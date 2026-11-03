import CoreText
import Foundation

/// Un a capo deciso per un paragrafo: dove comincia la riga successiva, e se la riga finisce con un trattino.
struct LineBreak: Equatable {
    /// Indice, relativo al paragrafo, del primo carattere della riga successiva.
    var end: Int
    /// Trattino di sillabazione da aggiungere in fondo alla riga; `nil` se la riga finisce tra due parole.
    var hyphen: String?
}

/// Scelta degli a capo sull'intero paragrafo, secondo l'algoritmo di Knuth e Plass («Breaking Paragraphs into
/// Lines», 1981), quello usato da TeX.
///
/// Invece di riempire ogni riga il più possibile, si considerano tutti i punti in cui il paragrafo può andare a capo
/// e si cerca la combinazione di costo minimo. Il costo di una riga cresce col cubo di quanto i suoi spazi vanno
/// allargati o ristretti; si aggiungono penalità per i trattini, per due trattini di seguito, per un trattino sulla
/// penultima riga e per una riga stretta accanto a una larga. Le penalità sono quelle predefinite di TeX;
/// l'elasticità degli spazi e il limite di trattini consecutivi sono scelte nostre, spiegate più sotto.
enum LineBreaker {
    // Parametri di TeX: \linepenalty, \hyphenpenalty, \doublehyphendemerits, \finalhyphendemerits, \adjdemerits.
    private static let linePenalty = 10.0
    private static let hyphenPenalty = 50.0
    private static let doubleHyphenDemerits = 10_000.0
    private static let finalHyphenDemerits = 5_000.0
    private static let adjacentFitnessDemerits = 10_000.0
    /// Quanto uno spazio tra parole può allargarsi e restringersi, in frazioni della sua larghezza. L'allargamento
    /// è più prudente del valore iniziale, senza spingere il motore a preferire righe eccessivamente compresse.
    private static let spaceStretch = 3.0 / 4
    private static let spaceShrink = 1.0 / 3
    /// L'ultima riga non si giustifica, ma non deve nemmeno restare troppo corta. Sotto il 35% della giustezza il
    /// costo cresce gradualmente; una sola parola ha una penalità ulteriore. Non vale per un paragrafo di una riga.
    private static let shortLastLineFill = 0.35
    private static let shortLastLineDemerits = 20_000.0
    private static let singleWordLastLineDemerits = 10_000.0
    /// Nel testo non giustificato una riga corta di questa frazione della giustezza vale quanto una riga
    /// giustificata con gli spazi allargati al limite.
    private static let raggedSlack = 0.12
    /// Quante righe di seguito possono finire con un trattino. È un vincolo rigido, non una penalità: in una colonna
    /// stretta il minimo matematico sarebbe una lunga scala di trattini, che in tipografia è un difetto riconosciuto.
    private static let maximumConsecutiveHyphens = 2
    /// Costo di una riga che non sta nella giustezza (una parola più lunga della riga): si accetta solo se inevitabile.
    private static let overfullDemerits = 1e10
    /// La microtipografia può allargare o stringere i glifi fino al limite scelto nel documento. Il valore entra nel
    /// calcolo degli a capo e nella composizione della riga, così modello e risultato visibile usano la stessa elasticità.
    private static func validExpansionLimit(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    /// La tensione di una riga: 0 è naturale, positiva allargata, negativa compressa. L'elasticità è la somma di
    /// quella degli spazi e della piccola espansione dei glifi; le righe forzate e quelle col trattino non si stringono.
    static func justificationRatio(natural: Double, spaces: Double, width: Double, justified: Bool, forced: Bool, hyphenated: Bool,
                                   expansionLimit: Double) -> Double {
        let limit = validExpansionLimit(expansionLimit)
        if forced, natural <= width { return 0 }
        if natural <= width {
            let glyphs = justified && !forced ? natural * limit : 0
            let stretch = justified ? spaces * spaceStretch + glyphs : width * raggedSlack
            return stretch > 0 ? (width - natural) / stretch : (width - natural < 0.01 ? 0 : 1e3)
        }
        let glyphs = justified && !forced && !hyphenated ? natural * limit : 0
        let shrink = justified && !hyphenated ? spaces * spaceShrink + glyphs : 0
        return shrink > 0 ? (width - natural) / shrink : -1e3
    }

    /// La frazione di espansione da applicare ai font della riga; il resto della giustificazione resta agli spazi.
    static func glyphExpansion(natural: Double, spaces: Double, width: Double, justified: Bool, forced: Bool, hyphenated: Bool,
                               expansionLimit: Double) -> Double {
        guard justified, !forced else { return 0 }
        let limit = validExpansionLimit(expansionLimit)
        let ratio = justificationRatio(natural: natural, spaces: spaces, width: width, justified: justified, forced: forced,
                                       hyphenated: hyphenated, expansionLimit: limit)
        return abs(ratio) <= 1 ? ratio * limit : 0
    }

    /// I bordi della riga su cui il primo e l'ultimo glifo possono sporgere nel margine.
    struct Protrusion: OptionSet, Hashable {
        let rawValue: Int
        static let left = Protrusion(rawValue: 1)
        static let right = Protrusion(rawValue: 2)
    }

    /// Un punto in cui il paragrafo può andare a capo.
    private struct Candidate {
        var index: Int
        /// Fine del testo visibile della riga: `index` meno gli spazi che lo precedono.
        var visibleEnd: Int
        var hyphen: String?
        var hyphenWidth = 0.0
        /// Di quanto l'ultimo glifo visibile della riga che finisce qui sporge nel margine destro.
        var rightProtrusion = 0.0
        /// Di quanto il primo glifo visibile della riga che comincia qui sporge nel margine sinistro.
        var leftProtrusion = 0.0
        var penalty = 0.0
        /// A capo obbligato: un a capo scritto dentro il paragrafo, oppure la sua fine.
        var isForced = false
    }

    /// Gli a capo ottimali del paragrafo, oppure `nil` se il paragrafo non si presta (testo da destra a sinistra,
    /// tabulazioni): in quel caso si procede riga per riga.
    static func optimalBreaks(
        paragraph: NSAttributedString, typesetter: CTTypesetter, firstWidth: CGFloat, restWidth: CGFloat,
        justified: Bool, expansionLimit: Double, hyphenates: Bool = true, hyphenationLanguage: String?, tracked: Bool = false, hangsHyphens: Bool = false,
        protrusion: Protrusion = []
    ) -> [LineBreak]? {
        let string = paragraph.string as NSString
        let length = string.length
        let glyphLimit = validExpansionLimit(expansionLimit)
        guard length > 0, string.range(of: "\t").location == NSNotFound else { return nil }

        // Le larghezze si leggono da un'unica riga non spezzata: l'ascissa di ogni carattere, con kerning,
        // legature e spaziatura già applicati. Vale solo se il testo scorre tutto da sinistra a destra.
        let unbroken = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: length))
        for run in CTLineGetGlyphRuns(unbroken) as? [CTRun] ?? [] where CTRunGetStatus(run).contains(.rightToLeft) { return nil }
        var offsets: [Int: Double] = [:]
        func x(_ index: Int) -> Double {
            if let known = offsets[index] { return known }
            let value = Double(CTLineGetOffsetForStringIndex(unbroken, index, nil))
            offsets[index] = value
            return value
        }

