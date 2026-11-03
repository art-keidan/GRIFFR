import AppKit
import CoreText

/// Il disegno dei filetti (sottolineato, barrato, filetti propri). Core Text non li disegna: si tracciano qui, dopo
/// la riga, nello stesso modo a schermo e nel PDF.
enum LineDecorations {
    /// Disegna i filetti di una riga già collocata. I tratti vicini con lo stesso filetto e lo stesso font formano
    /// un solo segmento, così un tratteggio non ricomincia a ogni cambio d'attributo.
    static func draw(line: CTLine, at origin: CGPoint, in context: CGContext) {
        struct Segment {
            var decoration: LineDecoration
            var font: CTFont
            var color: CGColor
            var start: CGFloat
            var end: CGFloat
            var baseline: CGFloat
            var gaps: [ClosedRange<CGFloat>]
        }
        var segments: [Segment] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let encoded = attributes[NSAttributedString.Key.lineDecorations] as? String,
                  let decorations = LineDecoration.decode(encoded), !decorations.isEmpty else { continue }
            let font = attributes[kCTFontAttributeName] as! CTFont
            let textColor = textColor(of: attributes)
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: count), nil, nil, nil))
            let start = origin.x + positions[0].x
            // Un tratto alzato o abbassato (apice, pedice) ha i filetti alla linea di base della riga.
            let shift = (attributes[kCTBaselineOffsetAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            for decoration in decorations {
                let color = decoration.color.flatMap { TextStyling.color(hex: $0)?.cgColor } ?? textColor
                let gaps = decoration.position == .under && decoration.skipsDescenders
                    ? descenderGaps(run: run, font: font, positions: positions, originX: origin.x, decoration: decoration, shift: shift) : []
                if var last = segments.last, last.decoration == decoration, abs(last.end - start) < 0.5, CFEqual(last.font, font), last.color == color {
                    last.end = start + width
                    last.gaps += gaps
                    segments[segments.count - 1] = last
                } else {
                    segments.append(Segment(decoration: decoration, font: font, color: color, start: start, end: start + width,
                                            baseline: origin.y, gaps: gaps))
                }
            }
        }
        for segment in segments { stroke(segment.decoration, font: segment.font, color: segment.color, from: segment.start, to: segment.end,
                                         baseline: segment.baseline, gaps: segment.gaps, in: context) }
    }

    private static func textColor(of attributes: NSDictionary) -> CGColor {
        // Il testo Graphite è trasparente per Core Text: il suo colore sta a parte.
        if let value = attributes[NSAttributedString.Key.graphiteColor], CFGetTypeID(value as CFTypeRef) == CGColor.typeID { return value as! CGColor }
        if let value = attributes[kCTForegroundColorAttributeName], CFGetTypeID(value as CFTypeRef) == CGColor.typeID { return value as! CGColor }
        if let color = attributes[NSAttributedString.Key.foregroundColor] as? NSColor { return color.cgColor }
        return CGColor(gray: 0, alpha: 1)
    }

    static func thickness(of decoration: LineDecoration, font: CTFont) -> CGFloat {
        decoration.thickness.map { CGFloat($0) } ?? max(CTFontGetUnderlineThickness(font), CTFontGetSize(font) / 20)
    }

    /// L'altezza del filetto rispetto alla linea di base: sotto alla posizione che il font dichiara per la
    /// sottolineatura, in mezzo a metà dell'altezza della x, sopra poco più su delle maiuscole.
    static func height(of decoration: LineDecoration, font: CTFont) -> CGFloat {
        let thickness = thickness(of: decoration, font: font)
        return switch decoration.position {
        case .under: CTFontGetUnderlinePosition(font) - CGFloat(decoration.offset)
        case .through: CTFontGetXHeight(font) * 0.55 + CGFloat(decoration.offset)
        case .over: CTFontGetCapHeight(font) + 2 * thickness + CGFloat(decoration.offset)
        }
    }

    /// Dove il filetto sotto si interrompe: la parte delle discendenti che attraversa la fascia del filetto (la forma
    /// vera del glifo, non il suo rettangolo), con un po' d'aria ai lati.
    private static func descenderGaps(run: CTRun, font: CTFont, positions: [CGPoint], originX: CGFloat, decoration: LineDecoration,
                                      shift: CGFloat) -> [ClosedRange<CGFloat>] {
        let count = positions.count
        var glyphs = [CGGlyph](repeating: 0, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        var boxes = [CGRect](repeating: .zero, count: count)
        CTFontGetBoundingRectsForGlyphs(font, .default, glyphs, &boxes, count)
        let thickness = thickness(of: decoration, font: font)
        let center = height(of: decoration, font: font) - shift
        // La fascia: lo spessore del filetto più un respiro sopra e sotto.
        let band = CGRect(x: -10_000, y: center - thickness * 1.5, width: 20_000, height: thickness * 3)
        var gaps: [ClosedRange<CGFloat>] = []
        for index in 0..<count where boxes[index].height > 0 && boxes[index].minY < band.maxY {
            guard let path = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            let crossing = path.intersection(CGPath(rect: band, transform: nil))
            guard !crossing.isEmpty else { continue }
            let box = crossing.boundingBoxOfPath
            let air = thickness * 1.2
            gaps.append((originX + positions[index].x + box.minX - air)...(originX + positions[index].x + box.maxX + air))
        }
        return gaps
    }

    /// Le parti del segmento da tracciare, tolte le interruzioni.
    static func pieces(from start: CGFloat, to end: CGFloat, gaps: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var result: [ClosedRange<CGFloat>] = []
        var cursor = start
        for gap in gaps.sorted(by: { $0.lowerBound < $1.lowerBound }) where gap.upperBound > cursor && gap.lowerBound < end {
            if gap.lowerBound > cursor { result.append(cursor...gap.lowerBound) }
            cursor = max(cursor, gap.upperBound)
        }
        if cursor < end { result.append(cursor...end) }
        return result
    }

    private static func stroke(_ decoration: LineDecoration, font: CTFont, color: CGColor, from start: CGFloat, to end: CGFloat, baseline: CGFloat,
                               gaps: [ClosedRange<CGFloat>], in context: CGContext) {
        let thickness = thickness(of: decoration, font: font)
        let y = baseline + height(of: decoration, font: font)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setLineWidth(thickness)
        switch decoration.pattern {
        case .dotted:
            context.setLineCap(.round)
            context.setLineDash(phase: 0, lengths: [0.01, thickness * 2.5])
        case .dashed:
            context.setLineCap(.butt)
            context.setLineDash(phase: 0, lengths: [thickness * 4, thickness * 2.5])
        default:
            context.setLineCap(.butt)
        }
        for piece in pieces(from: start, to: end, gaps: gaps) {
            switch decoration.pattern {
            case .double:
                // Due righe sottili, con lo spazio di una tra loro; la seconda si allontana dal testo.
                let away: CGFloat = decoration.position == .under ? -1 : 1
                context.setLineWidth(thickness * 0.75)
                for offset in [0, away * thickness * 2] {
                    context.move(to: CGPoint(x: piece.lowerBound, y: y + offset))
                    context.addLine(to: CGPoint(x: piece.upperBound, y: y + offset))
                }
            case .wavy:
                let amplitude = thickness * 1.2
                let period = max(thickness * 6, 3)
                var x = piece.lowerBound
                var up: CGFloat = 1
                context.move(to: CGPoint(x: x, y: y))
                while x < piece.upperBound {
                    let step = min(period / 2, piece.upperBound - x)
                    context.addQuadCurve(to: CGPoint(x: x + step, y: y), control: CGPoint(x: x + step / 2, y: y + up * amplitude * 2))
                    x += step
                    up = -up
                }
            default:
                context.move(to: CGPoint(x: piece.lowerBound, y: y))
                context.addLine(to: CGPoint(x: piece.upperBound, y: y))
            }
        }
        context.strokePath()
    }
}
