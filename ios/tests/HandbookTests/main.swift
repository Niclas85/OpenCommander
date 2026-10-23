import Foundation
assert(CommanderHandbook.moreAppsURL.absoluteString == "https://haenggi.vip/")
func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
let chapters = CommanderHandbook.anchors.map { CommanderHandbook.Chapter(id: $0, title: "Titel <&>\"", text: "Deutsch\n<script>alert('unsafe')</script>") }
let html = CommanderHandbook.html(chapters, german: true)
require(html.contains("lang=\"de\""), "language missing")
for anchor in CommanderHandbook.anchors {
    require(html.contains("id=\"\(anchor)\""), "missing chapter")
    require(html.contains("href=\"#\(anchor)\""), "missing chapter navigation")
}
require(!html.contains("<script>"), "unescaped executable content")
require(html.contains("&lt;script&gt;"), "text lost")
require(!html.contains("https://") && html.contains("default-src 'none'"), "external content enabled")
require(html.contains("<svg") && html.contains("role=\"img\""), "accessible illustration missing")
require(html.contains("@media print") && html.contains("break-after:avoid"), "print-friendly offline layout missing")
let invalid = CommanderHandbook.html([.init(id: "\"><script>", title: "bad", text: "bad")], german: false)
require(!invalid.contains("<script>"), "invalid chapter IDs accepted")
print("PASS offline handbook navigation, language, accessible illustration and HTML/CSP safety")
let baseIDs = ["anfang", "tastatur", "cloud", "uebertragungen", "probleme"]
for german in [true, false] {
    let base = baseIDs.map { CommanderHandbook.Chapter(id: $0, title: "Existing", text: "Preserve localized app guidance") }
    let complete = CommanderHandbook.complete(base + base, german: german)
    require(complete.count == 18 && complete.map(\.id) == CommanderHandbook.anchors, "eighteen-topic coverage or ordering missing")
    require(complete.filter { baseIDs.contains($0.id) }.allSatisfy { ["cloud", "tastatur", "uebertragungen"].contains($0.id) ? $0.text.hasPrefix(base[0].text + "\n\n") : $0.text == base[0].text }, "localized base descriptions replaced")
    let transfer = complete.first(where: { $0.id == "uebertragungen" })!.text
    require(transfer.contains(german ? "Ersetzen beim Online-Verschieben" : "Replace during an online move"), "replacement move guidance missing")
    require(transfer.contains(german ? "Löschauftrag" : "deletion job") && transfer.contains(german ? "Ordnerinhalt" : "folder contents") && transfer.contains(german ? "Zurücklegen" : "Put Back"), "deferred deletion scope, recursive folder proof and Finder recovery limitation missing")
    let keyboard = complete.first(where: { $0.id == "tastatur" })!.text
    require(keyboard.contains("native") && keyboard.contains("Command") && keyboard.contains("Option"), "native external drag guidance missing")
    require(keyboard.contains(german ? "Schalter" : "select Move"), "working external move alternative missing")
    require(complete.first(where: { $0.id == "cloud" })?.text.contains("PKCE") == true, "publisher desktop sign-in guidance missing")
    let media = complete.first(where: { $0.id == "medien" })!.text
    require(media.contains(german ? "Original beim Anbieter" : "provider original") && !media.contains("cannot yet be safely exported"), "media deletion/export guidance stale")
    let recovery = complete.first(where: { $0.id == "wiederherstellen" })!.text
    require(recovery.contains(german ? "gemeinsamen Historie" : "shared chronological History") && !recovery.contains("only in the same online session"), "persistent chronological Undo guidance stale")
    let sharing = complete.first(where: { $0.id == "teilen" })!.text
    require(sharing.contains("Dropbox") && sharing.contains(german ? "Abbrechen vor Erstellen" : "Cancel before Create"), "explicit provider-sharing consent guidance missing")
    let result = CommanderHandbook.html(complete, german: german)
    require(!result.contains("https://") && !result.contains("<script>"), "completed handbook loads outside content")
}
print("PASS complete eighteen-topic Mac handbook in German and English, deduplicated navigation and preserved localized base guidance")
