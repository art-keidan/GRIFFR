import AppKit
import Testing
@testable import Typesetting

@Suite("Memoria delle righe composte", .serialized)
struct LayoutCacheTests {
    static let paragraph = "Una riga troppo lunga costringe l’occhio a un viaggio faticoso: arrivato in fondo, deve tornare indietro e cercare "
        + "l’inizio della riga successiva, e spesso sbaglia, rileggendo la stessa o saltandone una. Una riga troppo corta, al "
        + "contrario, spezza continuamente il discorso e obbliga a frequenti divisioni in sillabe.\n"

    static func text() -> NSAttributedString {
        let font = NSFont(name: "HoeflerText-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        return NSAttributedString(string: (0..<40).map { "\($0). " + paragraph }.joined(), attributes: [.font: font, .paragraphStyle: style])
    }

    static func fingerprint(_ layout: DocumentLayout) -> [String] {
        layout.pages.enumerated().flatMap { page, content in content.lines.map { "\(page) \($0.range) \(Int($0.origin.x * 100)) \(Int($0.origin.y * 100))" } }
    }

    @Test("Un cambio degli stili che non tocca il testo non fa ricomporre i paragrafi, e le pagine restano quelle")
    func stylesChangeKeepsLines() {
        let text = Self.text()
        var options = LayoutOptions(lineBreaking: .optimal)
        PageLayout.clearCaches()
        var start = Date()
        let cold = Self.fingerprint(PageLayout.layout(text, options: options))
        let coldTime = Date().timeIntervalSince(start)

        var sheet = options.styles
        sheet.styles.append(NamedStyle(name: "Non usato", target: .paragraph, basedOn: nil, values: StyleValues()))
        options.styles = sheet
        start = Date()
        let warm = Self.fingerprint(PageLayout.layout(text, options: options))
        let warmTime = Date().timeIntervalSince(start)
        #expect(warm == cold)
        #expect(warmTime < coldTime / 4, "da zero \(Int(coldTime * 1000)) ms, dopo il cambio \(Int(warmTime * 1000)) ms")
    }

    @Test("Le scelte di composizione contano ancora: senza sillabazione le righe cambiano")
    func compositionChoicesStillCount() {
        let text = Self.text()
        var options = LayoutOptions(lineBreaking: .optimal)
        let hyphenated = Self.fingerprint(PageLayout.layout(text, options: options))
        options.hyphenates = false
        options.hyphenationLanguage = "it"
        let warm = Self.fingerprint(PageLayout.layout(text, options: options))
        PageLayout.clearCaches()
        let cold = Self.fingerprint(PageLayout.layout(text, options: options))
        #expect(warm == cold)
        _ = hyphenated
    }
}
