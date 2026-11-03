import AppKit

/// I punti in cui una parola si può dividere a fine riga.
///
/// Per le lingue che macOS conosce si usa il suo dizionario di sillabazione. Per le altre (latino, greco antico,
/// sanscrito) si usano i modelli di TeX, applicati con l'algoritmo di Liang («Word Hy-phen-a-tion by Com-put-er»,
/// 1983): ogni modello è un frammento di parola con un numero tra le lettere; dove i modelli si sovrappongono
/// vince il numero più alto, e la parola si può dividere dove il numero che resta è dispari.
public enum Hyphenation {
    /// Le lingue per cui il programma porta con sé i modelli di TeX, con le lunghezze minime (in caratteri) dei
    /// pezzi prima e dopo il trattino. Gli autori dei modelli ammettono anche un solo carattere per greco antico
    /// e sanscrito; qui non si scende sotto due.
    private static let bundled: [String: (file: String, left: Int, right: Int)] = [
        "la": ("hyph-la", 2, 2),
        "la-x-classic": ("hyph-la-x-classic", 2, 2),
        "grc": ("hyph-grc", 2, 2),
        "sa": ("hyph-sa", 2, 3),
    ]

    /// Le lingue sillabate con i modelli di TeX.
    public static var patternLanguages: [String] { bundled.keys.sorted() }

    /// Se una lingua (per esempio "it", "la", "grc") si può sillabare, con il sistema o con i nostri modelli.
    public static func isAvailable(for language: String) -> Bool {
        bundled[language] != nil || CFStringIsHyphenationAvailableForLocale(Locale(identifier: language) as CFLocale)
    }

    /// La lingua con cui dividere la parola che comincia a `index`: quella assegnata a quel testo (attributo
    /// `.language`), altrimenti quella predefinita.
    static func language(in paragraph: NSAttributedString, at index: Int, default defaultLanguage: String?) -> String? {
        // Il testo che non si vuole dividere (sillabazione spenta per quel tratto) non ha lingua per la sillabazione.
        if paragraph.attribute(.hyphenates, at: index, effectiveRange: nil) as? Bool == false { return nil }
        return (paragraph.attribute(.language, at: index, effectiveRange: nil) as? String) ?? defaultLanguage
    }

    /// Un punto di divisione: l'indice UTF-16 del primo carattere che va a capo, e il trattino da aggiungere.
    struct Point: Equatable {
        var index: Int
        var hyphen: String
    }

    /// I punti in cui si può dividere una parola, in ordine crescente. Restano sempre almeno due caratteri prima
    /// del trattino e due dopo (una lettera con i suoi accenti conta per uno).
    static func points(in string: NSString, word: NSRange, language: String) -> [Point] {
        if let patterns = patterns(for: language) {
            return patterns.breaks(in: string, word: word).map { Point(index: $0, hyphen: "-") }
        }
        guard let locale = systemLocale(for: language) else { return [] }
        var result: [Point] = []
        var limit = NSMaxRange(word)
        while limit > word.location {
            var character: UTF32Char = 0
            let point = CFStringGetHyphenationLocationBeforeIndex(string, limit, CFRange(location: word.location, length: word.length), 0, locale, &character)
            guard point != kCFNotFound, point - word.location >= 2 else { break }
            limit = point
            guard NSMaxRange(word) - point >= 2 else { continue }
            result.append(Point(index: point, hyphen: Unicode.Scalar(character).flatMap { $0.value > 0 ? String($0) : nil } ?? "-"))
        }
        return result.reversed()
    }

    // MARK: Dizionario del sistema

    nonisolated(unsafe) private static var systemLocales: [String: CFLocale?] = [:]

    /// Il dizionario di sillabazione del sistema per una lingua, se c'è.
    private static func systemLocale(for language: String) -> CFLocale? {
        lock.lock()
        defer { lock.unlock() }
        if let known = systemLocales[language] { return known }
        let locale = Locale(identifier: language) as CFLocale
        let found: CFLocale? = CFStringIsHyphenationAvailableForLocale(locale) ? locale : nil
        systemLocales[language] = .some(found)
        return found
    }