        let whitespace = CharacterSet.whitespacesAndNewlines
        func isSpace(_ index: Int) -> Bool { Unicode.Scalar(string.character(at: index)).map(whitespace.contains) ?? false }
        // Somma delle larghezze degli spazi che precedono ogni posizione: serve a sapere quanto una riga è elastica.
        var spaceWidthBefore = [Double](repeating: 0, count: length + 1)
        for index in 0..<length {
            spaceWidthBefore[index + 1] = spaceWidthBefore[index] + (isSpace(index) ? max(x(index + 1) - x(index), 0) : 0)
        }
        func visibleEnd(before index: Int) -> Int {
            var end = index
            while end > 0, isSpace(end - 1) { end -= 1 }
            return end
        }

        var candidates = candidates(in: string, paragraph: paragraph, hyphenates: hyphenates, defaultLanguage: hyphenationLanguage, tracked: tracked, hangsHyphens: hangsHyphens)
        for position in candidates.indices { candidates[position].visibleEnd = visibleEnd(before: candidates[position].index) }
        guard !candidates.isEmpty else { return nil }

        // La sporgenza nei margini, come la applica poi la composizione della riga: la riga può essere più larga
        // della giustezza di quanto i suoi due glifi estremi escono dai margini. Il trattino di sillabazione ha già
        // la sua nella larghezza del trattino.
        var startProtrusion = 0.0
        if !protrusion.isEmpty {
            let glyphs = edgeGlyphs(of: unbroken)
            var insets: [String: Double] = [:]
            func inset(at index: Int, right: Bool) -> Double {
                guard let entry = right ? glyphs.last[index] : glyphs.first[index] else { return 0 }
                let character = string.character(at: index)
                let key = "\(Unmanaged.passUnretained(entry.font).toOpaque())|\(entry.glyph)|\(right ? PageLayout.isHangingHyphen(character) ? 2 : 1 : 0)"
                if let known = insets[key] { return known }
                let value = Double(PageLayout.opticalInset(glyph: entry.glyph, font: entry.font, character: character, right: right))
                insets[key] = value
                return value
            }
            func firstVisible(from index: Int) -> Int? {
                var position = index
                while position < length, isSpace(position) { position += 1 }
                return position < length ? position : nil
            }
            for position in candidates.indices {
                let candidate = candidates[position]
                if protrusion.contains(.right), candidate.hyphen == nil, candidate.visibleEnd > 0 {
                    candidates[position].rightProtrusion = inset(at: candidate.visibleEnd - 1, right: true)
                }
                if protrusion.contains(.left), let first = firstVisible(from: candidate.index) {
                    candidates[position].leftProtrusion = inset(at: first, right: false)
                }
            }
            if protrusion.contains(.left), let first = firstVisible(from: 0) { startProtrusion = inset(at: first, right: false) }
        }

