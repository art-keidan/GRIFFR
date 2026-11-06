import AppKit
import CoreText

/// I caratteri che il font scelto non ha: Core Text li disegna con un font di ripiego, senza cambiare il testo. Qui si
/// riconoscono, per mostrarli a schermo e per dire nel menu della famiglia quale font si vede davvero.
///
/// Core Text, quando ricorre a un altro font, conserva gli altri attributi del tratto: la famiglia scelta viaggia quindi
/// nell'attributo `.chosenFontFamily`, che l'impaginazione aggiunge, e si confronta con il font del tratto disegnato.
public enum FontFallback {
    private static let delegateKey = NSAttributedString.Key(kCTRunDelegateAttributeName as String)

    /// Il testo con la famiglia scelta scritta su ogni tratto, accanto al font.
    static func annotated(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let value else { return }
            result.addAttribute(.chosenFontFamily, value: CTFontCopyFamilyName(value as! CTFont) as String, range: range)
        }
        return result
    }

    /// La famiglia del font di ripiego di un tratto composto, o `nil` se il tratto usa il font scelto. I tratti
    /// Graphite (segnaposto) e le immagini nella riga non contano.
    static func fallbackFamily(of run: CTRun) -> String? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let chosen = attributes[NSAttributedString.Key.chosenFontFamily] as? String,
              attributes[NSAttributedString.Key.graphite] == nil, attributes[delegateKey] == nil,
              let value = attributes[kCTFontAttributeName] else { return nil }
        let actual = CTFontCopyFamilyName(value as! CTFont) as String
        return actual == chosen ? nil : actual
    }

    /// Le famiglie di ripiego usate per disegnare il tratto di testo, nell'ordine in cui compaiono.
    public static func fallbackFamilies(in text: NSAttributedString, range: NSRange) -> [String] {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard range.length > 0 else { return [] }
        // Basta un tratto ragionevole: per selezioni lunghe si guardano i primi caratteri.
        let piece = annotated(text.attributedSubstring(from: NSRange(location: range.location, length: min(range.length, 2_000))))
        let line = CTLineCreateWithAttributedString(piece)
        var result: [String] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let span = CTRunGetStringRange(run)
            // Il carattere che tiene il posto di un campo non si disegna: sulla pagina c'è il testo calcolato, con il font
            // del tratto. Che il font non lo abbia non è una sostituzione.
            var string = ""
            piece.enumerateAttribute(.field, in: NSRange(location: span.location, length: span.length)) { value, range, _ in
                if value == nil { string += (piece.string as NSString).substring(with: range) }
            }
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let family = fallbackFamily(of: run), !result.contains(family) else { continue }
            result.append(family)
        }
        return result
    }
}

extension LaidOutPage {
    /// Il testo calcolato di ogni campo sulla pagina: la posizione del campo nel documento e il rettangolo che occupa
    /// nella riga, nelle coordinate della pagina (origine in basso a sinistra). Per la cornice che si vede solo a schermo.
    public var fieldRects: [(location: Int, rect: CGRect)] {
        var result: [(location: Int, rect: CGRect)] = []
        for placed in lines {
            var byField: [Int: CGRect] = [:]
            var order: [Int] = []
            for run in CTLineGetGlyphRuns(placed.line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let location = (attributes[NSAttributedString.Key.composedField] as? NSNumber)?.intValue,
                      CTRunGetGlyphCount(run) > 0 else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
                let rect = CGRect(x: placed.origin.x + position.x, y: placed.origin.y - placed.descent, width: width, height: placed.ascent + placed.descent)
                if let known = byField[location] { byField[location] = known.union(rect) } else { byField[location] = rect; order.append(location) }
            }
            for location in order { result.append((location, byField[location]!)) }
        }
        return result
    }

    /// I rettangoli dei caratteri disegnati con un font di ripiego, nelle coordinate della pagina (origine in basso a
    /// sinistra): per segnalarli a schermo.
    public var fallbackRects: [CGRect] {
        var rects: [CGRect] = []
        for placed in lines {
            for run in CTLineGetGlyphRuns(placed.line) as! [CTRun] where FontFallback.fallbackFamily(of: run) != nil {
                guard CTRunGetGlyphCount(run) > 0 else { continue }
                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), nil, nil, nil))
                rects.append(CGRect(x: placed.origin.x + position.x, y: placed.origin.y - placed.descent,
                                    width: width, height: placed.ascent + placed.descent))
            }
        }
        return rects
    }
}

extension NSAttributedString.Key {
    /// La famiglia del font scelto per il tratto, aggiunta solo durante l'impaginazione (vedi `FontFallback`).
    public static let chosenFontFamily = NSAttributedString.Key("WordProcessorChosenFontFamily")
    /// Nel testo composto, sul testo calcolato di un campo: la posizione del campo nel documento.
    public static let composedField = NSAttributedString.Key("WordProcessorComposedField")
}
