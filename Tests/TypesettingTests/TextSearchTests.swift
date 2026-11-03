import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Cerca e sostituisci: le occorrenze nel testo")
    struct TextSearchTests {
        private func text(_ string: String) -> NSAttributedString { NSAttributedString(string: string) }

        private func found(_ query: String, in string: String, _ options: TextSearch.Options = .init()) throws -> [String] {
            let ns = string as NSString
            return try TextSearch.matches(of: query, in: text(string), options: options).map { ns.substring(with: $0) }
        }

        @Test("Maiuscole e minuscole, e parole intere")
        func caseAndWords() throws {
            #expect(try found("lago", in: "Il Lago, il lago e i laghi.") == ["Lago", "lago"])
            #expect(try found("lago", in: "Il Lago, il lago.", .init(matchesCase: true)) == ["lago"])
            #expect(try found("la", in: "la lana e la luna", .init(wholeWords: true)) == ["la", "la"])
            #expect(try found("città", in: "cittàdina città", .init(wholeWords: true)) == ["città"], "una lettera accentata è una lettera")
            #expect(try found("", in: "testo").isEmpty)
        }

        @Test("Ignorando i segni, «e» trova anche é, è, ē e ἐ; senza, solo e")
        func diacritics() throws {
            #expect(try found("e", in: "e é è ē") == ["e"])
            #expect(try found("e", in: "e é è ē", .init(ignoresDiacritics: true)) == ["e", "é", "è", "ē"])
            #expect(try found("λογος", in: "ὁ λόγος", .init(ignoresDiacritics: true)) == ["λόγος"])
            // Una lettera scritta con il segno a parte (e + accento combinante) si trova intera.
            #expect(try found("e", in: "cafe\u{301}", .init(ignoresDiacritics: true)) == ["e\u{301}"])
        }

        @Test("Con il modello: espressioni regolari, e nella sostituzione i gruppi")
        func patterns() throws {
            #expect(try found("\\d+", in: "pp. 12-345", .init(isPattern: true)) == ["12", "345"])
            #expect(try found("a*", in: "baab", .init(isPattern: true)) == ["aa"], "le occorrenze vuote non contano")
            #expect(try found("[A-Z]+", in: "ONU e Nato", .init(matchesCase: true, isPattern: true)) == ["ONU", "N"])
            #expect(throws: TextSearch.SearchError.invalidPattern) { try found("(", in: "x", .init(isPattern: true)) }
            let source = text("Rossi, Mario")
            let match = try #require(try TextSearch.matches(of: "(\\w+), (\\w+)", in: source, options: .init(isPattern: true)).first)
            #expect(try TextSearch.replacement(for: match, in: source, query: "(\\w+), (\\w+)", template: "$2 $1", options: .init(isPattern: true)) == "Mario Rossi")
            #expect(try TextSearch.replacement(for: match, in: source, query: "x", template: "$2 $1", options: .init()) == "$2 $1", "senza modello la sostituzione è letterale")
        }

        @Test("Un'occorrenza non passa dal corpo a una nota, né attraversa un richiamo")
        func notesAreSeparate() throws {
            let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
            let note = FloatingObject(runs: [TextRun("nota", style: body)])
            let document = Document(blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("testo", style: body)), .floating(note), .text(TextRun(" fine", style: body))]))])
            let attributed = document.attributedString().text
            #expect(try TextSearch.matches(of: "nota", in: attributed, options: .init()).count == 1, "nel testo delle note si cerca")
            #expect(try TextSearch.matches(of: "o.n", in: attributed, options: .init(isPattern: true)).isEmpty, "«testo» + richiamo + «nota»: no")
            #expect(try TextSearch.matches(of: "ta f", in: attributed, options: .init()).isEmpty, "fine della nota + corpo: no")
        }
    }
}
