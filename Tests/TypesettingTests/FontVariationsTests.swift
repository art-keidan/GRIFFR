import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// Il font di prova è Skia, il font a più assi che macOS porta con sé (assi peso e larghezza).
    @Suite("Font a più assi")
    struct FontVariationsTests {
        private func skia(_ name: String = "Skia-Regular", size: CGFloat = 24) throws -> CTFont {
            try #require(NSFont(name: name, size: size)) as CTFont
        }

        private func width(_ font: CTFont, _ text: String = "Hamburg") -> CGFloat {
            Shaper.glyphs(for: text, font: font).map(\.advance).reduce(0, +)
        }

        @Test("Gli assi di Skia: peso e larghezza, con i loro limiti; un font normale non ne ha")
        func axes() throws {
            let axes = FontVariations.axes(of: try skia())
            #expect(axes.map(\.tag) == ["wght", "wdth"])
            #expect(abs(axes[0].minimum - 0.48) < 0.001 && axes[0].defaultValue == 1 && abs(axes[0].maximum - 3.2) < 0.001)
            #expect(abs(axes[1].minimum - 0.62) < 0.001 && axes[1].defaultValue == 1 && abs(axes[1].maximum - 1.3) < 0.001)
            #expect(FontVariations.axes(of: try TestFonts.hoefler()).isEmpty)
            #expect(FontVariations.values(of: try TestFonts.hoefler()).isEmpty)
        }

        @Test("Una faccia con un nome è il font di base più i valori dei suoi assi")
        func namedInstances() throws {
            #expect(FontVariations.values(of: try skia()).isEmpty)
            let bold = try skia("Skia-Regular_Bold")
            #expect(FontVariations.values(of: bold) == [AxisValue(tag: "wght", value: 1.9499)])
            #expect(FontVariations.baseName(of: bold) == "Skia-Regular")
            #expect(FontVariations.values(of: try skia("Skia-Regular_Light-Condensed")) == [AxisValue(tag: "wght", value: 0.4799), AxisValue(tag: "wdth", value: 0.6999)])
            #expect(CharacterStyle(bold) == CharacterStyle(fontName: "Skia-Regular", size: 24, variations: [AxisValue(tag: "wght", value: 1.9499)]))
        }

        @Test("Spostare gli assi cambia il disegno; gli assi non nominati tornano al predefinito, i valori fuori limite al limite")
        func customInstance() throws {
            let regular = try skia()
            let custom = FontVariations.font(regular, with: [AxisValue(tag: "wght", value: 2.3), AxisValue(tag: "wdth", value: 0.8)])
            #expect(FontVariations.values(of: custom) == [AxisValue(tag: "wght", value: 2.3), AxisValue(tag: "wdth", value: 0.8)])
            #expect(CTFontGetSize(custom) == 24)
            // Più nero ma più stretto: «Hamburg» a corpo 24 misura 91,71 punti, meno che nel tondo.
            #expect(abs(width(custom) - 91.711) < 0.01)
            #expect(width(custom) < width(regular) - 5)
            #expect(FontVariations.baseName(of: custom) == "Skia-Regular")

            // Solo la larghezza: il peso torna al predefinito.
            let narrow = FontVariations.font(custom, with: [AxisValue(tag: "wdth", value: 0.8)])
            #expect(FontVariations.values(of: narrow) == [AxisValue(tag: "wdth", value: 0.8)])
            #expect(FontVariations.font(custom, with: []).postScriptName == "Skia-Regular")
            // Oltre il massimo ci si ferma al massimo.
            let heaviest = FontVariations.font(regular, with: [AxisValue(tag: "wght", value: 99)])
            #expect(FontVariations.values(of: heaviest) == [AxisValue(tag: "wght", value: 3.1999)])
            // Un asse che il font non ha viene ignorato; su un font senza assi non cambia nulla.
            #expect(FontVariations.values(of: FontVariations.font(regular, with: [AxisValue(tag: "opsz", value: 12)])).isEmpty)
            let hoefler = try TestFonts.hoefler()
            #expect(FontVariations.font(hoefler, with: [AxisValue(tag: "wght", value: 2)]) === hoefler)
        }

        @Test("Assi, funzioni e corpo non si disturbano a vicenda")
        func coexistence() throws {
            let variations = [AxisValue(tag: "wght", value: 2.3), AxisValue(tag: "wdth", value: 0.8)]
            let custom = FontVariations.font(try skia(), with: variations)
            // Una funzione qualsiasi tra quelle che Skia dichiara.
            let type = try #require(FontFeatures.types(of: custom).first { !$0.isExclusive })
            let selector = try #require(type.selectors.first { !type.isOn($0, in: []) })
            let settings = type.setting(selector, on: true, in: [])

            let withFeature = FontFeatures.font(custom, with: settings)
            #expect(FontVariations.values(of: withFeature) == variations)
            #expect(FontFeatures.settings(of: withFeature) == settings)
            let moved = FontVariations.font(withFeature, with: [AxisValue(tag: "wght", value: 1.5)])
            #expect(FontFeatures.settings(of: moved) == settings)
            #expect(FontVariations.values(of: moved) == [AxisValue(tag: "wght", value: 1.5)])
            let resized = TextStyling.resized(withFeature, to: 11)
            #expect(FontVariations.values(of: resized) == variations && FontFeatures.settings(of: resized) == settings && CTFontGetSize(resized) == 11)
            #expect(FontFeatures.font(withFeature, with: []).postScriptName == custom.postScriptName)
        }

        // Merriweather non è un font del sistema: la prova si fa solo dove è installato.
        @Test("La dimensione ottica regolata da Core Text secondo il corpo non viene fissata per sbaglio",
              .enabled(if: NSFont(name: "Merriweather-Regular", size: 12) != nil))
        func automaticOpticalSize() throws {
            let large = try #require(NSFont(name: "Merriweather-Regular", size: 60)) as CTFont
            // A corpo 60 Core Text porta da sé l'asse a 60 (il predefinito è 18).
            #expect(FontVariations.coordinates(of: large)["opsz"] == 60)
            // Per noi è fissato solo il peso: la dimensione ottica resta libera di seguire il corpo.
            #expect(FontVariations.values(of: large) == [AxisValue(tag: "wght", value: 400)])
            #expect(CharacterStyle(large) == CharacterStyle(fontName: "Merriweather-Light", size: 60, variations: [AxisValue(tag: "wght", value: 400)]))

            let bold = FontVariations.font(large, with: [AxisValue(tag: "wght", value: 700)])
            #expect(FontVariations.coordinates(of: bold)["opsz"] == 60)
            #expect(FontVariations.coordinates(of: TextStyling.resized(bold, to: 100))["opsz"] == 100)
            #expect(FontVariations.values(of: TextStyling.resized(bold, to: 100)) == [AxisValue(tag: "wght", value: 700)])
            // Anche passando dal modello: il font ricostruito segue il corpo.
            let rebuilt = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("x", style: CharacterStyle(bold)))]))]).attributedString().text
            #expect(FontVariations.coordinates(of: rebuilt.attribute(.font, at: 0, effectiveRange: nil) as! NSFont as CTFont) == ["wght": 700, "wdth": 100, "opsz": 60])

            // Fissata esplicitamente, la dimensione ottica non segue più il corpo, e si scrive nel file.
            let pinned = FontVariations.font(bold, with: [AxisValue(tag: "wght", value: 700), AxisValue(tag: "opsz", value: 30)])
            #expect(FontVariations.values(of: pinned) == [AxisValue(tag: "wght", value: 700), AxisValue(tag: "opsz", value: 30)])
            #expect(FontVariations.coordinates(of: TextStyling.resized(pinned, to: 100))["opsz"] == 30)
            // Tolta dall'elenco, torna a seguirlo.
            #expect(FontVariations.coordinates(of: FontVariations.font(pinned, with: [AxisValue(tag: "wght", value: 700)]))["opsz"] == 60)

            // L'interruttore congela il valore effettivo: al clic non cambia nulla, al cambio di corpo resta fermo.
            let frozen = FontVariations.font(bold, automaticOpticalSize: false)
            let frozenCoordinate = try #require(FontVariations.coordinates(of: frozen)["opsz"])
            #expect(abs(frozenCoordinate - 60) < 0.001)
            #expect(FontVariations.coordinates(of: TextStyling.resized(frozen, to: 100))["opsz"] == frozenCoordinate)
            let automatic = FontVariations.font(TextStyling.resized(frozen, to: 100), automaticOpticalSize: true)
            #expect(!FontVariations.values(of: automatic).contains { $0.tag == "opsz" })
            #expect(FontVariations.coordinates(of: automatic)["opsz"] == 100)
        }

        // MARK: La stessa famiglia installata come font a più assi e in file statici

        /// Noto Sans su questo Mac è installato in tutti e due i modi; altrove queste prove non si fanno.
        private static var notoSansInstalledTwice: Bool {
            guard let byName = NSFont(name: "NotoSans-Bold", size: 12), !FontVariations.isVariable(byName as CTFont),
                  let variable = FontVariations.font(named: "NotoSans-Bold", size: 12, preferringVariable: true) else { return false }
            return FontVariations.isVariable(variable)
        }

        @Test("Per nome macOS apre il file statico; chiedendolo, si ottiene il font a più assi", .enabled(if: notoSansInstalledTwice))
        func staticAndVariable() throws {
            let staticBold = try #require(FontVariations.font(named: "NotoSans-Bold", size: 24, preferringVariable: false))
            let variableBold = try #require(FontVariations.font(named: "NotoSans-Bold", size: 24, preferringVariable: true))
            #expect(!FontVariations.isVariable(staticBold) && FontVariations.isVariable(variableBold))
            #expect(FontVariations.fileURL(of: staticBold)?.lastPathComponent == "NotoSans-Bold.ttf")
            #expect(FontVariations.fileURL(of: variableBold)?.lastPathComponent == "NotoSans-VariableFont_wdth,wght.ttf")
            // La faccia è la stessa: il nero del font a più assi è il font di base con il peso a 700.
            #expect(FontVariations.baseName(of: variableBold) == "NotoSans-Regular")
            #expect(FontVariations.values(of: variableBold) == [AxisValue(tag: "wght", value: 700)])
            #expect(abs(width(staticBold) - width(variableBold)) < width(staticBold) * 0.01)

            // Il passaggio da un'installazione all'altra, nei due sensi.
            let switched = try #require(FontVariations.counterpart(of: staticBold, variable: true))
            #expect(FontVariations.isVariable(switched) && FontVariations.values(of: switched) == [AxisValue(tag: "wght", value: 700)] && CTFontGetSize(switched) == 24)
            let back = try #require(FontVariations.counterpart(of: switched, variable: false))
            #expect(back.postScriptName == "NotoSans-Bold" && !FontVariations.isVariable(back))
            // Skia è installato in un modo solo.
            #expect(FontVariations.counterpart(of: try skia(), variable: false) == nil)
            #expect(!FontVariations.isShadowed(try skia()))
        }

        @Test("Spostando assi, funzioni e corpo si resta nel font a più assi, anche se il nome porterebbe al file statico", .enabled(if: notoSansInstalledTwice))
        func shadowedFontKeepsItsFile() throws {
            let regular = try #require(FontVariations.font(named: "NotoSans-Regular", size: 24, preferringVariable: true))
            #expect(FontVariations.isShadowed(regular))
            func isVariableFile(_ font: CTFont) -> Bool { FontVariations.fileURL(of: font)?.lastPathComponent == "NotoSans-VariableFont_wdth,wght.ttf" }
            let custom = FontVariations.font(regular, with: [AxisValue(tag: "wght", value: 555)])
            #expect(isVariableFile(custom) && FontVariations.values(of: custom) == [AxisValue(tag: "wght", value: 555)])

            // Una funzione qualsiasi tra quelle che il font dichiara e che non è già attiva.
            let settings = try #require(FontFeatures.types(of: custom).lazy.filter { !$0.isExclusive }.compactMap { type in
                type.selectors.first { !type.isOn($0, in: []) }.map { type.setting($0, on: true, in: []) }
            }.first)
            let withFeature = FontFeatures.font(custom, with: settings)
            #expect(isVariableFile(withFeature) && FontVariations.values(of: withFeature) == [AxisValue(tag: "wght", value: 555)])
            #expect(FontFeatures.settings(of: withFeature) == settings)
            let cleared = FontFeatures.font(withFeature, with: [])
            #expect(isVariableFile(cleared) && FontFeatures.settings(of: cleared).isEmpty && FontVariations.values(of: cleared) == [AxisValue(tag: "wght", value: 555)])
            #expect(isVariableFile(TextStyling.resized(withFeature, to: 11)))
            #expect(isVariableFile(FontVariations.font(withFeature, with: [])) && FontVariations.values(of: FontVariations.font(withFeature, with: [])).isEmpty)
        }

        @Test("Nel file la scelta del font a più assi si scrive con variable, o è sottintesa dagli assi", .enabled(if: notoSansInstalledTwice))
        func variableChoiceInFile() throws {
            let plain = CharacterStyle(fontName: "NotoSans-Regular", size: 12)
            let variable = CharacterStyle(fontName: "NotoSans-Regular", size: 12, prefersVariableFont: true)
            let heavy = CharacterStyle(fontName: "NotoSans-Regular", size: 12, variations: [AxisValue(tag: "wght", value: 555)])
            let document = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("statico ", style: plain)), .text(TextRun("a più assi ", style: variable)), .text(TextRun("su misura", style: heavy))])),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<p>statico <t variable=\"on\">a più assi </t><t axes=\"wght=555\">su misura</t></p>"))
            #expect(try DocumentFormat.document(from: written) == document)

            let text = document.attributedString().text
            func font(_ word: String) -> CTFont { text.attribute(.font, at: (text.string as NSString).range(of: word).location, effectiveRange: nil) as! NSFont as CTFont }
            #expect(!FontVariations.isVariable(font("statico")))
            #expect(FontVariations.isVariable(font("a più assi")) && FontVariations.values(of: font("a più assi")).isEmpty)
            #expect(FontVariations.values(of: font("su misura")) == [AxisValue(tag: "wght", value: 555)])
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)

            // Il passaggio su una selezione tocca solo i tratti di quella famiglia che stanno dall'altra parte.
            let mutable = NSMutableAttributedString(attributedString: text)
            #expect(TextStyling.switchFontFile(in: mutable, range: NSRange(location: 0, length: mutable.length), family: "Noto Sans", variable: true) == 1)
            #expect(FontVariations.isVariable(mutable.attribute(.font, at: 0, effectiveRange: nil) as! NSFont as CTFont))
            // Tornando ai file statici: i primi due tratti, ormai nello stesso font, sono un tratto solo.
            #expect(TextStyling.switchFontFile(in: mutable, range: NSRange(location: 0, length: mutable.length), family: "Noto Sans", variable: false) == 2)
            #expect(TextStyling.fontRuns(in: mutable, range: NSRange(location: 0, length: mutable.length)).allSatisfy { !FontVariations.isVariable($0.font) })
        }

        @Test("Nel file: il font di base e, in axes, i valori degli assi; si rilegge identico")
        func fileFormat() throws {
            let plain = CharacterStyle(fontName: "Skia-Regular", size: 14)
            let heavy = CharacterStyle(fontName: "Skia-Regular", size: 14, variations: [AxisValue(tag: "wght", value: 2.3), AxisValue(tag: "wdth", value: 0.8)])
            let hoefler = CharacterStyle(fontName: "HoeflerText-Regular", size: 14)
            let document = Document(blocks: [
                .paragraph(Paragraph(inlines: [.text(TextRun("Testo normale e ", style: plain)), .text(TextRun("pesante e stretto", style: heavy)), .text(TextRun(".", style: plain))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Tutto pesante.", style: heavy))])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Pesante, poi ", style: heavy)), .text(TextRun("un altro font", style: hoefler))])),
            ])
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<p>Testo normale e <t axes=\"wght=2.3 wdth=0.8\">pesante e stretto</t>.</p>"))
            #expect(written.contains("<p axes=\"wght=2.3 wdth=0.8\">Tutto pesante.</p>"))
            // Cambiando font gli assi ereditati si azzerano da soli, come le funzioni.
            #expect(written.contains("<p axes=\"wght=2.3 wdth=0.8\">Pesante, poi <t font=\"HoeflerText-Regular\">un altro font</t></p>"))
            #expect(try DocumentFormat.document(from: written) == document)

            // Nel testo attribuito il font è la faccia giusta, e torna identico nel modello.
            let text = document.attributedString().text
            let font = try #require(text.attribute(.font, at: (text.string as NSString).range(of: "pesante e").location, effectiveRange: nil) as? NSFont) as CTFont
            #expect(FontVariations.values(of: font) == heavy.variations)
            #expect(abs(width(font) - width(FontVariations.font(try skia(size: 14), with: heavy.variations))) < 0.001)
            #expect(Document(attributedString: text, settings: document.settingsOnly) == document)

            #expect(throws: DocumentFormatError.invalidValue(line: 1, attribute: "axes", value: "pesante=2")) {
                try DocumentFormat.document(from: "<document version=\"18\" font=\"Skia-Regular\" size=\"12\" axes=\"pesante=2\"></document>")
            }
        }

        @Test("Un file che nomina una faccia (Skia Bold) si apre, e al salvataggio diventa base più assi")
        func namedInstanceInFile() throws {
            let document = try DocumentFormat.document(from: "<document version=\"18\" font=\"Skia-Regular_Bold\" size=\"12\"><p>Nero</p></document>")
            let normalized = Document(attributedString: document.attributedString().text, settings: document.settingsOnly)
            #expect(DocumentFormat.string(for: normalized).contains("font=\"Skia-Regular\" size=\"12\" axes=\"wght=1.9499\""))
        }

        @Test("Spostare un asse su una selezione tocca solo il testo in quel font, in tutte le sue facce")
        func updateInText() throws {
            let text = NSMutableAttributedString(string: "tondo ", attributes: [.font: try skia()])
            text.append(NSAttributedString(string: "nero ", attributes: [.font: try skia("Skia-Regular_Bold")]))
            text.append(NSAttributedString(string: "altro", attributes: [.font: try TestFonts.hoefler()]))
            let changed = TextStyling.updateVariations(in: text, range: NSRange(location: 0, length: text.length), ofFontNamed: "Skia-Regular") { current in
                current.filter { $0.tag != "wdth" } + [AxisValue(tag: "wdth", value: 0.7)]
            }
            #expect(changed == 2)
            func values(_ index: Int) -> [AxisValue] { FontVariations.values(of: text.attribute(.font, at: index, effectiveRange: nil) as! NSFont as CTFont) }
            #expect(values(0) == [AxisValue(tag: "wdth", value: 0.7)])
            #expect(values(7) == [AxisValue(tag: "wght", value: 1.9499), AxisValue(tag: "wdth", value: 0.7)])
            #expect((text.attribute(.font, at: 12, effectiveRange: nil) as! NSFont).fontName == "HoeflerText-Regular")
        }

        @Test("La pagina e il PDF usano la faccia scelta")
        func layoutAndPDF() throws {
            let heavy = FontVariations.font(try skia(), with: [AxisValue(tag: "wght", value: 2.3), AxisValue(tag: "wdth", value: 0.8)])
            let layout = PageLayout.layout(NSAttributedString(string: "Hamburg", attributes: [.font: heavy]), appliesFontTracking: false)
            let line = layout.pages[0].lines[0].line
            #expect(abs(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - 91.711) < 0.01)
            #expect(Shaper.glyphs(in: line).allSatisfy { $0.fontName == heavy.postScriptName })
            #expect(PDFRenderer.pdfData(for: layout).count > 1000)
        }
    }
}
