import EeveeSpotifyC
import Orion
import UIKit

struct PixieNativeArtistDownloadsGroup: HookGroup {}

class PixieArtistHeaderHook: ClassHook<UIView> {
    typealias Group = PixieNativeArtistDownloadsGroup
    static let targetName = "_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView"

    func layoutSubviews() {
        orig.layoutSubviews()
        EeveePixieUpdateArtistDownloads(target, nil)
    }
}

class PixieArtistRowHook: ClassHook<UIStackView> {
    typealias Group = PixieNativeArtistDownloadsGroup
    static let headerClass = NSClassFromString(PixieArtistHeaderHook.targetName)

    func layoutSubviews() {
        orig.layoutSubviews()
        guard let header = target.superview, let headerClass = Self.headerClass,
              header.isKind(of: headerClass) else { return }
        EeveePixieUpdateArtistDownloads(header, nil)
    }
}

func activatePixieArtistDownloads() {
    if #available(iOS 26.0, *) {
        let options = LiquidGlass.launchOptions
        if options.enabled && options.playlist != false { return }
    }
    guard NSClassFromString(PixieArtistHeaderHook.targetName) != nil else { return }
    PixieNativeArtistDownloadsGroup().activate()
}
