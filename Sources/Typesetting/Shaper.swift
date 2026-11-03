import CoreText
import Foundation

/// Un glifo prodotto da Core Text, con il font che lo ha effettivamente fornito.
public struct ShapedGlyph: Hashable, Sendable {
    public var id: CGGlyph
    public var fontName: String
    /// Indice UTF-16 del primo carattere a cui il glifo corrisponde.
    public var stringIndex: Int
    public var advance: CGFloat
}

public enum Shaper {
    public static func glyphs(in line: CTLine) -> [ShapedGlyph] {
        var result: [ShapedGlyph] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            let range = CFRange(location: 0, length: count)
            var ids = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetGlyphs(run, range, &ids)
            CTRunGetStringIndices(run, range, &indices)
            CTRunGetAdvances(run, range, &advances)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let fontName = (attributes[kCTFontAttributeName] as! CTFont).postScriptName
            for index in 0..<count {
                result.append(ShapedGlyph(id: ids[index], fontName: fontName, stringIndex: indices[index], advance: advances[index].width))
            }
        }
        return result
    }

    public static func glyphs(for attributedString: NSAttributedString) -> [ShapedGlyph] {
        glyphs(in: CTLineCreateWithAttributedString(attributedString))
    }

    public static func glyphs(for text: String, font: CTFont) -> [ShapedGlyph] {
        glyphs(for: NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    }

    /// Gli ID di glifo di un testo composto con un solo font: la misura usata dai test di regressione.
    public static func glyphIDs(for text: String, font: CTFont) -> [Int] {
        glyphs(for: text, font: font).map { Int($0.id) }
    }
}