        // Programmazione dinamica: per ogni punto di a capo si tiene la soluzione di costo minimo che ci arriva,
        // distinguendo la classe di «tensione» della riga che vi finisce (stretta, giusta, larga, molto larga) e
        // quante righe sillabate di seguito la precedono.
        struct State {
            var demerits = Double.infinity
            var previous = -1  // punto di a capo precedente; −1 è l'inizio del paragrafo
            var previousSlot = 0
        }
        let runs = maximumConsecutiveHyphens + 1
        func slot(fitness: Int, run: Int) -> Int { fitness * runs + run }
        var states = [[State]](repeating: [State](repeating: State(), count: 4 * runs), count: candidates.count)
        let widest = Double(max(firstWidth, restWidth))

        for current in candidates.indices {
            let candidate = candidates[current]
            let isLastLine = current == candidates.count - 1
            var fallback: (demerits: Double, previous: Int, slot: Int)?
            var reached = false
            var previous = current - 1
            while previous >= -1 {
                let start = previous >= 0 ? candidates[previous].index : 0
                let width = Double(start == 0 ? firstWidth : restWidth)
                let natural = x(candidate.visibleEnd) - x(start) + candidate.hyphenWidth - candidate.rightProtrusion
                    - (previous >= 0 ? candidates[previous].leftProtrusion : startProtrusion)
                let spaces = spaceWidthBefore[candidate.visibleEnd] - spaceWidthBefore[min(start, candidate.visibleEnd)]
                // Una riga che finisce con un trattino di sillabazione non si comprime: restringerla avvicinerebbe
                // ancora di più il trattino alla lettera che lo precede.
                let glyphShrink = justified && !candidate.isForced && candidate.hyphen == nil ? natural * glyphLimit : 0
                // Risalendo, le righe si allungano soltanto: oltre questo punto nessuna può più stare.
                if natural - spaces * spaceShrink - glyphShrink > widest + 0.01, previous < current - 1 { break }

                // Costi delle soluzioni che arrivano al punto di partenza di questa riga.
                let origins: [(demerits: Double, slot: Int)] = previous >= 0
                    ? states[previous].enumerated().compactMap { $0.element.demerits.isFinite ? ($0.element.demerits, $0.offset) : nil }
                    : [(0, slot(fitness: 1, run: 0))]
                if !origins.isEmpty {
                    let ratio = justificationRatio(natural: natural, spaces: spaces, width: width, justified: justified,
                                                   forced: candidate.isForced, hyphenated: candidate.hyphen != nil, expansionLimit: glyphLimit)
                    let previousIsHyphen = previous >= 0 && candidates[previous].hyphen != nil
                    if ratio >= -1 {
                        reached = true
                        let badness = 100 * abs(ratio * ratio * ratio)
                        let fitness = ratio < -0.5 ? 0 : (ratio <= 0.5 ? 1 : (ratio <= 1 ? 2 : 3))
                        var cost = (linePenalty + badness) * (linePenalty + badness) + candidate.penalty * candidate.penalty
                        if previousIsHyphen && candidate.hyphen != nil { cost += doubleHyphenDemerits }
                        if previousIsHyphen && isLastLine { cost += finalHyphenDemerits }
                        if isLastLine, previous >= 0 {
                            let fill = min(max(natural / width, 0), 1)
                            let shortness = max(0, (shortLastLineFill - fill) / shortLastLineFill)
                            cost += shortLastLineDemerits * shortness * shortness
                            if spaces == 0 { cost += singleWordLastLineDemerits }
                        }
                        for origin in origins {
                            // Una riga sillabata allunga la serie di trattini; una non sillabata la azzera.
                            let run = candidate.hyphen != nil ? origin.slot % runs + 1 : 0
                            guard run <= maximumConsecutiveHyphens else { continue }
                            let total = origin.demerits + cost + (abs(fitness - origin.slot / runs) > 1 ? adjacentFitnessDemerits : 0)
                            let target = slot(fitness: fitness, run: run)
                            if total < states[current][target].demerits {
                                states[current][target] = State(demerits: total, previous: previous, previousSlot: origin.slot)
                            }
                        }
                    } else if previous == current - 1, candidate.hyphen == nil, let best = origins.min(by: { $0.demerits < $1.demerits }) {
                        // La riga più corta possibile che finisce qui è già troppo lunga: si tiene da parte, per i
                        // casi in cui non esiste alternativa (una parola più larga della giustezza).
                        fallback = (best.demerits + overfullDemerits, previous, best.slot)
                    }
                }
                // Una riga non può scavalcare un a capo obbligato.
                if previous >= 0, candidates[previous].isForced { break }
                previous -= 1
            }
            if !reached, let fallback {
                states[current][slot(fitness: 1, run: 0)] = State(demerits: fallback.demerits, previous: fallback.previous, previousSlot: fallback.slot)
            }
        }

