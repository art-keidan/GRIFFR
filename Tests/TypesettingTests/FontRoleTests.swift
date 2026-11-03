import Foundation
import Testing
@testable import Typesetting

@Suite("Ruoli tipografici")
struct FontRoleTests {
    @Test("I quattro ruoli combinano corsivo e nero senza dipendere da una faccia")
    func rolesFromTraits() {
        #expect(FontRole.allCases == [.regular, .italic, .bold, .boldItalic])
        #expect(FontRole(italic: false, bold: false) == .regular)
        #expect(FontRole(italic: true, bold: false) == .italic)
        #expect(FontRole(italic: false, bold: true) == .bold)
        #expect(FontRole(italic: true, bold: true) == .boldItalic)
        for role in FontRole.allCases {
            #expect(FontRole(italic: role.isItalic, bold: role.isBold) == role)
        }
    }

    @Test("I comandi di corsivo e nero cambiano soltanto il proprio ruolo")
    func independentToggles() {
        #expect(FontRole.regular.togglingBold() == .bold)
        #expect(FontRole.regular.togglingItalic() == .italic)
        #expect(FontRole.bold.togglingBold() == .regular)
        #expect(FontRole.bold.togglingItalic() == .boldItalic)
        #expect(FontRole.italic.togglingBold() == .boldItalic)
        #expect(FontRole.italic.togglingItalic() == .regular)
        #expect(FontRole.boldItalic.togglingBold() == .italic)
        #expect(FontRole.boldItalic.togglingItalic() == .bold)
    }

    @Test("I nomi conservati sono stabili")
    func stableRawValues() throws {
        #expect(FontRole.regular.rawValue == "regular")
        #expect(FontRole.italic.rawValue == "italic")
        #expect(FontRole.bold.rawValue == "bold")
        #expect(FontRole.boldItalic.rawValue == "boldItalic")
        for role in FontRole.allCases {
            let data = try JSONEncoder().encode(role)
            #expect(try JSONDecoder().decode(FontRole.self, from: data) == role)
        }
    }
}
