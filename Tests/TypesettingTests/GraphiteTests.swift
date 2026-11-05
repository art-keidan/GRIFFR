import AppKit
import CoreText
import PDFKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Graphite: il ponte verso graphite2 installata nel sistema")
    struct GraphiteTests {
        private func font(_ name: String, size: CGFloat = 20) -> CTFont? {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            return (CTFontCopyPostScriptName(font) as String) == name ? font : nil
        }

        @Test("La libreria si carica dal sistema; senza, Graphite non c'è e nulla si compone")
        func loading() throws {
            #expect(Graphite.isAvailable, "su questo Mac graphite2 c'è (Homebrew)")
            #expect(Graphite.libraryPath?.hasSuffix("libgraphite2.3.dylib") == true)
            #expect(Graphite.API.load(from: ["/percorso/che/non/esiste/libgraphite2.3.dylib"]) == nil)
            let hoefler = try #require(font("HoeflerText-Regular"))
            #expect(!Graphite.hasTables(hoefler))
            #expect(Graphite.shape("prova", font: hoefler) == nil, "un font senza tabelle Graphite non si compone con Graphite")
        }

        @Test("Due file con lo stesso nome PostScript hanno volti Graphite distinti; lo stesso font, sempre lo stesso volto")
        func faceCachePerFile() throws {
            let padauk = try #require(font("Padauk-Regular"), "Padauk installato")
            let original = try #require(CTFontCopyAttribute(padauk, kCTFontURLAttribute) as? URL)
            // Una copia in una cartella temporanea: il font originale non si tocca.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let copy = folder.appendingPathComponent(original.lastPathComponent)
            try FileManager.default.copyItem(at: original, to: copy)
            let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(copy as CFURL) as? [CTFontDescriptor])
            let descriptor = try #require(descriptors.first { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == "Padauk-Regular" })
            let twin = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
            #expect(CTFontCopyPostScriptName(twin) as String == "Padauk-Regular")
            #expect(Graphite.faceKey(for: twin) != Graphite.faceKey(for: padauk), "stesso nome, file diverso")
            let first = try #require(Graphite.face(for: padauk))
            #expect(Graphite.face(for: CTFontCreateWithName("Padauk-Regular" as CFString, 30, nil)) === first, "il corpo non conta")
            #expect(try #require(Graphite.face(for: twin)) !== first)
        }

        @Test("Padauk: un testo birmano composto, con i gruppi che coprono tutto il testo e i glifi tutti assegnati")
        func burmese() throws {
            let padauk = try #require(font("Padauk-Regular"), "Padauk installato")
            #expect(Graphite.hasTables(padauk))
            let text = "မြန်မာစာ"  // «lingua birmana»
            let run = try #require(Graphite.shape(text, font: padauk))
            #expect(!run.glyphs.isEmpty && run.glyphs.count == run.positions.count)
            #expect(run.advance > 0)
            // I gruppi in fila: dal primo all'ultimo carattere, senza buchi né sovrapposizioni; tutti i glifi in un gruppo.
            var next = 0
            for cluster in run.clusters {
                #expect(cluster.characters.location == next)
                next = NSMaxRange(cluster.characters)
            }
            #expect(next == (text as NSString).length)
            #expect(run.clusters.map(\.glyphs.length).reduce(0, +) == run.glyphs.count)
            #expect(run.clusters.count < (text as NSString).length, "i segni stanno nel gruppo della loro consonante")
            // A confronto con Core Text (OpenType) sullo stesso font: la stessa larghezza a meno di un punto, o la differenza
            // da segnare negli appunti.
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: padauk]))
            let coreText = CTLineGetTypographicBounds(line, nil, nil, nil)
            #expect(abs(coreText - run.advance) < 1, "Core Text \(coreText), Graphite \(run.advance)")
        }

        /// Il testo nelle righe della pagina: un paragrafo nel font dato, con Graphite (e le sue funzioni) o senza.
        private func laidOut(_ text: String, font name: String, size: CGFloat = 24, graphite: String?) -> (layout: DocumentLayout, text: NSAttributedString) {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            var attributes: [NSAttributedString.Key: Any] = [.font: font as NSFont]
            if let graphite { attributes[.graphite] = graphite }
            let source = NSAttributedString(string: text, attributes: attributes)
            return (PageLayout.layout(source), source)
        }

        /// La pagina disegnata in memoria, a 2 pixel per punto: i pixel scuri, per posizione.
        private func ink(_ layout: DocumentLayout) -> Set<Int> {
            let size = layout.setup.paperSize
            let width = Int(size.width * 2), height = Int(size.height * 2)
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: 2, y: 2)
            PDFRenderer.draw(layout.pages[0], in: context)
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            var dark = Set<Int>()
            for y in 0..<height { for x in 0..<width where data[y * context.bytesPerRow + x] < 128 { dark.insert(y * width + x) } }
            return dark
        }

        @Test("Nelle righe: i gruppi di Graphite sono spazi delle loro misure per Core Text; la riga è larga quanto Graphite")
        func linesHoldGraphiteRuns() throws {
            let text = "မြန်မာစာ"
            let (layout, _) = laidOut(text, font: "Padauk-Regular", graphite: "")
            let line = try #require(layout.pages.first?.lines.first)
            let run = try #require(Graphite.shape(text, font: CTFontCreateWithName("Padauk-Regular" as CFString, 24, nil)))
            let clusters = (CTLineGetGlyphRuns(line.line) as! [CTRun]).filter {
                (CTRunGetAttributes($0) as NSDictionary)[NSAttributedString.Key.graphiteCluster] != nil
            }
            #expect(clusters.count == run.clusters.count, "un tratto di Core Text per ogni gruppo")
            #expect(abs(line.naturalWidth - run.advance) < 0.01, "riga \(line.naturalWidth), Graphite \(run.advance)")
            // Senza l'attributo, la stessa riga è di Core Text, con la larghezza di Core Text.
            let plain = try #require(laidOut(text, font: "Padauk-Regular", graphite: nil).layout.pages.first?.lines.first)
            #expect(abs(plain.naturalWidth - run.advance) > 0.1)
            // Il cursore va da un gruppo all'altro (dentro un gruppo, per ora, al suo bordo: tappa G.3).
            let caret = try #require(layout.caret(at: run.clusters[1].characters.location, affinity: .downstream))
            #expect(abs(caret.rect.minX - line.origin.x - run.clusters[0].advance) < 0.01)
        }

        @Test("A capo: un testo birmano lungo si divide in righe che non escono dalla colonna")
        func lineBreaking() throws {
            let text = Array(repeating: "မြန်မာစာ သည် မြန်မာနိုင်ငံ ၏ ရုံးသုံး ဘာသာစကား ဖြစ်သည်။", count: 8).joined(separator: " ")
            let (layout, _) = laidOut(text, font: "Padauk-Regular", graphite: "")
            let lines = try #require(layout.pages.first?.lines)
            #expect(lines.count >= 3)
            for line in lines { #expect(line.width <= line.availableWidth + 0.5, "\(line.width) su \(line.availableWidth)") }
            #expect(lines.map(\.range.length).reduce(0, +) == (text as NSString).length, "tutti i caratteri, una volta sola")
            // Ogni riga finisce dove il testo vero permette di andare a capo, mai in mezzo a una parola (con i segnaposto
            // Core Text andava a capo fra due gruppi qualsiasi, nella composizione riga per riga: trovato con il PDF).
            for line in lines.dropLast() {
                let end = NSMaxRange(line.range)
                #expect(GraphiteLayout.lastLineBreak(in: text as NSString, after: line.range.location, notBeyond: end) == end, "a capo a \(end)")
            }
        }

        @Test("Il disegno: si vedono i glifi di Graphite (con le sue funzioni), non quelli di Core Text sotto")
        func drawing() throws {
            let annapurna = CTFontCreateWithName("AnnapurnaSIL-Regular" as CFString, 24, nil)
            let jha = "झ"
            let india = try #require(Graphite.shape(jha, font: annapurna, settings: [GraphiteSetting(id: Graphite.fourCC("cv01"), value: 0)]))
            let nepal = try #require(Graphite.shape(jha, font: annapurna, settings: [GraphiteSetting(id: Graphite.fourCC("cv01"), value: 1)]))
            #expect(india.glyphs != nepal.glyphs, "la jha nepalese è un altro glifo")
            let coreText = ink(laidOut(jha, font: "AnnapurnaSIL-Regular", graphite: nil).layout)
            let plain = ink(laidOut(jha, font: "AnnapurnaSIL-Regular", graphite: "").layout)
            let nepali = ink(laidOut(jha, font: "AnnapurnaSIL-Regular", graphite: "cv01=1").layout)
            #expect(!coreText.isEmpty && plain == coreText, "senza funzioni, Graphite disegna come Core Text")
            let common = nepali.intersection(coreText).count
            #expect(common < coreText.count * 3 / 4, "con cv01=1 il glifo cambia: in comune \(common) pixel su \(coreText.count)")
            #expect(abs(nepali.count - coreText.count) < coreText.count, "un glifo solo, non due sovrapposti")
        }

        @Test("Dentro un gruppo di più grafemi il cursore divide la larghezza in parti uguali; mai in mezzo a un grafemo")
        func caretInsideClusters() throws {
            // Un gruppo fatto a mano: tre caratteri, tre grafemi, largo 30 punti; poi una «x» di Core Text.
            func line(boundaries: [Int]) -> CTLine {
                let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
                let cluster = GraphiteLayout.cluster(width: 30, length: 3, boundaries: boundaries)
                let delegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)
                let text = NSMutableAttributedString(string: "\u{FFFC}\u{FFFC}\u{FFFC}x", attributes: [.font: font])
                text.addAttributes([delegateKey: cluster.delegate, .graphiteCluster: cluster], range: NSRange(location: 0, length: 1))
                text.addAttribute(delegateKey, value: GraphiteLayout.zeroWidthForTests, range: NSRange(location: 1, length: 2))
                return CTLineCreateWithAttributedString(text)
            }
            let three = line(boundaries: [1, 2])
            #expect(GraphiteLayout.offset(in: three, stringIndex: 0) == nil, "i bordi del gruppo restano a Core Text")
            #expect(GraphiteLayout.offset(in: three, stringIndex: 1) == 10)
            #expect(GraphiteLayout.offset(in: three, stringIndex: 2) == 20)
            #expect(GraphiteLayout.offset(in: three, stringIndex: 3) == nil)
            #expect(abs(CTLineGetOffsetForStringIndex(three, 3, nil) - 30) < 0.01)
            #expect(GraphiteLayout.stringIndex(in: three, offset: 4) == 0)
            #expect(GraphiteLayout.stringIndex(in: three, offset: 12) == 1)
            #expect(GraphiteLayout.stringIndex(in: three, offset: 26) == 3)
            #expect(GraphiteLayout.stringIndex(in: three, offset: 31) == nil, "sulla «x» decide Core Text")
            // Un gruppo di tre caratteri che è un grafemo solo: il cursore sta all'inizio o alla fine, mai dentro.
            let one = line(boundaries: [])
            #expect(GraphiteLayout.offset(in: one, stringIndex: 2) == 0)
            #expect(GraphiteLayout.stringIndex(in: one, offset: 14) == 0)
            #expect(GraphiteLayout.stringIndex(in: one, offset: 16) == 3)
        }

        @Test("Il cursore su un testo birmano vero: avanza a ogni grafemo, e un clic dove sta riporta allo stesso punto")
        func caretRoundTrip() throws {
            let text = "ကျွန်ုပ် မြန်မာ သင်္ချိုင်း"
            let (layout, _) = laidOut(text, font: "Padauk-Regular", graphite: "")
            let string = text as NSString
            var stops = [0]
            while stops.last! < string.length { stops.append(NSMaxRange(string.rangeOfComposedCharacterSequence(at: stops.last!))) }
            var previous = -CGFloat.infinity
            for stop in stops {
                let caret = try #require(layout.caret(at: stop, affinity: .downstream))
                #expect(caret.rect.minX > previous, "il cursore avanza al grafemo che comincia a \(stop)")
                previous = caret.rect.minX
                let hit = try #require(layout.position(at: CGPoint(x: caret.rect.minX + 0.01, y: caret.rect.midY), onPage: 0))
                #expect(hit.index == stop, "un clic a \(caret.rect.minX) porta a \(hit.index), non a \(stop)")
            }
            // A metà del primo gruppo (tre caratteri, un grafemo): l'inizio o la fine, mai in mezzo.
            let start = try #require(layout.caret(at: 0)), end = try #require(layout.caret(at: stops[1]))
            for fraction in [0.3, 0.45, 0.55, 0.7] {
                let x = start.rect.minX + (end.rect.minX - start.rect.minX) * fraction
                let hit = try #require(layout.position(at: CGPoint(x: x, y: start.rect.midY), onPage: 0))
                #expect(hit.index == 0 || hit.index == stops[1], "a \(fraction) del gruppo: \(hit.index)")
            }
            // La selezione del secondo grafemo: un rettangolo largo quanto il suo gruppo.
            let rects = layout.selectionRects(for: NSRange(location: stops[1], length: stops[2] - stops[1]))
            #expect(rects.count == 1)
        }

        @Test("I segni vocalici stanno nel gruppo della loro consonante: riga, selezione e spazi tornano con Graphite")
        func marksJoinTheirConsonant() throws {
            // Segnalato da Artemij Keidan (20 ottobre 2026): con Graphite la selezione escludeva il danda finale e il
            // pallino dello spazio cadeva sulla «व». Graphite faceva un gruppo a sé, largo −0,4 punti, della matra «े».
            let text = "सत्यमेव जयते।"
            let (layout, _) = laidOut(text, font: "AnnapurnaSIL-Regular", size: 40, graphite: "")
            let run = try #require(Graphite.shape(text, font: CTFontCreateWithName("AnnapurnaSIL-Regular" as CFString, 40, nil)))
            let string = text as NSString
            #expect(run.clusters.allSatisfy { $0.advance >= 0 })
            #expect(run.clusters.allSatisfy { string.rangeOfComposedCharacterSequence(at: $0.characters.location).location == $0.characters.location })
            #expect(run.clusters.map { string.substring(with: $0.characters) }.contains("मे"))
            let line = try #require(layout.pages.first?.lines.first)
            #expect(abs(line.width - run.advance) < 0.01)
            let selection = layout.selectionRects(for: NSRange(location: 0, length: string.length))
            #expect(selection.count == 1 && abs(selection[0].rect.maxX - line.origin.x - run.advance) < 0.01, "la selezione arriva in fondo al danda")
            let space = try #require(layout.invisibleMarks(onPage: 0).first { $0.kind == .space })
            let spaceCluster = try #require(run.clusters.first { string.substring(with: $0.characters) == " " })
            let spaceStart = run.positions[spaceCluster.glyphs.location].x
            #expect(abs(space.rect.minX - line.origin.x - spaceStart) < 0.01 && abs(space.rect.width - spaceCluster.advance) < 0.01,
                    "il pallino sta nello spazio")
        }

        @Test("La lingua arriva ai due motori: del tratto o del documento; la jha nepalese di Annapurna SIL per il nepalese")
        func languageReachesBothEngines() throws {
            func glyphs(runLanguage: String?, documentLanguage: String?, graphite: String?) -> [CGGlyph] {
                var style = CharacterStyle(fontName: "AnnapurnaSIL-Regular", size: 24, language: runLanguage)
                style.graphite = graphite
                var document = Document(styles: .builtIn, blocks: [.paragraph(Paragraph(inlines: [.text(TextRun("झ", style: style))]))])
                document.language = documentLanguage
                let layout = PageLayout.layout(document.attributedString().text, options: document.layoutOptions)
                return (CTLineGetGlyphRuns(layout.pages[0].lines[0].line) as! [CTRun]).flatMap { run -> [CGGlyph] in
                    if let cluster = (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.graphiteCluster] as? GraphiteLayout.Cluster { return cluster.glyphs }
                    guard (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] == nil else { return [] }
                    var ids = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                    CTRunGetGlyphs(run, CFRange(), &ids)
                    return ids
                }
            }
            for graphite in [nil, ""] as [String?] {
                let engine = graphite == nil ? "Core Text" : "Graphite"
                #expect(glyphs(runLanguage: nil, documentLanguage: "it", graphite: graphite) == [411], "\(engine): la jha indiana")
                #expect(glyphs(runLanguage: "ne", documentLanguage: "it", graphite: graphite) == [412], "\(engine): nepalese dal tratto")
                #expect(glyphs(runLanguage: nil, documentLanguage: "ne", graphite: graphite) == [412], "\(engine): nepalese dal documento")
                #expect(glyphs(runLanguage: "new", documentLanguage: "ne", graphite: graphite) == [413], "\(engine): il tratto vince sul documento")
            }
        }

        @Test("Il PDF: il testo Graphite si estrae com'è scritto, nell'ordine in cui si legge, e si trova cercandolo")
        func pdfText() throws {
            // Senza la tappa G.5 PDFKit estraeva solo segnaposto (U+FFFC); Core Text stesso dà «िकताब» e «ြမန်».
            for (font, text) in [("AnnapurnaSIL-Regular", "सत्यमेव जयते। किताब"), ("Padauk-Regular", "မြန်မာစာ ကျွန်ုပ်")] {
                let (layout, _) = laidOut(text, font: font, size: 20, graphite: "")
                let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
                #expect(pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines) == text, "\(font)")
                #expect(pdf.string?.contains("\u{FFFC}") == false)
            }
            // Una riga mista: un'etichetta latina di Core Text e il testo Graphite.
            let mixed = NSMutableAttributedString(string: "Esempio: ", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 14)!])
            mixed.append(NSAttributedString(string: "किताब पढ़ो", attributes: [.font: NSFont(name: "AnnapurnaSIL-Regular", size: 20)!, .graphite: ""]))
            mixed.append(NSAttributedString(string: " fine.", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 14)!]))
            let mixedLayout = PageLayout.layout(mixed)
            let mixedPDF = try #require(PDFDocument(data: PDFRenderer.pdfData(for: mixedLayout)))
            #expect(mixedPDF.string?.trimmingCharacters(in: .whitespacesAndNewlines) == "Esempio: किताब पढ़ो fine.")
            // Cercando la parola la si trova dove sta sulla pagina.
            let found = try #require(mixedPDF.findString("पढ़ो", withOptions: []).first)
            let page = try #require(mixedPDF.page(at: 0))
            let bounds = found.bounds(for: page)
            let line = try #require(mixedLayout.pages[0].lines.first)
            #expect(abs(bounds.midY - line.origin.y) < 20, "sulla riga: \(bounds) contro la linea di base \(line.origin.y)")
            #expect(bounds.minX > line.origin.x + 60, "dopo «Esempio: किताब»")
            // Un paragrafo lungo, su più righe: tutto il testo, una volta sola.
            let long = Array(repeating: "सत्यमेव जयते।", count: 12).joined(separator: " ")
            let (longLayout, _) = laidOut(long, font: "AnnapurnaSIL-Regular", size: 20, graphite: "")
            #expect(longLayout.pages[0].lines.count > 1)
            let extracted = try #require(PDFDocument(data: PDFRenderer.pdfData(for: longLayout))?.string)
            #expect(extracted.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty } == long.components(separatedBy: " "))
        }

        @Test("Il PDF anche con Core Text: devanagari e birmano si estraggono nell'ordine in cui si leggono")
        func pdfCoreTextOrder() throws {
            // Prima Core Text scriveva i glifi nell'ordine in cui li disegna: «िकताब», «कर्», «कू ँ», «ြမန်».
            for (font, text) in [("AnnapurnaSIL-Regular", "किताब र्क कूँ र्द्धं सत्यमेव जयते।"), ("Padauk-Regular", "မြန်မာစာ ကျွန်ုပ်"),
                                 ("KohinoorDevanagari-Regular", "किताब पढ़िए")] {
                let (layout, _) = laidOut(text, font: font, size: 20, graphite: nil)
                let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout)))
                #expect(pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines) == text, "\(font)")
            }
            // Il latino resta testo vero, e una riga mista esce nell'ordine giusto.
            let mixed = NSMutableAttributedString(string: "Esempio: ", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 14)!])
            mixed.append(NSAttributedString(string: "किताब", attributes: [.font: NSFont(name: "AnnapurnaSIL-Regular", size: 20)!]))
            mixed.append(NSAttributedString(string: " fine.", attributes: [.font: NSFont(name: "HoeflerText-Regular", size: 14)!]))
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: PageLayout.layout(mixed))))
            #expect(pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines) == "Esempio: किताब fine.")
        }

        @Test("Il PDF disegna il testo Graphite come lo schermo: i contorni dei glifi al loro posto")
        func pdfDrawing() throws {
            let (layout, _) = laidOut("सत्यमेव जयते।", font: "AnnapurnaSIL-Regular", size: 24, graphite: "cv01=1")
            let screen = ink(layout)
            let pdf = try #require(PDFDocument(data: PDFRenderer.pdfData(for: layout))?.page(at: 0))
            let size = layout.setup.paperSize
            let width = Int(size.width * 2), height = Int(size.height * 2)
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: 2, y: 2)
            pdf.draw(with: .mediaBox, to: context)
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            var printed = Set<Int>()
            for y in 0..<height { for x in 0..<width where data[y * context.bytesPerRow + x] < 128 { printed.insert(y * width + x) } }
            // Nel PDF i glifi Graphite sono contorni, che lo schermo non ispessisce come il testo: un filo più sottili. Il
            // disegno del PDF sta quasi tutto dentro quello dello schermo, e occupa lo stesso spazio.
            let common = screen.intersection(printed).count
            #expect(!screen.isEmpty && common > printed.count * 8 / 10, "in comune \(common) pixel: schermo \(screen.count), PDF \(printed.count)")
            func box(_ pixels: Set<Int>) -> (Int, Int, Int, Int) {
                (pixels.map { $0 % width }.min()!, pixels.map { $0 % width }.max()!, pixels.map { $0 / width }.min()!, pixels.map { $0 / width }.max()!)
            }
            let (a, b) = (box(screen), box(printed))
            #expect(abs(a.0 - b.0) <= 2 && abs(a.1 - b.1) <= 2 && abs(a.2 - b.2) <= 2 && abs(a.3 - b.3) <= 2, "schermo \(a), PDF \(b)")
        }

        @Test("La scelta Graphite nel modello: nel file, negli stili, nell'ispettore; i tratti rimasti a Core Text si contano")
        func choiceInModel() throws {
            #expect(Graphite.encodedChoice(nil) == "off" && Graphite.encodedChoice("") == "on" && Graphite.encodedChoice("cv01=1") == "cv01=1")
            #expect(Graphite.choice(fromEncoded: "off") == .some(nil) && Graphite.choice(fromEncoded: "on") == .some(""))
            #expect(Graphite.choice(fromEncoded: "cv01=1 lldt=1") == .some("cv01=1 lldt=1"))
            #expect(Graphite.choice(fromEncoded: "boh") == nil)
            // Uno stile di carattere «Birmano» che chiede Graphite, dato a un pezzo di testo; un altro pezzo con le funzioni.
            let padauk = CharacterStyle(fontName: "Padauk-Regular", size: 14)
            var sheet = StyleSheet.builtIn
            var birmano = StyleValues()
            birmano.graphite = "on"
            sheet.styles.append(NamedStyle(name: "Birmano", target: .character, values: birmano))
            var withFeatures = padauk
            withFeatures.graphite = "lldt=1"
            var document = Document(styles: sheet, blocks: [.paragraph(Paragraph(styleName: "Body", inlines: [
                .text(TextRun("မြန်မာ", style: { var s = padauk; s.graphite = ""; return s }(), characterStyleName: "Birmano")),
                .text(TextRun(" စာ", style: withFeatures)),
            ]))])
            let saved = DocumentFormat.string(for: document)
            #expect(saved.contains("graphite=\"on\""), "lo stile e il tratto")
            #expect(saved.contains("graphite=\"lldt=1\""))
            let reread = try DocumentFormat.document(from: saved)
            #expect(reread.styles.style(named: "Birmano")?.values.graphite == "on")
            let text = reread.attributedString().text
            #expect(text.attribute(.graphite, at: 0, effectiveRange: nil) as? String == "")
            #expect(text.attribute(.graphite, at: 7, effectiveRange: nil) as? String == "lldt=1")
            #expect(throws: DocumentFormatError.self) { try DocumentFormat.document(from: saved.replacingOccurrences(of: "graphite=\"on\"", with: "graphite=\"forse\"")) }
            // L'ispettore: Composizione Graphite, dallo stile «Birmano».
            let inspected = TextStyling.inspect(.character, in: text, range: NSRange(location: 1, length: 0), sheet: reread.styles)
            let shaping = try #require(inspected.first { $0.property == .shaping })
            #expect(shaping.value.graphite == "on" && shaping.source == .style("Birmano"))
            // Nessun tratto resta a Core Text; con Graphite su Hoefler Text, uno.
            #expect(PageLayout.layout(text).graphiteFallbacks == 0)
            document.blocks = [.paragraph(Paragraph(inlines: [.text(TextRun("Hoefler", style: { var s = CharacterStyle(fontName: "HoeflerText-Regular", size: 12); s.graphite = ""; return s }()))]))]
            #expect(PageLayout.layout(document.attributedString().text).graphiteFallbacks == 1)
        }

        @Test("Annapurna SIL: devanagari; le funzioni Graphite del font, con nomi e valori")
        func devanagariAndFeatures() throws {
            let annapurna = try #require(font("AnnapurnaSIL-Regular"), "Annapurna SIL installato")
            let run = try #require(Graphite.shape("संस्कृतम्", font: annapurna))
            #expect(run.clusters.count >= 2 && run.advance > 0)
            let features = Graphite.features(of: annapurna)
            #expect(!features.isEmpty)
            #expect(features.allSatisfy { !$0.name.isEmpty && !$0.tag.isEmpty })
            #expect(features.contains { $0.values.count >= 2 && $0.values.contains { $0.value == $0.value } })
            // Una funzione con più valori cambia davvero la composizione di qualche testo, o almeno non la rompe.
            if let feature = features.first(where: { $0.values.count >= 2 }),
               let other = feature.values.first(where: { $0.value != feature.defaultValue }) {
                let changed = Graphite.shape("संस्कृतम् १२३", font: annapurna, settings: [GraphiteSetting(id: feature.id, value: other.value)])
                #expect(changed != nil)
            }
        }
        @Test("La memoria dei tratti composti distingue due istanze dello stesso font variabile (stesso nome di partenza, stesso corpo)")
        func cacheKeyDistinguishesVariations() throws {
            // Skia, variabile, è nel sistema; per la chiave non servono le tabelle di Graphite. Visto il 26 ottobre: Core Text
            // mette già le coordinate nel nome PostScript di un'istanza («Skia-Regular_wght14CCC…»); la chiave ha in più il
            // file e gli assi, per il caso di due file con lo stesso nome.
            let base = CTFontCreateWithName("Skia-Regular" as CFString, 12, nil)
            try #require(CTFontCopyPostScriptName(base) as String == "Skia-Regular")
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [NSNumber(value: 0x7767_6874): NSNumber(value: 1.3)]] as CFDictionary)
            let heavier = CTFontCreateCopyWithAttributes(base, 12, nil, descriptor)
            let plainKey = GraphiteLayout.cacheKey("testo", font: base, settings: "", language: nil)
            #expect(plainKey == GraphiteLayout.cacheKey("testo", font: CTFontCreateWithName("Skia-Regular" as CFString, 12, nil), settings: "", language: nil))
            let heavierKey = GraphiteLayout.cacheKey("testo", font: heavier, settings: "", language: nil)
            #expect(plainKey != heavierKey, "un'altra istanza, la stessa chiave")
            #expect(!heavierKey.variation.isEmpty && heavierKey.fontFile.hasSuffix("Skia.ttf"))
        }
    }
}
