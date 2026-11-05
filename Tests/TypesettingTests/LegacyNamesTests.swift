import Foundation
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Nomi italiani dei documenti di prima")
    struct LegacyNamesTests {
        private let old = """
            <document version="14" font="HoeflerText-Regular" size="12">
            <lists>
            <list name="Note" counter="1" continues="on"/>
            </lists>
            <styles>
            <style name="Testo" target="paragraph"/>
            </styles>
            <float-styles>
            <float-style name="Nota a piè di pagina" list="Note" rule-length="100"/>
            </float-styles>
            <p style="Testo">Uno<note style="Nota a piè di pagina">nota</note>.</p>
            <section id="c1" role="capitolo" page-type="Predefinito">
            <title><p>Capitolo</p></title>
            <p style="Testo">Due.</p>
            </section>
            </document>
            """

        @Test("Lo stile delle note e il tipo di pagina predefinito prendono i nomi nuovi; gli stili del documento restano suoi")
        func readsOldNames() throws {
            let document = try DocumentFormat.document(from: old)
            let footnote = try #require(document.floatStyles.first { $0.name == FloatStyle.footnoteName })
            #expect(footnote.ruleLength == 100 && footnote.listName == "Note", "le misure dello stile vecchio restano")
            #expect(!document.floatStyles.contains { $0.name == FloatStyle.legacyFootnoteName })
            #expect(document.sections.first?.pageTypes.pages == PageType.defaultName)
            #expect(document.sections.first?.role == "capitolo", "il ruolo è un dato del documento")
            #expect(document.styles.bodyStyleName == "Testo", "il corpo di un documento di prima resta «Testo»")
            let written = DocumentFormat.string(for: document)
            #expect(!written.contains(FloatStyle.legacyFootnoteName) && !written.contains("Predefinito"))
            #expect(try DocumentFormat.document(from: written) == document)
        }
    }
}
