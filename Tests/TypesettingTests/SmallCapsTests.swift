import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// Il maiuscoletto come scelta tipografica: nel documento si registra cosa si vuole, e le forme tecniche si scelgono
    /// quando si compone, fra quelle che il font conosce. Font di prova: Hoefler Text (forma AAT 3/3, niente
    /// maiuscoletto delle sigle) e Baskerville.
    @Suite("Maiuscoletto come proprietà")
    struct SmallCapsTests {
        private func shownSettings(_ text: NSAttributedString, at index: Int) throws -> [FeatureSetting] {
            let font = try #require(text.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
            return FontFeatures.settings(of: font as CTFont)
        }

        @Test("Un file di prima: le forme del maiuscoletto fra le funzioni diventano la proprietà, e si riscrivono così")
        func oldFile() throws {
            let document = try DocumentFormat.document(from: """
            <document version="1" font="HoeflerText-Regular" size="12">
            <styles>
            <style name="Maiuscoletto" target="character" features="3/3 37/1 smcp=1"/>
            <style name="Sigle e legature" target="character" features="38/1 c2sc=1 1/4"/>
            </styles>
            <p>Testo con <t features="3/3">maiuscoletto</t> e <t char-style="Maiuscoletto">stile</t>.</p>
            </document>
            """)
            let caps = try #require(document.styles.style(named: "Maiuscoletto")?.values)
            #expect(caps.smallCaps == .lowercase)
            #expect(caps.features == nil, "lo stile non fissa più funzioni")
            let mixed = try #require(document.styles.style(named: "Sigle e legature")?.values)
            #expect(mixed.smallCaps == .uppercase)
            #expect(mixed.features == [.aat(type: 1, selector: 4)], "le altre funzioni restano")
            guard case .paragraph(let paragraph) = document.blocks[0], case .text(let run) = paragraph.inlines[1] else {
                Issue.record("il paragrafo manca"); return
            }
            #expect(run.style.smallCaps == .lowercase && run.style.features == [])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<t small-caps=\"lowercase\">maiuscoletto</t>"))
            #expect(written.contains("<style name=\"Maiuscoletto\" target=\"character\" small-caps=\"lowercase\"/>"))
            #expect(!written.contains("3/3"))
            #expect(try DocumentFormat.document(from: written) == document)
        }

        @Test("Nel file il maiuscoletto si eredita, ma si ripete dove cambiano font o funzioni: la rilettura è identica")
        func inheritanceRoundTrip() throws {
            let caps = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, smallCaps: .lowercase)
            let other = CharacterStyle(fontName: "Baskerville", size: 12, smallCaps: .lowercase)
            let rare = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, features: [.aat(type: 1, selector: 4)], smallCaps: .lowercase)
            let plain = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let document = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Tutto ", style: caps)), .text(TextRun("in ", style: other)),
                                               .text(TextRun("maiuscoletto ", style: rare)), .text(TextRun("qui.", style: caps))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Testo liscio.", style: plain))])),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<p small-caps=\"lowercase\">"))
            #expect(written.contains("<t font=\"Baskerville\" small-caps=\"lowercase\">in </t>"))
            #expect(written.contains("<t features=\"1/4\" small-caps=\"lowercase\">maiuscoletto </t>"))
            #expect(try DocumentFormat.document(from: written) == document)
        }

        @Test("Cambiando famiglia il maiuscoletto resta, e il font nuovo usa la sua forma")
        func otherFamily() throws {
            let text = NSMutableAttributedString(string: "Una prova", attributes: TextStyling.characterAttributes(
                for: CharacterStyle(fontName: "HoeflerText-Regular", size: 12, smallCaps: .lowercase)).attributes)
            #expect(try shownSettings(text, at: 0) == [.aat(type: 3, selector: 3)])
            var family = StyleValues()
            family.family = "Baskerville"
            TextStyling.setValue(family, of: .family, in: text, range: NSRange(location: 0, length: text.length))
            let style = try #require(TextStyling.characterStyle(in: text, at: 0))
            #expect(style.fontName.hasPrefix("Baskerville"))
            #expect(style.smallCaps == .lowercase)
            #expect(try SmallCaps.split(shownSettings(text, at: 0)).smallCaps == .lowercase, "Baskerville mostra il maiuscoletto nella sua forma")
        }

        @Test("Il maiuscoletto delle sigle resta registrato anche dove il font non l'ha")
        func missingForm() throws {
            let style = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, smallCaps: .uppercase)
            let text = NSMutableAttributedString(string: "ONU", attributes: TextStyling.characterAttributes(for: style).attributes)
            #expect(try shownSettings(text, at: 0) == [], "Hoefler Text non ha la forma: il testo non cambia")
            #expect(TextStyling.characterStyle(in: text, at: 0)?.smallCaps == .uppercase)
            let written = DocumentFormat.string(for: Document(attributedString: text))
            #expect(written.contains("small-caps=\"uppercase\""))
        }

        @Test("Dal pannello delle funzioni: accendere o spegnere la forma del maiuscoletto cambia la proprietà")
        func featurePanel() throws {
            let text = NSMutableAttributedString(string: "Una prova", attributes: TextStyling.characterAttributes(
                for: CharacterStyle(fontName: "HoeflerText-Regular", size: 12)).attributes)
            let all = NSRange(location: 0, length: text.length)
            TextStyling.updateFeatures(in: text, range: all, ofFontNamed: "HoeflerText-Regular") { $0 + [.aat(type: 3, selector: 3)] }
            #expect(TextStyling.characterStyle(in: text, at: 0)?.smallCaps == .lowercase)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.features == [])
            TextStyling.updateFeatures(in: text, range: all, ofFontNamed: "HoeflerText-Regular") { $0.filter { $0 != .aat(type: 3, selector: 3) } }
            #expect(TextStyling.characterStyle(in: text, at: 0)?.smallCaps == .off)
            #expect(try shownSettings(text, at: 0) == [])
        }

        @Test("Il maiuscoletto delle sigle registrato sopravvive a una funzione cambiata dal pannello")
        func panelKeepsRecorded() throws {
            let style = CharacterStyle(fontName: "HoeflerText-Regular", size: 12, smallCaps: .uppercase)
            let text = NSMutableAttributedString(string: "ONU", attributes: TextStyling.characterAttributes(for: style).attributes)
            TextStyling.updateFeatures(in: text, range: NSRange(location: 0, length: text.length), ofFontNamed: "HoeflerText-Regular") { $0 + [.aat(type: 1, selector: 4)] }
            #expect(TextStyling.characterStyle(in: text, at: 0)?.smallCaps == .uppercase)
            #expect(TextStyling.characterStyle(in: text, at: 0)?.features == [.aat(type: 1, selector: 4)])
        }
    }
}
