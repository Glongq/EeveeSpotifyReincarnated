import Foundation

struct Work { let uri: URL }
struct Template { let creativeWork: Work }
class ArtistPage: NSObject {
    let template: Template
    init(_ uri: String) { template = Template(creativeWork: Work(uri: URL(string: uri)!)) }
}
final class InheritedPage: ArtistPage {}
final class UnrelatedPage: NSObject {
    let trackURI = URL(string: "spotify:artist:0123456789ABCDEFGHIJKL")!
}
struct StringWork { let uri: String }
struct StringTemplate { let creativeWork: StringWork }
final class StringPage: NSObject {
    let template: StringTemplate
    init(_ uri: String) { template = StringTemplate(creativeWork: StringWork(uri: uri)) }
}

let artist = "spotify:artist:0123456789ABCDEFGHIJKL"
let checks: [(AnyObject, String?)] = [
    (ArtistPage(artist), artist),
    (InheritedPage(artist), artist),
    (StringPage(artist), artist),
    (ArtistPage("spotify:album:0123456789ABCDEFGHIJKL"), nil),
    (ArtistPage("spotify:track:0123456789ABCDEFGHIJKL"), nil),
    (StringPage("spotify:artist:short"), nil),
    (StringPage("spotify:artist:0123456789ABCDEFGHIJK!"), nil),
    (StringPage(artist + "?other=true"), nil),
    (UnrelatedPage(), nil),
    (NSObject(), nil)
]
for (page, expected) in checks {
    let actual = PixieArtistIdentity.artistURI(page)
    precondition(actual == expected, "Unexpected artist identity: \(String(describing: actual))")
}
print("PASS: \(checks.count) artist model identity cases; no UI launched")
