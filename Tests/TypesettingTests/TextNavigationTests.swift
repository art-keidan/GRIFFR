import AppKit
import CoreText
import Testing
import Typesetting

extension TypesettingSuite {
    @Suite("Movimenti del cursore e della selezione")
    struct TextNavigationTests {
        /// Tre paragrafi; il secondo è lungo e va a capo da solo su più righe.
        private func layout() throws -> DocumentLayout {
            let text = "Uno due\n" + String(repeating: "minister affixed stamps ", count: 10) + "\ncafe\u{301} fine"
            return PageLayout.layout(NSAttributedString(string: text, attributes: [.font: try TestFonts.hoefler(size: 24)]), appliesFontTracking: false)
        }

        private func move(_ layout: DocumentLayout, from index: Int, _ movement: TextMovement, extending: Bool = false) -> TextSelection {
            layout.selection(TextSelection(caret: index), moving: movement, extending: extending)
        }

        @Test("Sinistra e destra si fermano ai limiti e non spezzano un carattere con accento combinato")
        func leftRight() throws {
            let layout = try layout()
            let length = layout.text.length
            #expect(move(layout, from: 0, .left).head == 0)
            #expect(move(layout, from: length, .right).head == length)
            #expect(move(layout, from: 3, .right).head == 4)
            // «cafe» + accento combinante: la «e» e l'accento sono due unità ma un solo passo.
            let cafe = (layout.text.string as NSString).range(of: "cafe", options: .literal).location
            #expect(move(layout, from: cafe + 3, .right).head == cafe + 5)
            #expect(move(layout, from: cafe + 5, .left).head == cafe + 3)
        }

        @Test("Per parole")
        func words() throws {
            let layout = try layout()
            #expect(move(layout, from: 0, .wordRight).head == 3, "fine di «Uno»")
            #expect(move(layout, from: 7, .wordLeft).head == 4, "inizio di «due»")
        }

        @Test("Inizio e fine riga seguono le righe della pagina, non i paragrafi")
        func lineEdges() throws {
            let layout = try layout()
            let lines = layout.pages[0].lines
            #expect(lines.count > 4)
            // Prima riga: finisce con un a capo scritto, la fine è prima dell'a capo.
            #expect(move(layout, from: 2, .lineEnd).head == 7)
            #expect(move(layout, from: 5, .lineStart).head == 0)
            // Seconda riga (inizio del paragrafo lungo): la fine coincide con l'inizio della terza, e resta sulla seconda.
            let second = lines[1], third = lines[2]
            let end = move(layout, from: second.range.location + 3, .lineEnd)
            #expect(end.head == NSMaxRange(second.range))
            #expect(end.affinity == .upstream)
            #expect(try #require(layout.caret(at: end.head, affinity: end.affinity)).rect.minY > third.origin.y, "il cursore è disegnato sulla seconda riga")
            // Da lì, inizio riga torna all'inizio della seconda, non della terza.
            #expect(layout.selection(end, moving: .lineStart, extending: false).head == second.range.location)
            #expect(move(layout, from: third.range.location + 2, .lineStart).head == third.range.location)
        }

        @Test("Su e giù mantengono l'ascissa anche passando per righe più corte")
        func vertical() throws {
            let layout = try layout()
            let lines = layout.pages[0].lines
            // Dalla terza riga, a metà, si sale alla seconda e poi alla prima («Uno due», corta).
            let start = lines[2].range.location + 20
            let x0 = try #require(layout.caret(at: start)).rect.minX
            let up1 = move(layout, from: start, .up)
            #expect(lines[1].range.contains(up1.head))
            #expect(abs(try #require(layout.caret(at: up1.head)).rect.minX - x0) < 12, "più o meno sotto lo stesso punto")
            let up2 = layout.selection(up1, moving: .up, extending: false)
            #expect(up2.head == 7, "la prima riga è più corta: ci si ferma alla sua fine")
            // Riscendendo due volte si torna sotto l'ascissa di partenza, non sotto la fine della riga corta.
            let down2 = layout.selection(layout.selection(up2, moving: .down, extending: false), moving: .down, extending: false)
            #expect(abs(try #require(layout.caret(at: down2.head)).rect.minX - x0) < 12)
            #expect(lines[2].range.contains(down2.head))
            // Oltre i limiti: inizio e fine del documento.
            #expect(move(layout, from: 3, .up).head == 0)
            #expect(move(layout, from: layout.text.length - 2, .down).head == layout.text.length)
            // Un movimento orizzontale dimentica l'ascissa memorizzata.
            #expect(layout.selection(up2, moving: .left, extending: false).goalX == nil)
        }

