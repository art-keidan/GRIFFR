import AppKit
import CoreText
import Testing
@testable import Typesetting

extension TypesettingSuite {
    /// Adobe Kis VF: un font variabile con gli assi `opsz` (6–36, predefinito 12) e `wght` (300–800), e istanze con un
    /// nome che uniscono i due (Caption = `opsz` 8, Subhead = 18, Display = 36; Regular, Semibold, Bold).
    @Suite("Font variabili con l'asse della dimensione ottica (Adobe Kis VF)",
           .enabled(if: NSFont(name: "AdobeKisVF-Regular", size: 12) != nil))
    struct VariableOpticalSizeTests {
        private let opsz = NSNumber(value: 0x6f70737a)

        private func kis(_ size: CGFloat, opsz value: Double? = nil) -> CTFont {
            let regular = CTFontCreateWithName("AdobeKisVF-Regular" as CFString, size, nil)
            guard let value else { return regular }
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(regular), [kCTFontVariationAttribute: [opsz: value]] as CFDictionary)
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }

        private func width(_ font: CTFont, _ text: String = "Hamburgefonstiv") -> Double {
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font as NSFont])), nil, nil, nil)
        }

        @Test("Core Text non segue il corpo da sé: la dimensione ottica automatica va chiesta, e un valore fissato vince")
        func automaticOpticalSize() {
            // Senza richiesta, a 36 pt il disegno è quello di `opsz` 12.
            #expect(abs(width(kis(36)) - width(kis(36, opsz: 12))) < 0.01)
            let automatic = FontVariations.withAutomaticOpticalSize(kis(36))
            #expect(FontVariations.hasAutomaticOpticalSize(automatic))
            #expect(abs(width(automatic) - width(kis(36, opsz: 36))) < 0.01)
            #expect(abs(width(automatic) - width(kis(36, opsz: 12))) > 5)
            // Per chi legge gli assi la dimensione automatica non è un valore fissato.
            #expect(FontVariations.values(of: automatic) == FontVariations.values(of: kis(36)))
            // Un valore fissato resta.
            let fixed = kis(36, opsz: 20)
            #expect(FontVariations.withAutomaticOpticalSize(fixed) === fixed)
        }

        @Test("La composizione dà la dimensione ottica automatica: la riga a 36 pt è larga quanto con `opsz` 36")
        func layoutUsesAutomaticOpticalSize() {
            let text = NSAttributedString(string: "Hamburgefonstiv", attributes: [.font: kis(36) as NSFont])
            let line = PageLayout.layout(text, options: LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false)).pages[0].lines[0]
            let composed = CTLineGetTypographicBounds(line.line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line.line)
            #expect(abs(composed - width(kis(36, opsz: 36))) < 0.05)
        }

        @Test("Le istanze Caption, Subhead e Display non sono corpi ottici statici né facce da scegliere")
        func namedOpticalInstances() throws {
            #expect(OpticalFonts.inFamilyGroup(for: "Adobe Kis VF") == nil)
            #expect(OpticalFonts.namesOpticalSizes(family: "Adobe Kis VF"))
            let styles = OpticalFonts.members(ofFamily: "Adobe Kis VF").compactMap { $0[1] as? String }
            #expect(styles.contains("Regular") && styles.contains("Bold") && styles.contains("Semibold Italic"))
            #expect(!styles.contains { $0.contains("Caption") || $0.contains("Subhead") || $0.contains("Display") })
            #expect(TextStyling.face(of: "AdobeKisVF-Regular", bold: true, italic: nil) == "AdobeKisVF-Bold")
            #expect(TextStyling.face(of: "AdobeKisVF-Regular", bold: true, italic: true) == "AdobeKisVF-BoldItalic")
            // Il corpo non cambia faccia: lo fa l'asse.
            let big = kis(36)
            #expect(OpticalFonts.font(big, opticalSize: nil) === big)
            #expect(OpticalFonts.opticalSize(of: big) == nil)
            // Il nome dello stile con il corpo ottico in qualsiasi posizione.
            #expect(OpticalFonts.namesOpticalSize(style: "Display Semibold Italic"))
            #expect(OpticalFonts.namesOpticalSize(style: "Light Caption"))
            #expect(!OpticalFonts.namesOpticalSize(style: "Text"))
            #expect(!OpticalFonts.namesOpticalSize(style: "Bold Italic"))
        }

        @Test("Bloccare la dimensione ottica la ferma sul corpo, cioè sul disegno che si vede")
        func freezeAtPointSize() throws {
            let frozen = FontVariations.font(kis(24), automaticOpticalSize: false)
            let value = try #require(FontVariations.values(of: frozen).first { $0.tag == "opsz" })
            #expect(abs(value.value - 24) < 0.01)
        }
    }
}
