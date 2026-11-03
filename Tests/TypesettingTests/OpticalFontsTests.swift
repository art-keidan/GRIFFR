import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Corpi ottici statici")
    struct OpticalFontsTests {
        // Minion 3 arriva da Adobe Fonts: come fa l'app, lo si rende visibile a questo processo.
        // Servono anche i corpi ottici: in Adobe Fonts si possono attivare separatamente dalla famiglia di base.
        private static let installed = { FontLoader.registerAdobeFonts(); return ["Minion3-Regular", "Minion3Caption-Regular", "Minion3Subhead-Regular", "Minion3Display-Regular"].allSatisfy { NSFont(name: $0, size: 12) != nil } }()
        private static let ptInstalled = NSFont(name: "PTSans-Regular", size: 12) != nil

        private func font(_ name: String, _ size: CGFloat = 12) throws -> CTFont {
            try #require(NSFont(name: name, size: size)) as CTFont
        }

        @Test("Il raggruppamento è generale e non spezza nomi che contengono soltanto Text")
        func grouping() {
            let invented = OpticalFonts.families(["Example Caption", "Hoefler Text", "Example", "Example Display"])
            #expect(invented == ["Example", "Hoefler Text"])
            let families = OpticalFonts.families(["Minion 3 Caption", "Hoefler Text", "Minion 3", "Minion 3 Display", "Minion 3 Subhead"])
            #expect(families == ["Minion 3", "Hoefler Text"])
            // Questo guarda i font davvero installati: solo se ci sono i corpi ottici di Minion 3.
            if Self.installed { #expect(OpticalFonts.canonicalFamily("Minion 3 Caption") == "Minion 3") }
            #expect(OpticalFonts.canonicalFamily("Hoefler Text") == nil)
            #expect(OpticalFonts.automaticSize(forPointSize: 8.4) == .caption)
            #expect(OpticalFonts.automaticSize(forPointSize: 8.5) == .text)
            #expect(OpticalFonts.automaticSize(forPointSize: 13) == .text)
            #expect(OpticalFonts.automaticSize(forPointSize: 13.1) == .subhead)
            #expect(OpticalFonts.automaticSize(forPointSize: 20) == .display)
        }

        /// Una tabella `GPOS` minima con la sola funzione `size`; `historical` misura i parametri dall'elenco delle
        /// funzioni, come certi font vecchi, invece che dalla funzione.
        private func gpos(design: Int, subfamily: Int, start: Int, end: Int, historical: Bool = false) -> [UInt8] {
            func u16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xff), UInt8(v & 0xff)] }
            // Intestazione (10 byte), elenco delle funzioni a 10: conteggio, record «size» → funzione a 8 dall'elenco.
            // Funzione: scostamento dei parametri, conteggio degli indici di lookup (0). Parametri dopo la funzione.
            let paramsFromFeature = 4, paramsFromList = 12
            return u16(1) + u16(0) + u16(0) + u16(10) + u16(0)
                + u16(1) + Array("size".utf8) + u16(8)
                + u16(historical ? paramsFromList : paramsFromFeature) + u16(0)
                + u16(design) + u16(subfamily) + u16(256) + u16(start) + u16(end)
        }

        @Test("La funzione size si legge in entrambe le collocazioni dei parametri, e senza fascia resta senza fascia")
        func sizeFeature() throws {
            let modern = try #require(OpticalDeclaration.sizeFeature(gpos(design: 80, subfamily: 1, start: 59, end: 99)))
            #expect(modern.design == 8 && modern.subfamily == 1 && modern.lower == 5.9 && modern.upper == 9.9)
            let historical = try #require(OpticalDeclaration.sizeFeature(gpos(design: 360, subfamily: 1, start: 259, end: 720, historical: true)))
            #expect(historical.design == 36 && historical.lower == 25.9 && historical.upper == 72)
            let bare = try #require(OpticalDeclaration.sizeFeature(gpos(design: 110, subfamily: 0, start: 0, end: 0)))
            #expect(bare.lower == nil && bare.upper == nil)
            #expect(OpticalDeclaration(designSize: bare.design).isOptical == false, "un corpo di progetto senza fascia non è un corpo ottico")
            #expect(OpticalDeclaration.sizeFeature([]) == nil)
        }

        @Test("I nomi 16 e 21 si leggono preferendo il record Windows inglese")
        func nameTable() {
            func u16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xff), UInt8(v & 0xff)] }
            let mac = Array("Mac".utf8), windows = Array("Alpha".utf16).flatMap { u16(Int($0)) }, wws = Array("Alpha Petit".utf16).flatMap { u16(Int($0)) }
            let records = [(1, 0, 0, 16, mac.count, 0), (3, 1, 0x409, 16, windows.count, mac.count), (3, 1, 0x409, 21, wws.count, mac.count + windows.count)]
            let header = u16(0) + u16(records.count) + u16(6 + 12 * records.count)
            let table = header + records.flatMap { u16($0.0) + u16($0.1) + u16($0.2) + u16($0.3) + u16($0.4) + u16($0.5) } + mac + windows + wws
            #expect(OpticalDeclaration.names([16, 21], in: table) == [16: "Alpha", 21: "Alpha Petit"])
        }

        @Test("I gruppi vengono prima da ciò che i font dichiarano, poi dai nomi")
        func groupsFromDeclarations() throws {
            typealias D = OpticalFonts.FamilyDescription
            let groups = OpticalFonts.makeGroups([
                // Come Minion 3: niente nome 16, stessa sottofamiglia size, fasce contigue.
                D(family: "Example 3", declaration: OpticalDeclaration(designSize: 12, subfamily: 1, lower: 9.9, upper: 13.9)),
                D(family: "Example 3 Caption", declaration: OpticalDeclaration(designSize: 8, subfamily: 1, lower: 5.9, upper: 9.9)),
                D(family: "Example 3 Display", declaration: OpticalDeclaration(designSize: 36, subfamily: 1, lower: 25.9, upper: 72)),
                // Come Minion Pro IE: stesso corpo di progetto, quindi non un corpo ottico dell'altro.
                D(family: "Example Pro", declaration: OpticalDeclaration(designSize: 11, subfamily: 3, lower: 8.4, upper: 13)),
                D(family: "Example Pro IE", declaration: OpticalDeclaration(designSize: 11, subfamily: 3, lower: 8.4, upper: 13)),
                // Nomi 16 e 21, e nomi di famiglia che non dicono nulla del corpo.
                D(family: "Alpha Petit", declaration: OpticalDeclaration(designSize: 7, typographicFamily: "Alpha", wwsFamily: "Alpha Petit")),
                D(family: "Alpha Grand", declaration: OpticalDeclaration(designSize: 30, typographicFamily: "Alpha", wwsFamily: "Alpha Grand")),
                // Il solo nome 16 divide i pesi, non i corpi.
                D(family: "Beta", declaration: OpticalDeclaration(typographicFamily: "Beta")),
                D(family: "Beta Black", declaration: OpticalDeclaration(typographicFamily: "Beta")),
                // Nessuna dichiarazione: vale ancora il nome.
                D(family: "Gamma", declaration: nil), D(family: "Gamma Caption", declaration: nil),
            ])
            let example = try #require(groups.first { $0.family == "Example 3" })
            #expect(example.variants == [.text: "Example 3", .caption: "Example 3 Caption", .display: "Example 3 Display"])
            #expect(example.ranges["Example 3 Caption"] == 5.9...9.9)
            let alpha = try #require(groups.first { $0.family == "Alpha" })
            #expect(alpha.variants == [.caption: "Alpha Petit", .display: "Alpha Grand"])
            #expect(!groups.contains { $0.family.hasPrefix("Example Pro") || $0.family == "Beta" })
            #expect(groups.first { $0.family == "Gamma" }?.variants == [.text: "Gamma", .caption: "Gamma Caption"])

            // La fascia dichiarata decide: estremo inferiore escluso, superiore compreso; fuori, il corpo più vicino.
            #expect(OpticalFonts.automaticFamily(in: example, pointSize: 9) == "Example 3 Caption")
            #expect(OpticalFonts.automaticFamily(in: example, pointSize: 9.9) == "Example 3 Caption")
            #expect(OpticalFonts.automaticFamily(in: example, pointSize: 10) == "Example 3")
            #expect(OpticalFonts.automaticFamily(in: example, pointSize: 4) == "Example 3 Caption")
            #expect(OpticalFonts.automaticFamily(in: example, pointSize: 120) == "Example 3 Display")
            // Senza fasce valgono le soglie di ripiego, e un corpo assente cede al più vicino.
            let gamma = try #require(groups.first { $0.family == "Gamma" })
            #expect(OpticalFonts.automaticFamily(in: gamma, pointSize: 7) == "Gamma Caption")
            #expect(OpticalFonts.automaticFamily(in: gamma, pointSize: 36) == "Gamma")
        }

        @Test("I corpi ottici dentro il nome dello stile si riconoscono e si ricompongono")
        func styleNames() {
            #expect(OpticalFonts.splitStyle("Light Italic Caption")! == ("Light Italic", .caption, "Caption"))
            #expect(OpticalFonts.splitStyle("Caption")! == ("Regular", .caption, "Caption"))
            #expect(OpticalFonts.splitStyle("Semibold Subh")! == ("Semibold", .subhead, "Subh"))
            #expect(OpticalFonts.splitStyle("Bold Italic") == nil)
            #expect(OpticalFonts.splitStyle("Text") == nil, "«Text» da solo non è un corpo da togliere")
            #expect(OpticalFonts.joinStyle("Regular", "Display") == "Display")
            #expect(OpticalFonts.joinStyle("Light Italic", "Caption") == "Light Italic Caption")
            #expect(OpticalFonts.joinStyle("Bold", "") == "Bold")
        }

        // Warnock Pro: i corpi ottici sono facce della stessa famiglia, non famiglie a sé.
        private static let warnock = { FontLoader.registerAdobeFonts(); return NSFont(name: "WarnockPro-LightCapt", size: 12) != nil }()

        @Test("Warnock: i corpi ottici escono dai pesi e seguono il corpo", .enabled(if: warnock))
        func warnockInFamily() throws {
            let styles = OpticalFonts.members(ofFamily: "Warnock Pro").compactMap { $0[1] as? String }
            #expect(!styles.isEmpty && !styles.contains { $0.contains("Capt") || $0.contains("Subh") || $0.contains("Disp") },
                    "i pulsanti dei pesi non vedono Caption, Subhead, Display: \(styles)")
            #expect(styles.contains("Light") && styles.contains("Semibold Italic"))
            let light = try font("WarnockPro-Light", 12)
            #expect(OpticalFonts.availableSizes(of: light) == [.caption, .text, .subhead, .display])
            #expect(TextStyling.resized(light, to: 7).postScriptName == "WarnockPro-LightCapt")
            #expect(TextStyling.resized(light, to: 11).postScriptName == "WarnockPro-Light")
            #expect(TextStyling.resized(light, to: 30).postScriptName == "WarnockPro-LightDisp")
            let caption = try font("WarnockPro-SemiboldItCapt", 7)
            #expect(OpticalFonts.opticalSize(of: caption) == .caption)
            #expect(OpticalFonts.baseFaceName(of: caption) == "WarnockPro-SemiboldIt")
            #expect(OpticalFonts.font(caption, opticalSize: .subhead).postScriptName == "WarnockPro-SemiboldItSubh")
            #expect(OpticalFonts.family(of: caption) == "Warnock Pro")
        }

        @Test("Minion 3 segue le fasce che dichiara, non le soglie fisse", .enabled(if: installed))
        func minionDeclaredRanges() throws {
            let text = try font("Minion3-Regular", 12)
            #expect(OpticalDeclaration(font: text).range == 9.9...13.9)
            #expect(TextStyling.resized(text, to: 9).postScriptName == "Minion3Caption-Regular", "9 pt è nella fascia del Caption (5,9–9,9)")
            #expect(TextStyling.resized(text, to: 13.95).postScriptName == "Minion3Subhead-Regular")
            #expect(TextStyling.resized(text, to: 25).postScriptName == "Minion3Subhead-Regular", "25 pt è ancora Subhead (13,9–25,9)")
            #expect(TextStyling.resized(text, to: 26).postScriptName == "Minion3Display-Regular")
        }

        @Test("Anche un font non Adobe cambia corpo conservando la faccia e offre solo le varianti esistenti", .enabled(if: ptInstalled))
        func nonAdobeFamily() throws {
            #expect(OpticalFonts.canonicalFamily("PT Sans Caption") == "PT Sans")
            let caption = OpticalFonts.font(try font("PTSans-Bold", 7), opticalSize: nil)
            #expect(caption.postScriptName == "PTSans-CaptionBold")
            #expect(OpticalFonts.baseFaceName(of: caption) == "PTSans-Bold")
            #expect(OpticalFonts.family(of: caption) == "PT Sans")
            #expect(OpticalFonts.availableSizes(of: caption) == [.caption, .text])
            #expect(OpticalFonts.font(caption, opticalSize: .display).postScriptName == caption.postScriptName)
            // In automatico un corpo che la famiglia non ha cede al più vicino: a 36 pt il PT Sans normale.
            #expect(OpticalFonts.font(TextStyling.resizedWithoutOpticalSize(caption, to: 36), opticalSize: nil).postScriptName == "PTSans-Bold")
        }

        @Test("Cambiare corpo ottico conserva esattamente peso e corsivo", .enabled(if: installed))
        func sameFaceAcrossOpticalSizes() throws {
            let boldItalic = try font("Minion3-BoldItalic")
            let caption = OpticalFonts.font(boldItalic, opticalSize: .caption)
            let subhead = OpticalFonts.font(boldItalic, opticalSize: .subhead)
            let display = OpticalFonts.font(boldItalic, opticalSize: .display)
            #expect(caption.postScriptName == "Minion3Caption-BoldItalic")
            #expect(subhead.postScriptName == "Minion3Subhead-BoldItalic")
            #expect(display.postScriptName == "Minion3Display-BoldItalic")
            #expect(OpticalFonts.baseFaceName(of: display) == "Minion3-BoldItalic")
            #expect(OpticalFonts.family(of: display) == "Minion 3")
        }

        @Test("In automatico il corpo sceglie la variante; quella fissa non si sposta", .enabled(if: installed))
        func automaticAndFixedResizing() throws {
            let text = try font("Minion3-Semibold", 12)
            #expect(TextStyling.resized(text, to: 7).postScriptName == "Minion3Caption-Semibold")
            #expect(TextStyling.resized(text, to: 16).postScriptName == "Minion3Subhead-Semibold")
            #expect(TextStyling.resized(text, to: 36).postScriptName == "Minion3Display-Semibold")
            let fixed = OpticalFonts.resized(text, to: 36, opticalSize: .caption)
            #expect(fixed.postScriptName == "Minion3Caption-Semibold" && fixed.pointSize == 36)
        }

        @Test("La scelta ottica si scrive nel documento e si rilegge; automatico è il predefinito", .enabled(if: installed))
        func fileRoundTrip() throws {
            let fixed = CharacterStyle(fontName: "Minion3-Bold", size: 36, opticalSize: .caption)
            let automatic = CharacterStyle(fontName: "Minion3-Bold", size: 36)
            var opticalValues = StyleValues()
            opticalValues.opticalSize = "caption"
            let styles = StyleSheet(styles: [NamedStyle(name: "Ottico", target: .character, values: opticalValues)])
            let document = Document(styles: styles, blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("fisso ", style: fixed)), .text(TextRun("automatico", style: automatic)),
            ]))])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("optical=\"caption\""))
            #expect(try DocumentFormat.document(from: written) == document)
            let attributed = document.attributedString().text
            #expect((attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Minion3Caption-Bold")
            #expect((attributed.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)?.fontName == "Minion3Display-Bold")
            #expect(attributed.attribute(.fontOpticalSize, at: 0, effectiveRange: nil) as? String == "caption")
            #expect(attributed.attribute(.fontOpticalSize, at: 6, effectiveRange: nil) == nil)
            #expect(throws: DocumentFormatError.invalidValue(line: 1, attribute: "optical", value: "enorme")) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"Minion3-Regular\" size=\"12\" optical=\"enorme\"><p>x</p></document>")
            }
        }
    }
}
