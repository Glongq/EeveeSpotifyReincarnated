import Foundation

/// The context Spotify's player is in and whether it is playing, taken from the player observer.
/// Pages compare it with their own URI, which works in every language, unlike the play button's label.
final class PlayerContextState {
    static let shared = PlayerContextState()
    static let changed = Notification.Name("EeveePlayerContextStateChanged")

    private var contextKey: String?
    private var playing = false
    private var known = false

    private init() {}

    /// Call from the player observer with the raw SPTPlayerState.
    func update(from state: AnyObject) {
        func value(_ key: String) -> Any? {
            state.responds(to: Selector(key)) ? state.value(forKey: key) : nil
        }
        let uri = value("contextURI").flatMap { ($0 as? URL)?.absoluteString ?? $0 as? String }
        let isPaused = value("isPaused") as? Bool ?? false
        let playing = (value("isPlaying") as? Bool ?? false) && !isPaused
        let key = uri.flatMap(Self.key)
        DispatchQueue.main.async {
            guard !self.known || self.contextKey != key || self.playing != playing else { return }
            self.known = true
            self.contextKey = key
            self.playing = playing
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    /// Whether the page with this URI is the playing context, or nil before the player has reported.
    func isPlaying(page uri: String) -> Bool? {
        guard known else { return nil }
        return playing && contextKey != nil && contextKey == Self.key(uri)
    }

    // "type:id" from the last two components, so spotify:user:<name>:playlist:<id> and
    // spotify:playlist:<id> compare equal.
    private static func key(_ uri: String) -> String? {
        let parts = uri.split(separator: ":")
        guard parts.count >= 3, parts[0] == "spotify" else { return nil }
        return parts.suffix(2).joined(separator: ":")
    }
}