    // MARK: Modelli

    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded: [String: HyphenationPatterns?] = [:]

    private static func patterns(for language: String) -> HyphenationPatterns? {
        guard let entry = bundled[language] else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let known = loaded[language] { return known }
        var patterns: HyphenationPatterns?
        if let url = resourceDirectory?.appendingPathComponent(entry.file + ".pat.txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
            patterns = HyphenationPatterns(text: text, leftMinimum: entry.left, rightMinimum: entry.right)
        }
        loaded[language] = .some(patterns)
        return patterns
    }

    /// La cartella dei modelli: dentro l'applicazione confezionata, oppure tra le risorse del pacchetto.
    private static let resourceDirectory: URL? = {
        if let inApp = Bundle.main.resourceURL?.appendingPathComponent("Hyphenation"), FileManager.default.fileExists(atPath: inApp.path) { return inApp }
        return Bundle.module.url(forResource: "Hyphenation", withExtension: nil)
    }()
}

/// Un insieme di modelli di sillabazione di TeX, pronto per essere applicato alle parole.
///
/// Parole e modelli si confrontano in forma decomposta (una lettera accentata è la lettera seguita dai suoi
/// segni) e in minuscolo: così non importa come gli accenti sono scritti nel testo o nel file dei modelli.
final class HyphenationPatterns: @unchecked Sendable {
    let leftMinimum: Int
    let rightMinimum: Int
    // L'albero dei modelli: da un nodo e una lettera si arriva al nodo successivo; un nodo che chiude un modello
    // ne porta i numeri, uno per ogni posizione tra le lettere (compresi i due estremi).
    private var edges: [UInt64: UInt32] = [:]
    private var levels: [UInt32: [UInt8]] = [:]
    private var nodeCount: UInt32 = 1
    // Le divisioni già calcolate, parola per parola. Non una `NSCache`, che il sistema può svuotare quando vuole.
    // La chiave è una `NSString`, confrontata carattere per carattere: per una `String` di Swift la stessa parola
    // con gli accenti composti o separati sarebbe la stessa chiave, ma le posizioni in UTF-16 sono diverse.
    private var cache: [NSString: [Int]] = [:]
    private let cacheLock = NSLock()

    private static let boundary: UInt32 = 0x2E  // il punto, che nei modelli segna l'inizio o la fine della parola

