import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Menu delle famiglie raggruppato")
    struct FontFamilyMenuTests {
        @Test("Le famiglie con la stessa prima parola vanno in un sottomenu, al posto della prima; le altre restano")
        func groups() {
            let families = ["Arial", "Arial Black", "Baskerville", "Hoefler Text", "Noto Sans", "Noto Sans Gothic", "Noto Serif", "Times New Roman"]
            #expect(FontFamilyMenu.entries(families) == [
                .group("Arial", ["Arial", "Arial Black"]),
                .family("Baskerville"),
                .family("Hoefler Text"),
                .group("Noto", ["Noto Sans", "Noto Sans Gothic", "Noto Serif"]),
                .family("Times New Roman"),
            ])
        }

        @Test("Con una soglia più alta i gruppi piccoli restano sciolti")
        func threshold() {
            let families = ["Arial", "Arial Black", "Noto Sans", "Noto Serif", "Noto Sans Gothic"]
            #expect(FontFamilyMenu.entries(families, minimum: 3) == [
                .family("Arial"), .family("Arial Black"), .group("Noto", ["Noto Sans", "Noto Serif", "Noto Sans Gothic"]),
            ])
        }
    }
}
