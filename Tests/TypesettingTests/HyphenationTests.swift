import AppKit
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Sillabazione con i modelli di TeX")
    struct HyphenationTests {
        /// La parola con un trattino in ogni punto in cui si può dividere.
        private func divided(_ word: String, _ language: String) -> String {
            let string = word as NSString
            let points = Hyphenation.points(in: string, word: NSRange(location: 0, length: string.length), language: language).map(\.index)
            var result = ""
            for index in 0..<string.length {
                if points.contains(index) { result += "-" }
                result += string.substring(with: NSRange(location: index, length: 1))
            }
            return result
        }

        // Le divisioni attese sono quelle osservate applicando i modelli scaricati: servono a segnalare un
        // cambiamento, non sono state confrontate con un'edizione a stampa.

        @Test("Latino: modelli moderni e modelli classici", arguments: [
            ("la", "consuetudinem", "con-sue-tu-di-nem"), ("la", "dominus", "do-mi-nus"), ("la", "philosophia", "phi-lo-so-phia"),
            ("la", "Gallia", "Gal-lia"), ("la", "abstulit", "ab-stu-lit"), ("la", "propterea", "prop-te-rea"),
            ("la", "CONSUETUDINEM", "CON-SUE-TU-DI-NEM"),
            ("la-x-classic", "abstulit", "abs-tu-lit"), ("la-x-classic", "propterea", "prop-ter-ea"), ("la-x-classic", "aequitas", "ae-qui-tas"),
        ])
        func latin(language: String, word: String, expected: String) {
            #expect(divided(word, language) == expected)
        }

        @Test("Greco antico, con gli accenti scritti in un carattere solo o separati", arguments: [
            ("ἄνθρωπος", "ἄν-θρω-πος"), ("φιλοσοφία", "φι-λο-σο-φία"), ("θάλασσα", "θά-λασ-σα"), ("πολυτρόπως", "πο-λυ-τρό-πως"),
            ("ΑΝΘΡΩΠΟΣ", "ΑΝ-ΘΡΩ-ΠΟΣ"), ("Ἀθηναῖοι", "Ἀθη-ναῖ-οι"),
        ])
        func ancientGreek(word: String, expected: String) {
            #expect(divided(word, "grc") == expected)
            // In forma decomposta i punti cadono tra le stesse lettere, mai tra una lettera e il suo accento.
            #expect(divided(word.decomposedStringWithCanonicalMapping, "grc").precomposedStringWithCanonicalMapping == expected)
        }

        @Test("Sanscrito, in traslitterazione e in devanāgarī", arguments: [
            ("dharmakṣetre", "dha-rma-kṣe-tre"), ("kurukṣetre", "ku-ru-kṣe-tre"), ("saṃskṛtam", "saṃ-skṛ-tam"), ("yuyutsavaḥ", "yu-yu-tsa-vaḥ"),
            ("कुरुक्षेत्रे", "कु-रु-क्षे-त्रे"), ("धर्मक्षेत्रे", "धर्म-क्षे-त्रे"), ("संस्कृतम्", "सं-स्कृ-तम्"),
        ])
        func sanskrit(word: String, expected: String) {
            #expect(divided(word, "sa") == expected)
            #expect(divided(word.decomposedStringWithCanonicalMapping, "sa").precomposedStringWithCanonicalMapping == expected)
        }

        @Test("In devanāgarī non si divide mai davanti a un segno vocalico o a un virama")
        func noBreakBeforeMarks() {
            for word in ["धर्मक्षेत्रे", "कुरुक्षेत्रे", "समवेता", "युयुत्सवः", "संस्कृतम्", "मामकाः", "पाण्डवाश्चैव"] {
                let string = word as NSString
                for point in Hyphenation.points(in: string, word: NSRange(location: 0, length: string.length), language: "sa") {
                    let category = Unicode.Scalar(string.character(at: point.index))!.properties.generalCategory
                    #expect(![.nonspacingMark, .spacingMark].contains(category), "\(word) diviso davanti a un segno")
                }
            }
        }

        @Test("Le lingue del sistema passano dal dizionario di macOS; una lingua sconosciuta non divide nulla")
        func systemAndUnknown() {
            #expect(divided("tipografia", "it") == "ti-po-gra-fia")
            #expect(divided("consuetudinem", "got") == "consuetudinem")
            #expect(Hyphenation.isAvailable(for: "la") && Hyphenation.isAvailable(for: "grc") && Hyphenation.isAvailable(for: "sa") && Hyphenation.isAvailable(for: "it"))
            #expect(!Hyphenation.isAvailable(for: "got"))
        }

        private let caesar = "Gallia est omnis divisa in partes tres, quarum unam incolunt Belgae, aliam Aquitani, tertiam qui ipsorum lingua Celtae, nostra Galli appellantur. Hi omnes lingua, institutis, legibus inter se differunt. Horum omnium fortissimi sunt Belgae, propterea quod a cultu atque humanitate provinciae longissime absunt."

        /// Le righe di un testo composto in una colonna di 150 punti.
        private func narrowLines(_ source: NSAttributedString, _ options: LayoutOptions) -> [PlacedLine] {
            var setup = PageSetup.a4
            setup.right = setup.paperSize.width - setup.left - 150
            return PageLayout.layout(source, setup: setup, options: options).pages.flatMap(\.lines)
        }

        @Test("Ogni parola si divide secondo la lingua assegnata al suo testo, non secondo quella del documento")
        func languageOfTheText() throws {
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let attributes: [NSAttributedString.Key: Any] = [.font: try TestFonts.hoefler(size: 14), .paragraphStyle: style]
            let length = (caesar as NSString).length
            func hyphens(language: String?, document: String?, hyphenates: Bool = true, _ breaking: LayoutOptions.LineBreaking = .optimal) -> Int {
                let source = NSMutableAttributedString(string: caesar, attributes: attributes)
                if let language { source.addAttribute(.language, value: language, range: NSRange(location: 0, length: length)) }
                let lines = narrowLines(source, LayoutOptions(hyphenationLanguage: document, hyphenates: hyphenates, lineBreaking: breaking))
                #expect(lines.map(\.range.length).reduce(0, +) == length)
                return lines.filter(\.endsWithHyphen).count
            }
            for breaking in [LayoutOptions.LineBreaking.optimal, .firstFit] {
                // Testo marcato come latino: si divide anche se il documento non ha lingua, o ne ha una che non si sa dividere.
                #expect(hyphens(language: "la", document: nil, breaking) > 0)
                #expect(hyphens(language: "la", document: "got", breaking) > 0)
                // Testo marcato con una lingua che non si sa dividere, in un documento italiano: nessun trattino.
                #expect(hyphens(language: "got", document: "it", breaking) == 0)
                // Con la sillabazione spenta non si divide nulla, qualunque lingua abbia il testo.
                #expect(hyphens(language: "la", document: "it", hyphenates: false, breaking) == 0)
                #expect(hyphens(language: nil, document: nil, breaking) == 0)
            }
        }

        @Test("Un paragrafo latino in una colonna stretta va a capo con i trattini, senza perdere caratteri")
        func latinParagraph() throws {
            let text = caesar
            let style = NSMutableParagraphStyle()
            style.alignment = .justified
            let source = NSAttributedString(string: text, attributes: [.font: try TestFonts.hoefler(size: 14), .paragraphStyle: style])
            let lines = narrowLines(source, LayoutOptions(hyphenationLanguage: "la"))
            #expect(lines.contains { $0.endsWithHyphen })
            #expect(lines.map(\.range.length).reduce(0, +) == (text as NSString).length)
            let without = narrowLines(source, LayoutOptions(hyphenationLanguage: "got"))
            #expect(without.allSatisfy { !$0.endsWithHyphen })
        }
    }
}