        @Test("Paragrafo e documento")
        func paragraphAndDocument() throws {
            let layout = try layout()
            let lines = layout.pages[0].lines
            let inside = lines[3].range.location + 5  // dentro il paragrafo lungo
            #expect(move(layout, from: inside, .paragraphStart).head == 8)
            let paragraphEnd = move(layout, from: inside, .paragraphEnd).head
            #expect((layout.text.string as NSString).character(at: paragraphEnd) == 0x0A)
            #expect(move(layout, from: inside, .documentStart).head == 0)
            #expect(move(layout, from: inside, .documentEnd).head == layout.text.length)
        }

        @Test("Con Maiuscole l'àncora resta ferma; senza, una selezione si chiude dal lato giusto")
        func extendingAndCollapsing() throws {
            let layout = try layout()
            var selection = TextSelection(caret: 4)
            selection = layout.selection(selection, moving: .right, extending: true)
            selection = layout.selection(selection, moving: .right, extending: true)
            #expect(selection.range == NSRange(location: 4, length: 2))
            #expect(selection.anchor == 4)
            // Si può tornare indietro oltre l'àncora: la selezione si rovescia.
            for _ in 0..<5 { selection = layout.selection(selection, moving: .left, extending: true) }
            #expect(selection.range == NSRange(location: 1, length: 3))
            #expect(selection.head == 1)
            #expect(layout.selection(selection, moving: .left, extending: false) == TextSelection(caret: 1))
            #expect(layout.selection(selection, moving: .right, extending: false) == TextSelection(caret: 4))
            // Maiuscole + fine riga dalla prima riga seleziona fino a prima dell'a capo.
            #expect(layout.selection(TextSelection(caret: 4), moving: .lineEnd, extending: true).range == NSRange(location: 4, length: 3))
        }

        @Test("Gli intervalli di cancellazione")
        func deletion() throws {
            let layout = try layout()
            #expect(layout.deletionRange(for: TextSelection(caret: 4), toward: .left) == NSRange(location: 3, length: 1))
            #expect(layout.deletionRange(for: TextSelection(caret: 4), toward: .right) == NSRange(location: 4, length: 1))
            #expect(layout.deletionRange(for: TextSelection(caret: 0), toward: .left).length == 0)
            #expect(layout.deletionRange(for: TextSelection(caret: 7), toward: .wordLeft) == NSRange(location: 4, length: 3))
            #expect(layout.deletionRange(for: TextSelection(anchor: 2, head: 6), toward: .left) == NSRange(location: 2, length: 4))
            let cafe = (layout.text.string as NSString).range(of: "cafe", options: .literal).location
            #expect(layout.deletionRange(for: TextSelection(caret: cafe + 5), toward: .left) == NSRange(location: cafe + 3, length: 2), "lettera e accento insieme")
        }

        @Test("Nelle scritture indiane e del Sud-Est asiatico Cancella toglie un carattere per volta; il cursore va per lettere")
        func indicDeletion() {
            let text = "सत्यमेव ffi e\u{301} 👍🏽 ကျွ"
            let layout = PageLayout.layout(NSAttributedString(string: text, attributes: [.font: NSFont(name: "AnnapurnaSIL-Regular", size: 14)!]))
            let string = text as NSString
            func deleted(_ caret: Int) -> String { string.substring(with: layout.deletionRange(for: TextSelection(caret: caret), toward: .left)) }
            // Dopo «मे» (posizioni 4–5): prima la vocale, poi la consonante.
            #expect(deleted(6) == "\u{947}")
            #expect(deleted(5) == "म")
            // Dopo «त्य» (1–3): «य»; col cursore in mezzo alla lettera, il virāma, poi «त».
            #expect(deleted(4) == "य" && deleted(3) == "\u{94D}" && deleted(2) == "त")
            // Il cursore invece passa «मे» e «त्य» in un passo, come in TextEdit.
            #expect(layout.selection(TextSelection(caret: 6), moving: .left, extending: false).head == 4)
            #expect(layout.selection(TextSelection(caret: 4), moving: .left, extending: false).head == 1)
            // Birmano: «ကျွ» si cancella dall'ultimo segno.
            #expect(deleted(string.length) == "\u{103D}")
            // Le altre scritture come prima: una lettera alla volta, l'accento con la sua lettera, l'emoji intera.
            let ffi = string.range(of: "ffi")
            #expect(deleted(NSMaxRange(ffi)) == "i")
            let accent = string.range(of: "e\u{301}")
            #expect(deleted(NSMaxRange(accent)) == "e\u{301}")
            let emoji = string.range(of: "👍🏽")
            #expect(deleted(NSMaxRange(emoji)) == "👍🏽")
            #expect(layout.deletionRange(for: TextSelection(caret: 6), toward: .right).length == 1, "verso destra, la lettera intera come prima")
        }
    }
}
