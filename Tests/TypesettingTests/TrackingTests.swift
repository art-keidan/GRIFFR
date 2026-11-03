import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Tabella trak")
    struct TrackingTests {
        @Test("La tabella di Hoefler Text si legge come nella prova preliminare")
        func parseHoefler() throws {
            let table = try #require(Tracking.parse(try TestFonts.hoefler().tableBytes("trak")))
            #expect(table.sizes == [2, 10, 12, 24, 196, 197])
            #expect(table.tracks.map(\.track) == [-1, 0, 2])
            #expect(table.tracks[1].values == [100, 0, -20, -30, -100, -100])
        }

        @Test("Traccia normale di Hoefler Text ai vari corpi (unità del font su 2000)", arguments: [
            (1.0, 100.0), (2, 100), (6, 50), (10, 0), (11, -10), (12, -20), (18, -25), (24, -30), (196, -100), (500, -100),
        ])
        func interpolation(size: Double, expected: Double) throws {
            let table = try #require(Tracking.parse(try TestFonts.hoefler().tableBytes("trak")))
            #expect(abs(try #require(table.normalValue(atSize: size)) - expected) < 1e-9)
        }

        @Test("In punti: −0,36 a corpo 24, nulla a corpo 10, nulla per un font senza trak")
        func points() throws {
            #expect(abs(try #require(Tracking.normalTracking(for: try TestFonts.hoefler(size: 24))) + 0.36) < 1e-9)
            #expect(Tracking.normalTracking(for: try TestFonts.hoefler(size: 10)) == nil)
            #expect(Tracking.normalTracking(for: try TestFonts.vulcanius()) == nil)
        }

        @Test("Nella pagina la riga si stringe di 0,36 pt per glifo, senza perdere legature né kerning")
        func layoutAppliesTracking() throws {
            let text = NSAttributedString(string: "AVA officiating To", attributes: [.font: try TestFonts.hoefler(size: 24)])
            let plain = try #require(PageLayout.layout(text, appliesFontTracking: false).pages.first?.lines.first)
            let tracked = try #require(PageLayout.layout(text).pages.first?.lines.first)
            let plainGlyphs = Shaper.glyphs(in: plain.line), trackedGlyphs = Shaper.glyphs(in: tracked.line)
            #expect(plainGlyphs.map(\.id) == trackedGlyphs.map(\.id), "stessi glifi: la legatura ffi resta")
            #expect(trackedGlyphs.contains { $0.id == 631 })
            let difference = CTLineGetTypographicBounds(tracked.line, nil, nil, nil) - CTLineGetTypographicBounds(plain.line, nil, nil, nil)
            #expect(abs(difference + 0.36 * Double(plainGlyphs.count)) < 1e-6)
        }

        @Test("Nell'area di scrittura la spaziatura segue font e corpo, e si può togliere")
        func syncInEditorText() throws {
            let text = NSMutableAttributedString(string: "officiating", attributes: [.font: try TestFonts.hoefler(size: 24)])
            let all = NSRange(location: 0, length: text.length)
            func kern() -> Double? { (text.attribute(.kern, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue }

            TextStyling.syncFontTracking(in: text, range: all, enabled: true)
            #expect(abs(try #require(kern()) + 0.36) < 1e-9)
            TextStyling.syncFontTracking(in: text, range: all, enabled: true)
            #expect(abs(try #require(kern()) + 0.36) < 1e-9, "ripetere non accumula")

            TextStyling.setSize(12, in: text, range: all)
            TextStyling.syncFontTracking(in: text, range: all, enabled: true)
            #expect(abs(try #require(kern()) + 0.12) < 1e-9, "a corpo 12 la spaziatura è −0,12")

            TextStyling.setSize(10, in: text, range: all)
            TextStyling.syncFontTracking(in: text, range: all, enabled: true)
            #expect(kern() == nil, "a corpo 10 non c'è spaziatura e l'attributo sparisce")

            TextStyling.setSize(24, in: text, range: all)
            TextStyling.syncFontTracking(in: text, range: all, enabled: true)
            TextStyling.syncFontTracking(in: text, range: all, enabled: false)
            #expect(kern() == nil)
            #expect(text.attribute(.fontTracking, at: 0, effectiveRange: nil) == nil)
        }

        @Test("Il layout non conta due volte la spaziatura già presente nel testo dell'area di scrittura")
        func noDoubleCounting() throws {
            let clean = NSAttributedString(string: "AVA officiating To", attributes: [.font: try TestFonts.hoefler(size: 24)])
            let synced = NSMutableAttributedString(attributedString: clean)
            TextStyling.syncFontTracking(in: synced, range: NSRange(location: 0, length: synced.length), enabled: true)
            func width(_ text: NSAttributedString, tracking: Bool) throws -> Double {
                CTLineGetTypographicBounds(try #require(PageLayout.layout(text, appliesFontTracking: tracking).pages.first?.lines.first).line, nil, nil, nil)
            }
            #expect(abs(try width(synced, tracking: true) - width(clean, tracking: true)) < 1e-9)
            #expect(abs(try width(synced, tracking: false) - width(clean, tracking: false)) < 1e-9)
            // E il kerning del testo sincronizzato non finisce nel modello che si salva.
            #expect(Document(attributedString: synced) == Document(attributedString: clean))
        }

        @Test("Una riga giustificata con trak finisce esattamente al margine destro")
        func justifiedEdge() throws {
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let text = NSAttributedString(
                string: String(repeating: "The officiating minister affixed five stamps. ", count: 8),
                attributes: [.font: try TestFonts.hoefler(size: 24), .paragraphStyle: style])
            let setup = PageSetup.a4
            let first = try #require(PageLayout.layout(text, setup: setup).pages.first?.lines.first)
            // Fine dell'ultimo glifo visibile = larghezza − spazio finale − spaziatura aggiunta dopo l'ultimo glifo (−0,36).
            let width = CGFloat(CTLineGetTypographicBounds(first.line, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(first.line)) + 0.36
            #expect(abs(first.origin.x + width - setup.textRect.maxX) < 0.01)
        }
    }
}
