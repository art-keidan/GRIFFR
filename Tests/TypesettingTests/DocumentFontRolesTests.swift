import Foundation
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Ruoli delle facce nel documento")
    struct DocumentFontRolesTests {
        @Test("Le facce scelte dal documento prevalgono su quelle del programma, ruolo per ruolo")
        func overlay() {
            var program = FontRoleTable()
            program.customize(family: "Baskerville", role: .bold, to: FontRoleEquivalence(staticFace: "Baskerville-Bold"))
            program.customize(family: "Baskerville", role: .italic, to: FontRoleEquivalence(staticFace: "Baskerville-SemiBoldItalic"))
            var document = FontRoleTable()
            document.customize(family: "Baskerville", role: .bold, to: FontRoleEquivalence(staticFace: "Baskerville-SemiBold"))
            let table = program.overlaid(by: document)
            #expect(table.equivalence(family: "Baskerville", role: .bold).staticFace == "Baskerville-SemiBold")
            #expect(table.equivalence(family: "Baskerville", role: .italic).staticFace == "Baskerville-SemiBoldItalic")
        }

        @Test("Il file conserva le facce dei ruoli, statiche e variabili")
        func roundTrip() throws {
            var document = try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><p>Testo.</p></document>")
            document.fontRoles.customize(family: "Baskerville", role: .bold, to: FontRoleEquivalence(staticFace: "Baskerville-SemiBold"))
            document.fontRoles.customize(family: "Adobe Kis VF", role: .bold, to: FontRoleEquivalence(
                variableInstance: VariableFontInstance(fontName: "AdobeKisVF-Default", variations: [AxisValue(tag: "wght", value: 450)])))
            document.fontRoles.customize(family: "Skia", role: .italic, to: FontRoleEquivalence(
                staticFace: "Skia-Regular", variableInstance: VariableFontInstance(fontName: "Skia-Regular", prefersVariableFont: false)))
            let written = DocumentFormat.string(for: document)
            #expect(written.contains("<font-role family=\"Baskerville\" role=\"bold\" face=\"Baskerville-SemiBold\"/>"))
            #expect(written.contains("<font-role family=\"Adobe Kis VF\" role=\"bold\" base=\"AdobeKisVF-Default\" axes=\"wght=450\"/>"))
            let read = try DocumentFormat.document(from: written)
            #expect(read.fontRoles == document.fontRoles)
            // Senza facce scelte, nulla nel file.
            #expect(!DocumentFormat.string(for: try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><p>x</p></document>")).contains("font-role"))
        }

        @Test("Un ruolo sconosciuto o ripetuto rende il file illeggibile")
        func invalid() {
            #expect(throws: (any Error).self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><font-roles><font-role family=\"X\" role=\"semibold\"/></font-roles><p>x</p></document>")
            }
            #expect(throws: (any Error).self) {
                try DocumentFormat.document(from: "<document version=\"1\" font=\"HoeflerText-Regular\" size=\"12\"><font-roles><font-role family=\"X\" role=\"bold\"/><font-role family=\"X\" role=\"bold\"/></font-roles><p>x</p></document>")
            }
        }
    }
}