    init(text: String, leftMinimum: Int, rightMinimum: Int) {
        self.leftMinimum = leftMinimum
        self.rightMinimum = rightMinimum
        for pattern in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            var letters: [Unicode.Scalar] = []
            var numbers: [UInt8] = [0]
            for scalar in pattern.unicodeScalars {
                if let digit = UInt8(String(scalar)), scalar.isASCII {
                    numbers[numbers.count - 1] = digit
                } else {
                    letters.append(scalar)
                    numbers.append(0)
                }
            }
            insert(letters: letters, numbers: numbers)
        }
    }

    private func insert(letters: [Unicode.Scalar], numbers: [UInt8]) {
        // Si decompone un gruppo alla volta (una lettera con i segni che la seguono), tenendo i numeri ai suoi bordi.
        var decomposed: [UInt32] = []
        var decomposedNumbers: [UInt8] = [numbers[0]]
        var index = 0
        while index < letters.count {
            var end = index + 1
            while end < letters.count, Self.isMark(letters[end]) { end += 1 }
            let group = Array(letters[index..<end])
            let canonical = Self.decompose(group)
            if canonical.map(\.value) == group.map(\.value) {
                for offset in 0..<group.count {
                    decomposed.append(group[offset].value)
                    decomposedNumbers.append(numbers[index + offset + 1])
                }
            } else {
                for scalar in canonical {
                    decomposed.append(scalar.value)
                    decomposedNumbers.append(0)
                }
                decomposedNumbers[decomposedNumbers.count - 1] = numbers[end]
            }
            index = end
        }
        var node: UInt32 = 0
        for letter in decomposed {
            let key = UInt64(node) << 32 | UInt64(letter)
            if let next = edges[key] {
                node = next
            } else {
                edges[key] = nodeCount
                node = nodeCount
                nodeCount += 1
            }
        }
        if let existing = levels[node] {
            levels[node] = zip(existing, decomposedNumbers).map(max)
        } else {
            levels[node] = decomposedNumbers
        }
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    private static func decompose(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return Array(String(view).decomposedStringWithCanonicalMapping.unicodeScalars)
    }

    private static let apostrophes: Set<unichar> = [0x27, 0x2019, 0x02BC, 0x1FBD, 0x1FBF]

    /// Gli indici UTF-16, nella stringa, in cui la parola si può dividere.
    func breaks(in string: NSString, word: NSRange) -> [Int] {
        var range = word
        // L'apostrofo dell'elisione fa parte della parola per i modelli (in greco: «ἀλλ'»).
        if NSMaxRange(range) < string.length, Self.apostrophes.contains(string.character(at: NSMaxRange(range))) { range.length += 1 }
        let text = string.substring(with: range) as NSString
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let offsets: [Int]
        if let known = cache[text] {
            offsets = known
        } else {
            offsets = breakOffsets(in: text as String, wordLength: word.length)
            if cache.count >= 50_000 { cache.removeAll(keepingCapacity: true) }
            cache[text] = offsets
        }
        return offsets.map { word.location + $0 }
    }

    /// Le distanze UTF-16 dall'inizio della parola dei punti in cui si può dividere.
    private func breakOffsets(in text: String, wordLength: Int) -> [Int] {
        // Le lettere della parola in forma decomposta e minuscola. Di ciascuna si ricorda dove comincia nel testo
        // (in UTF-16 e in caratteri) il gruppo a cui appartiene, e se è la prima del gruppo: si divide solo lì.
        // I caratteri si contano in forma composta, come li conta TeX: il conto non dipende da come sono scritti gli accenti.
        var letters: [UInt32] = [Self.boundary]
        var starts: [(utf16: Int, characters: Int, isFirst: Bool)] = [(0, 0, false)]
        let scalars = Array(text.unicodeScalars)
        var utf16 = 0
        var characters = 0
        var index = 0
        while index < scalars.count {
            var end = index + 1
            while end < scalars.count, Self.isMark(scalars[end]) { end += 1 }
            let group = scalars[index..<end].map { scalar -> Unicode.Scalar in
                let lower = scalar.properties.lowercaseMapping.unicodeScalars
                return lower.count == 1 ? lower.first! : scalar
            }
            let decomposed = Self.decompose(group)
            for (position, scalar) in decomposed.enumerated() {
                letters.append(scalar.value)
                starts.append((utf16, characters, position == 0))
            }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: decomposed)
            characters += String(view).precomposedStringWithCanonicalMapping.unicodeScalars.count
            utf16 += scalars[index..<end].reduce(0) { $0 + $1.utf16.count }
            index = end
        }
        letters.append(Self.boundary)
        starts.append((utf16, characters, false))

        var numbers = [UInt8](repeating: 0, count: letters.count + 1)
        for start in letters.indices {
            var node: UInt32 = 0
            var position = start
            while position < letters.count, let next = edges[UInt64(node) << 32 | UInt64(letters[position])] {
                node = next
                position += 1
                if let found = levels[node] {
                    for (offset, value) in found.enumerated() where value > numbers[start + offset] { numbers[start + offset] = value }
                }
            }
        }

        var result: [Int] = []
        // `numbers[position]` è il numero davanti a `letters[position]`; la posizione 0 è il punto iniziale.
        for position in 2..<max(letters.count - 1, 2) where numbers[position] % 2 == 1 && starts[position].isFirst {
            let before = starts[position].characters, after = characters - before
            let offset = starts[position].utf16
            guard before >= leftMinimum, after >= rightMinimum, offset < wordLength else { continue }
            result.append(offset)
        }
        return result
    }
}