        // Si risale dalla fine del paragrafo lungo la soluzione migliore.
        var position = candidates.count - 1
        guard var current = states[position].indices.min(by: { states[position][$0].demerits < states[position][$1].demerits }),
              states[position][current].demerits.isFinite else { return nil }
        var breaks: [LineBreak] = []
        while position >= 0 {
            breaks.append(LineBreak(end: candidates[position].index, hyphen: candidates[position].hyphen))
            let state = states[position][current]
            position = state.previous
            current = state.previousSlot
        }
        return breaks.reversed()
    }

    /// Per ogni indice del testo, il primo e l'ultimo glifo che gli corrispondono, con il loro font. In una legatura
    /// i caratteri dopo il primo non hanno glifo proprio: si usa quello della legatura.
    private static func edgeGlyphs(of line: CTLine) -> (first: [Int: (glyph: CGGlyph, font: CTFont)], last: [Int: (glyph: CGGlyph, font: CTFont)]) {
        var first: [Int: (glyph: CGGlyph, font: CTFont)] = [:], last: [Int: (glyph: CGGlyph, font: CTFont)] = [:]
        var previous: (glyph: CGGlyph, font: CTFont)?
        var previousIndex = -1
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0, let attribute = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { continue }
            let font = attribute as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            for position in 0..<count {
                let index = indices[position], entry = (glyph: glyphs[position], font: font)
                // I caratteri saltati da una legatura prendono il glifo che li contiene.
                if let previous, index > previousIndex + 1 {
                    for skipped in (previousIndex + 1)..<index where first[skipped] == nil {
                        first[skipped] = previous
                        last[skipped] = previous
                    }
                }
                if first[index] == nil { first[index] = entry }
                last[index] = entry
                previous = entry
                previousIndex = max(previousIndex, index)
            }
        }
        return (first, last)
    }

    /// I punti in cui il paragrafo può andare a capo: tra le parole (secondo le regole Unicode, come le applica
    /// il sistema), dentro le parole nei punti di sillabazione, agli a capo scritti e alla fine.
    private static func candidates(in string: NSString, paragraph: NSAttributedString, hyphenates: Bool, defaultLanguage: String?, tracked: Bool, hangsHyphens: Bool) -> [Candidate] {
        let length = string.length
        var byIndex: [Int: Candidate] = [:]
        let full = CFRange(location: 0, length: length)
        let letters = CharacterSet.letters

        let tokenizer = CFStringTokenizerCreate(nil, string, full, kCFStringTokenizerUnitLineBreak, nil)
        var hyphenWidths: [String: Double] = [:]
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let token = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let end = token.location + token.length
            guard end > 0, end <= length else { continue }
            let last = string.character(at: end - 1)
            var candidate = Candidate(index: end, visibleEnd: end)
            candidate.isForced = end == length || [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains(Int(last))
            // Un a capo dopo un trattino già scritto nel testo («ben-noto») costa quanto una sillabazione.
            if !candidate.isForced, [0x2D, 0x2010].contains(Int(last)), end < length,
               Unicode.Scalar(string.character(at: end)).map(letters.contains) ?? false {
                candidate.penalty = hyphenPenalty
            }
            byIndex[end] = candidate

            // L'ultima parola del paragrafo non si divide: lascerebbe in fondo una riga di due o tre lettere.
            guard hyphenates, !candidate.isForced || end < length else { continue }
            // La parola dentro il segmento: solo lettere, almeno cinque.
            var wordStart = token.location, wordEnd = end
            while wordStart < wordEnd, !(Unicode.Scalar(string.character(at: wordStart)).map(letters.contains) ?? false) { wordStart += 1 }
            while wordEnd > wordStart, !(Unicode.Scalar(string.character(at: wordEnd - 1)).map(letters.contains) ?? false) { wordEnd -= 1 }
            // Ogni parola si divide secondo la sua lingua: quella assegnata a quel testo, o quella del documento.
            guard wordEnd - wordStart >= 5, let language = Hyphenation.language(in: paragraph, at: wordStart, default: defaultLanguage) else { continue }
            for found in Hyphenation.points(in: string, word: NSRange(location: wordStart, length: wordEnd - wordStart), language: language) {
                let point = found.index, hyphen = found.hyphen
                guard byIndex[point] == nil else { continue }
                let attributes = paragraph.attributes(at: point - 1, effectiveRange: nil)
                // La larghezza del trattino dipende dal font del punto in cui cade e dalla lettera che lo precede.
                let before = string.substring(with: string.rangeOfComposedCharacterSequence(at: point - 1))
                let key = "\(before)\(hyphen)|\(Unmanaged.passUnretained(attributes[.init(kCTFontAttributeName as String)] as AnyObject).toOpaque())|\(attributes[.init(kCTKernAttributeName as String)] ?? 0)"
                let width = hyphenWidths[key] ?? {
                    let measured = PageLayout.hyphenAdvance(paragraph: paragraph, end: point, hyphen: hyphen, tracked: tracked, hanging: hangsHyphens)
                    hyphenWidths[key] = measured
                    return measured
                }()
                byIndex[point] = Candidate(index: point, visibleEnd: point, hyphen: hyphen, hyphenWidth: width, penalty: hyphenPenalty)
            }
        }
        if byIndex[length] == nil { byIndex[length] = Candidate(index: length, visibleEnd: length, isForced: true) }
        return byIndex.values.sorted { $0.index < $1.index }
    }
}
