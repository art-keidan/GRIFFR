import AppKit
import CoreText
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Note a piè di pagina: composizione, cursore, movimenti")
    struct FootnoteLayoutTests {
        private let body = CharacterStyle(fontName: "HoeflerText-Regular", size: 12)
        private let small = CharacterStyle(fontName: "HoeflerText-Regular", size: 10)
        private let options = LayoutOptions(appliesFontTracking: false, usesOpticalMargins: false, lineBreaking: .firstFit)

        /// «Testo¹ che continua² fine.» con due note, più un secondo paragrafo.
        /// Indici: T0…o4, richiamo 5, «Prima nota.» 6…16, « che continua» 17…29, richiamo 30, «Seconda.» 31…38, « fine.» 39…44, a capo 45.
        private func sample() -> NSAttributedString {
            Document(blocks: [
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Testo", style: body)),
                    .floating(FloatingObject(runs: [TextRun("Prima nota.", style: small)])),
                    .text(TextRun(" che continua", style: body)),
                    .floating(FloatingObject(runs: [TextRun("Seconda.", style: small)])),
                    .text(TextRun(" fine.", style: body)),
                ])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Secondo paragrafo.", style: body))])),
            ]).attributedString().text
        }

        @Test("Le note sono riconosciute, numerate e messe in fondo alla pagina sotto un filetto")
        func placement() throws {
            let layout = PageLayout.layout(sample(), options: options)
            #expect(layout.notes == [NSRange(location: 5, length: 12), NSRange(location: 30, length: 9)])
            let page = layout.pages[0]
            let main = page.lines.filter { !$0.isNote }, notes = page.lines.filter(\.isNote)
            #expect(main.count == 2)
            #expect(notes.count == 2)
            #expect(notes.map(\.noteRange) == [NSRange(location: 6, length: 11), NSRange(location: 31, length: 8)])
            #expect(page.rules.count == 1)
            let rect = layout.setup.textRect
            // Le note stanno sotto il testo, la seconda sotto la prima, e l'ultima tocca il fondo dello specchio.
            #expect(notes[0].origin.y < main[1].origin.y - 100)
            #expect(notes[1].origin.y < notes[0].origin.y)
            #expect(notes[1].origin.y - notes[1].descent >= rect.minY - 0.01)
            #expect(notes[1].origin.y - notes[1].descent < rect.minY + 3)
            #expect(page.rules[0].minY > notes[0].origin.y + notes[0].ascent, "il filetto sta sopra la prima nota")
            #expect(page.rules[0].maxY < main[1].origin.y - main[1].descent)
        }

        @Test("Nel PDF i richiami e le note portano i numeri nell'ordine giusto")
        func numbering() throws {
            let layout = PageLayout.layout(sample(), options: options)
            let text = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.string)
            // Hoefler Text ha i glifi Unicode delle cifre in apice, e sono quelli a essere usati.
            #expect(text.contains("Testo\u{B9} che continua\u{B2} fine."))
            #expect(text.contains("\u{B9} Prima nota."))
            #expect(text.contains("\u{B2} Seconda."))
        }

        @Test("Il richiamo usa le cifre in apice del font quando ci sono, in tre gradi di preferenza")
        func referenceMarks() throws {
            let arial = try FontLoader.font(at: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf"), size: 12)
            // Hoefler Text: nessuna funzione «apice», ma tutti i glifi Unicode in apice.
            let hoefler = PageLayout.referenceMark(12, attributes: [.font: try TestFonts.hoefler(size: 12)])
            #expect(hoefler.string == "\u{B9}\u{B2}")
            #expect((hoefler.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 12, "nessun rimpicciolimento")
            // Arial: né funzione né tutti i glifi (ha solo ¹²³): cifra normale ridotta, alzata e ingrossata.
            let faux = PageLayout.referenceMark(40, attributes: [.font: arial])
            #expect(faux.string == "40")
            #expect(abs(try #require(faux.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize - 7.44) < 0.01)
            #expect(faux.attribute(NSAttributedString.Key(kCTBaselineOffsetAttributeName as String), at: 0, effectiveRange: nil) != nil)
            // Brill, se installato: la funzione «apice» del font, sulle cifre normali.
            let brillURL = URL(fileURLWithPath: "/Users/artemio/Library/Fonts/Brill/Brill-Roman.ttf")
            if FileManager.default.fileExists(atPath: brillURL.path) {
                let base = try FontLoader.font(at: brillURL, size: 12)
                let mark = PageLayout.referenceMark(7, attributes: [.font: base])
                #expect(mark.string == "7")
                let font = try #require(mark.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) as CTFont
                #expect(!FontFeatures.settings(of: font).isEmpty)
                #expect(Shaper.glyphIDs(for: "7", font: font) != Shaper.glyphIDs(for: "7", font: base))
            }
        }

        @Test("Il cursore distingue il corpo dalla nota")
        func caret() throws {
            let layout = PageLayout.layout(sample(), options: options)
            let main = layout.pages[0].lines[0]
            let beforeMark = try #require(layout.caret(at: 5)), afterMark = try #require(layout.caret(at: 17))
            // Prima e dopo il richiamo: stessa riga del corpo, separati dalla larghezza del numero.
            #expect(abs(beforeMark.rect.minY - (main.origin.y - main.descent)) < 0.001)
            #expect(abs(afterMark.rect.minY - beforeMark.rect.minY) < 0.001)
            #expect(afterMark.rect.minX - beforeMark.rect.minX > 2)
            #expect(afterMark.rect.minX - beforeMark.rect.minX < 8)
            // Dentro il testo della nota: in fondo alla pagina, dopo il numero.
            let noteStart = try #require(layout.caret(at: 6)), noteEnd = try #require(layout.caret(at: 17, affinity: .upstream))
            #expect(noteStart.rect.minY < beforeMark.rect.minY - 100)
            #expect(noteStart.rect.minX > layout.setup.textRect.minX + 3, "il cursore sta dopo il numero della nota")
            #expect(abs(noteEnd.rect.minY - noteStart.rect.minY) < 0.001)
            #expect(noteEnd.rect.minX > noteStart.rect.minX + 30)
        }

        @Test("Clic e cursore si corrispondono, nel corpo e nelle note")
        func hitTesting() throws {
            let layout = PageLayout.layout(sample(), options: options)
            for index in 0...layout.text.length {
                // Dentro una nota, e alla sua fine con affinità upstream, si è nella nota; altrimenti nel corpo.
                for affinity in [NSSelectionAffinity.downstream, .upstream] {
                    let inNote = layout.noteTextRange(containing: index, affinity: affinity) != nil
                    if affinity == .upstream, !inNote { continue }
                    let caret = try #require(layout.caret(at: index, affinity: affinity))
                    let hit = try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: caret.page))
                    #expect(hit.index == index, "posizione \(index), nota: \(inNote)")
                    #expect((layout.noteTextRange(containing: hit.index, affinity: hit.affinity) != nil) == inNote, "posizione \(index)")
                }
            }
        }

        @Test("Dal corpo una nota si scavalca in un passo; dentro la nota i movimenti non ne escono")
        func navigation() throws {
            let layout = PageLayout.layout(sample(), options: options)
            // Nel corpo: da prima del richiamo (5) a dopo (17), e ritorno.
            let right = layout.selection(TextSelection(caret: 5), moving: .right, extending: false)
            #expect(right.head == 17)
            #expect(right.affinity == .downstream)
            #expect(layout.selection(right, moving: .left, extending: false).head == 5)
            #expect(layout.selection(TextSelection(caret: 4), moving: .wordRight, extending: false).head == 5)
            // Nella nota: ci si ferma ai suoi estremi.
            let start = TextSelection(caret: 6)
            #expect(layout.selection(start, moving: .left, extending: false).head == 6)
            let end = layout.selection(start, moving: .paragraphEnd, extending: false)
            #expect(end.head == 17)
            #expect(end.affinity == .upstream, "alla fine della nota si resta nella nota")
            #expect(layout.selection(end, moving: .right, extending: false) == end)
            #expect(layout.selection(end, moving: .lineStart, extending: false).head == 6)
            // Dalla nota si sale al testo, dal testo si scende alla nota: su e giù seguono la pagina.
            let up = layout.selection(start, moving: .up, extending: false)
            #expect(layout.noteTextRange(containing: up.head, affinity: up.affinity) == nil)
        }

        @Test("Cancellare all'indietro dopo un richiamo toglie tutta la nota; all'inizio della nota non toglie nulla")
        func deletion() throws {
            let layout = PageLayout.layout(sample(), options: options)
            #expect(layout.deletionRange(for: TextSelection(caret: 17), toward: .left) == NSRange(location: 5, length: 12))
            #expect(layout.deletionRange(for: TextSelection(caret: 5), toward: .right) == NSRange(location: 5, length: 12))
            #expect(layout.deletionRange(for: TextSelection(caret: 6), toward: .left).length == 0)
            #expect(layout.deletionRange(for: TextSelection(caret: 17, affinity: .upstream), toward: .left) == NSRange(location: 16, length: 1))
            #expect(layout.deletionRange(for: TextSelection(caret: 17, affinity: .upstream), toward: .right).length == 0)
        }

        @Test("Una nota vuota ha la sua riga, e il cursore ci può stare")
        func emptyNote() throws {
            let text = Document(blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("Testo", style: body)), .floating(FloatingObject(runs: [TextRun("", style: small)])), .text(TextRun(" dopo.", style: body)),
            ]))]).attributedString().text
            let layout = PageLayout.layout(text, options: options)
            #expect(layout.notes == [NSRange(location: 5, length: 1)])
            let inBody = try #require(layout.caret(at: 6)), inNote = try #require(layout.caret(at: 6, affinity: .upstream))
            #expect(inNote.rect.minY < inBody.rect.minY - 100)
            let hit = try #require(layout.position(at: CGPoint(x: inNote.rect.minX + 40, y: inNote.rect.midY), onPage: 0))
            #expect(hit.index == 6)
            #expect(hit.affinity == .upstream)
        }

        @Test("Una nota di più paragrafi si compone su più righe, e dopo un a capo finale c'è la riga per il cursore")
        func multipleParagraphs() throws {
            // «Testo» 0…4, richiamo 5, «Uno.» 6…9, a capo 10, «Due.» 11…14, a capo 15, « dopo.» 16…21, a capo 22, «Secondo.»
            let text = Document(blocks: [
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Testo", style: body)),
                    .floating(FloatingObject(paragraphs: [[TextRun("Uno.", style: small)], [TextRun("Due.", style: small)], [TextRun("", style: small)]])),
                    .text(TextRun(" dopo.", style: body)),
                ])),
                .paragraph(Paragraph(inlines: [.text(TextRun("Secondo.", style: body))])),
            ]).attributedString().text
            let layout = PageLayout.layout(text, options: options)
            #expect(layout.notes == [NSRange(location: 5, length: 11)])
            let lines = layout.pages[0].lines
            let main = lines.filter { !$0.isNote }, notes = lines.filter(\.isNote)
            #expect(main.count == 2, "il paragrafo del corpo resta uno, più il secondo")
            #expect(main[0].range == NSRange(location: 0, length: 23))
            #expect(notes.count == 3, "due paragrafi di nota e la riga vuota dopo l'a capo finale")
            #expect(notes[1].origin.y < notes[0].origin.y && notes[2].origin.y < notes[1].origin.y)
            // Il cursore alla fine della nota sta sulla riga vuota, a sinistra; nel corpo, dopo il richiamo.
            let inNote = try #require(layout.caret(at: 16, affinity: .upstream)), inBody = try #require(layout.caret(at: 16))
            #expect(abs(inNote.rect.minY - (notes[2].origin.y - notes[2].descent)) < 0.001)
            #expect(abs(inNote.rect.minX - layout.setup.textRect.minX) < 0.01)
            #expect(inBody.rect.minY > inNote.rect.minY + 100)
            // Inizio e fine paragrafo: dentro la nota valgono i suoi paragrafi, nel corpo quello che la contiene.
            #expect(layout.selection(TextSelection(caret: 13), moving: .paragraphStart, extending: false).head == 11)
            #expect(layout.selection(TextSelection(caret: 13), moving: .paragraphEnd, extending: false).head == 15)
            #expect(layout.selection(TextSelection(caret: 18), moving: .paragraphStart, extending: false).head == 0)
            #expect(layout.selection(TextSelection(caret: 2), moving: .paragraphEnd, extending: false).head == 22)
            // Clic e cursore si corrispondono ovunque.
            for index in 0...layout.text.length {
                for affinity in [NSSelectionAffinity.downstream, .upstream] {
                    let inside = layout.noteTextRange(containing: index, affinity: affinity) != nil
                    if affinity == .upstream, !inside { continue }
                    let caret = try #require(layout.caret(at: index, affinity: affinity))
                    let hit = try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: caret.page))
                    #expect(hit.index == index, "posizione \(index), nota: \(inside)")
                    #expect((layout.noteTextRange(containing: hit.index, affinity: hit.affinity) != nil) == inside, "posizione \(index)")
                }
            }
        }

        @Test("Una nota che non entra nella pagina continua in fondo alla successiva, senza uscire dallo specchio")
        func splitAcrossPages() throws {
            let filler = String(repeating: "The officiating minister affixed five stamps to the letter and went away. ", count: 4)
            // Paragrafi senza note fino quasi in fondo alla prima pagina, poi un richiamo con una nota molto lunga.
            var blocks: [Block] = (0..<9).map { .paragraph(Paragraph(inlines: [.text(TextRun("Paragrafo \($0). " + filler, style: body))])) }
            let long = (1...120).map { "Frase numero \($0) della nota lunga." }.joined(separator: " ")
            blocks.append(.paragraph(Paragraph(inlines: [
                .text(TextRun("Con nota", style: body)), .floating(FloatingObject(runs: [TextRun(long, style: small)])), .text(TextRun(". " + filler, style: body)),
            ])))
            blocks.append(contentsOf: (0..<6).map { .paragraph(Paragraph(inlines: [.text(TextRun("Seguito \($0). " + filler, style: body))])) })
            let layout = PageLayout.layout(Document(blocks: blocks).attributedString().text, options: options)
            let note = try #require(layout.notes.first)
            let textRange = NSRange(location: note.location + 1, length: note.length - 1)
            let rect = layout.setup.textRect

            let pagesWithNote = layout.pages.indices.filter { page in layout.pages[page].lines.contains { $0.noteRange == textRange } }
            #expect(pagesWithNote.count == 2, "la nota occupa due pagine consecutive")
            #expect(pagesWithNote.last == pagesWithNote.first.map { $0 + 1 })
            // Il richiamo è nella prima delle due.
            let first = try #require(pagesWithNote.first)
            #expect(layout.pages[first].lines.contains { !$0.isNote && NSLocationInRange(note.location, $0.range) })
            // Le righe della nota coprono tutto il suo testo, in ordine, senza buchi né ripetizioni.
            let noteLines = layout.pages.flatMap(\.lines).filter { $0.noteRange == textRange }
            #expect(noteLines.first?.range.location == textRange.location)
            #expect(noteLines.last.map { NSMaxRange($0.range) } == NSMaxRange(textRange))
            #expect(zip(noteLines, noteLines.dropFirst()).allSatisfy { NSMaxRange($0.range) == $1.range.location })
            // Nessuna riga, di testo o di nota, esce dallo specchio, e il testo sta sempre sopra le note.
            for page in layout.pages {
                let lowestMain = page.lines.filter { !$0.isNote }.map { $0.origin.y - $0.descent }.min() ?? rect.maxY
                for line in page.lines {
                    #expect(line.origin.y - line.descent >= rect.minY - 0.5)
                    #expect(line.origin.y + line.ascent <= rect.maxY + 0.5)
                    if line.isNote { #expect(line.origin.y + line.ascent < lowestMain + 0.01) }
                }
                #expect(page.rules.count == (page.lines.contains(where: \.isNote) ? 1 : 0))
            }
            // Nella seconda pagina il seguito della nota convive con il testo che prosegue.
            #expect(layout.pages[first + 1].lines.contains { !$0.isNote })
            // Il cursore e il clic funzionano anche nella parte continuata.
            let continued = try #require(layout.pages[first + 1].lines.first { $0.noteRange == textRange })
            let caret = try #require(layout.caret(at: continued.range.location + 3))
            #expect(caret.page == first + 1)
            #expect(try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: caret.page)).index == continued.range.location + 3)
        }

        @Test("Una nota più lunga di una pagina intera prosegue su più pagine")
        func noteLongerThanAPage() throws {
            let long = (1...600).map { "Frase numero \($0) della nota lunghissima." }.joined(separator: " ")
            let text = Document(blocks: [.paragraph(Paragraph(inlines: [
                .text(TextRun("Testo", style: body)), .floating(FloatingObject(runs: [TextRun(long, style: small)])), .text(TextRun(" fine.", style: body)),
            ]))]).attributedString().text
            let layout = PageLayout.layout(text, options: options)
            #expect(layout.pages.count >= 3)
            let rect = layout.setup.textRect
            for line in layout.pages.flatMap(\.lines) {
                #expect(line.origin.y - line.descent >= rect.minY - 0.5)
                #expect(line.origin.y + line.ascent <= rect.maxY + 0.5)
            }
            let noteLines = layout.pages.flatMap(\.lines).filter(\.isNote)
            #expect(noteLines.map(\.range.length).reduce(0, +) == (long as NSString).length)
            #expect(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.pageCount == layout.pages.count)
        }

        @Test("Selezionando tutta una nota si evidenziano il richiamo e il testo in fondo")
        func selection() throws {
            let layout = PageLayout.layout(sample(), options: options)
            let rects = layout.selectionRects(for: NSRange(location: 5, length: 12))
            #expect(rects.count == 2)
            let marker = try #require(rects.max { $0.rect.minY < $1.rect.minY }), note = try #require(rects.min { $0.rect.minY < $1.rect.minY })
            #expect(marker.rect.width > 2 && marker.rect.width < 8)
            #expect(note.rect.width > 30)
            // Solo una parte del testo della nota: il richiamo non si evidenzia.
            #expect(layout.selectionRects(for: NSRange(location: 6, length: 5)).count == 1)
        }

        @Test("Su più pagine ogni nota resta nella pagina del suo richiamo, e nulla esce dallo specchio")
        func pagination() throws {
            let filler = String(repeating: "The officiating minister affixed five stamps to the letter and went away. ", count: 5)
            let document = Document(blocks: (0..<24).map { index in
                .paragraph(Paragraph(inlines: [
                    .text(TextRun("Paragrafo \(index). " + filler, style: body)),
                    .floating(FloatingObject(runs: [TextRun("Nota del paragrafo \(index), abbastanza lunga da occupare più di una riga in fondo alla pagina quando la si compone nel corpo piccolo previsto per le note a piè di pagina.", style: small)])),
                    .text(TextRun(" Fine.", style: body)),
                ]))
            })
            let layout = PageLayout.layout(document.attributedString().text, options: LayoutOptions(appliesFontTracking: true, usesOpticalMargins: true, hyphenationLanguage: "en"))
            #expect(layout.pages.count > 2)
            #expect(layout.notes.count == 24)
            let rect = layout.setup.textRect
            var seen = 0
            for page in layout.pages {
                let main = page.lines.filter { !$0.isNote }, notes = page.lines.filter(\.isNote)
                let lowestMain = main.map { $0.origin.y - $0.descent }.min() ?? rect.maxY
                for note in notes {
                    #expect(note.origin.y + note.ascent < lowestMain + 0.01, "le note stanno sotto il testo")
                    #expect(note.origin.y - note.descent >= rect.minY - 0.5)
                    // La prima riga di ogni nota sta nella pagina del suo richiamo; il seguito può continuare nella successiva.
                    let textRange = try #require(note.noteRange)
                    guard note.range.location == textRange.location else { continue }
                    seen += 1
                    let anchor = textRange.location - 1
                    #expect(main.contains { NSLocationInRange(anchor, $0.range) || NSMaxRange($0.range) == anchor })
                }
                #expect(page.rules.count == (notes.isEmpty ? 0 : 1))
            }
            #expect(seen == 24)
        }
    }
}
