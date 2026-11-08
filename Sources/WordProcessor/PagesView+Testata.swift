import AppKit
import Typesetting

/// Che cosa si prende di una parte della testata.
enum HeadingGrip: Hashable {
    /// L'altezza minima della fascia di un'etichetta, di un numero o di un risultato (il testo poggia sul fondo: si tira
    /// il bordo in alto).
    case height
    /// L'altezza di uno spazio (si tira il bordo in basso).
    case space
    /// La lunghezza e lo spessore di un filetto.
    case ruleLength, ruleThickness
    /// La distanza fra il numero accanto al titolo e il titolo.
    case gap

    var title: String {
        switch self {
        case .height: "Minimum height"
        case .space: "Space"
        case .ruleLength: "Rule length"
        case .ruleThickness: "Rule thickness"
        case .gap: "Distance from the title"
        }
    }

    var isHorizontal: Bool { self == .ruleLength || self == .gap }
}

struct HeadingGripID: Hashable {
    var part: Int
    var grip: HeadingGrip
}

extension HeadingPart {
    /// Le maniglie che la parte ha sulla pagina.
    var grips: [HeadingGrip] {
        switch self {
        case .label, .number, .result: [.height]
        case .space: [.space]
        case .rule: [.ruleLength, .ruleThickness]
        case .numberBeside: [.gap]
        case .title: []
        }
    }

    /// Il valore che una maniglia muove, in punti; `shown` è la parte com'è posata (per i valori che mancano).
    func value(of grip: HeadingGrip, shown: CGRect) -> CGFloat {
        switch (self, grip) {
        case (.label(_, _, _, let height), .height), (.number(_, _, _, let height), .height), (.result(_, _, _, _, let height), .height):
            CGFloat(height ?? Double(shown.height))
        case (.space(let length), .space): CGFloat(length)
        case (.rule(_, let length, _), .ruleLength): CGFloat(length ?? Double(shown.width))
        case (.rule(let thickness, _, _), .ruleThickness): CGFloat(thickness)
        case (.numberBeside(_, _, _, let gap), .gap): CGFloat(gap)
        default: 0
        }
    }

    /// La parte con la maniglia a `value` punti.
    func setting(_ grip: HeadingGrip, to value: CGFloat) -> HeadingPart {
        let number = Double(value)
        switch (self, grip) {
        case (.label(let text, let style, let alignment, _), .height): return .label(text: text, style: style, alignment: alignment, minHeight: number)
        case (.number(let prefix, let style, let alignment, _), .height): return .number(prefix: prefix, style: style, alignment: alignment, minHeight: number)
        case (.result(let formula, let prefix, let style, let alignment, _), .height):
            return .result(formula: formula, prefix: prefix, style: style, alignment: alignment, minHeight: number)
        case (.space, .space): return .space(number)
        case (.rule(let thickness, _, let alignment), .ruleLength): return .rule(thickness: thickness, length: number, alignment: alignment)
        case (.rule(_, let length, let alignment), .ruleThickness): return .rule(thickness: max(number, 0.1), length: length, alignment: alignment)
        case (.numberBeside(let prefix, let style, let side, _), .gap): return .numberBeside(prefix: prefix, style: style, side: side, gap: number)
        default: return self
        }
    }

    /// Il valore dopo uno spostamento del mouse (in punti di pagina, in basso e a destra positivi).
    func value(of grip: HeadingGrip, from start: CGFloat, moved delta: CGSize, onRightSide: Bool) -> CGFloat {
        switch grip {
        case .height: max(start - delta.height, 0)
        case .space: max(start + delta.height, 0)
        case .ruleLength: max(start + (onRightSide ? -delta.width : delta.width), 4)
        case .ruleThickness: max(start + delta.height / 4, 0.1)
        case .gap: max(start + (onRightSide ? -delta.width : delta.width), 0)
        }
    }
}

extension PagesView {
    /// Le parti della testata del capoverso progettato, come sono posate: la pagina e il rettangolo nella vista.
    func designHeadingParts() -> [(part: Int, page: Int, rect: NSRect)] {
        guard let design, design.heading != nil, let layout else { return [] }
        var result: [(Int, Int, NSRect)] = []
        for (index, page) in layout.pages.enumerated() {
            for placed in page.headingParts where placed.paragraphLocation == design.paragraphLocation {
                result.append((placed.part, index, viewRect(for: placed.rect, onPage: index)))
            }
        }
        return result
    }

    /// Vero se la parte sta sul lato destro (un filetto allineato a destra, un numero a destra del titolo): le maniglie
    /// orizzontali vanno allora nel verso opposto.
    private func onRightSide(_ part: HeadingPart, rect: NSRect, page: Int) -> Bool {
        let leftPage = (layout?.setup(forPage: page).facing ?? false) && page % 2 == 1
        switch part {
        case .rule(_, _, let alignment): return alignment.resolved(onLeftPage: leftPage) == .right
        case .numberBeside(_, _, let side, _): return side.resolved(onLeftPage: leftPage) == .right
        default: return false
        }
    }

    /// Le maniglie delle parti della testata, in coordinate della vista.
    func headingGripRects() -> [HeadingGripID: NSRect] {
        guard let design, let heading = design.heading else { return [:] }
        var result: [HeadingGripID: NSRect] = [:]
        // Solo la parte scelta ha le sue maniglie: le fasce della testata sono sottili, e tutte insieme si ammucchierebbero.
        for placed in designHeadingParts() where heading.parts.indices.contains(placed.part) && placed.part == design.selectedHeadingPart {
            let part = heading.parts[placed.part]
            let rect = placed.rect
            let right = onRightSide(part, rect: rect, page: placed.page)
            for grip in part.grips {
                let id = HeadingGripID(part: placed.part, grip: grip)
                switch grip {
                case .height: result[id] = NSRect(x: rect.maxX + 28, y: rect.minY - 3, width: 18, height: 6)
                case .space: result[id] = NSRect(x: rect.maxX + 28, y: rect.maxY - 3, width: 18, height: 6)
                case .ruleLength: result[id] = NSRect(x: (right ? rect.minX : rect.maxX) - 3, y: rect.midY - 8, width: 6, height: 16)
                case .ruleThickness: result[id] = NSRect(x: rect.midX - 9, y: rect.maxY + 2, width: 18, height: 5)
                case .gap:
                    let gap = CGFloat(part.value(of: .gap, shown: .zero)) * scale
                    let x = right ? rect.minX - gap : rect.maxX + gap
                    result[id] = NSRect(x: x - 3, y: rect.midY - 8, width: 6, height: 16)
                }
            }
        }
        return result
    }

    func headingGrip(at point: NSPoint) -> HeadingGripID? {
        headingGripRects().first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }?.key
    }

    /// La parte della testata sotto il punto (per sceglierla con un clic).
    func headingPart(at point: NSPoint) -> Int? {
        designHeadingParts().first { $0.rect.insetBy(dx: 0, dy: -2).contains(point) }?.part
    }

    // MARK: Gesti (chiamati dai gesti della progettazione)

    func headingMouseDown(at point: NSPoint) -> Bool {
        guard let design else { return false }
        if let id = headingGrip(at: point), design.headingEditable {
            headingDrag = (id, point)
            onHeadingDrag?(id, .zero, .began)
            return true
        }
        if let part = headingPart(at: point) {
            onHeadingSelect?(part)
            return true
        }
        return false
    }

    func headingMouseDragged(to point: NSPoint) -> Bool {
        guard let drag = headingDrag else { return false }
        onHeadingDrag?(drag.id, CGSize(width: (point.x - drag.start.x) / scale, height: (point.y - drag.start.y) / scale), .changed)
        return true
    }

    func headingMouseUp(at point: NSPoint) -> Bool {
        guard let drag = headingDrag else { return false }
        headingDrag = nil
        onHeadingDrag?(drag.id, CGSize(width: (point.x - drag.start.x) / scale, height: (point.y - drag.start.y) / scale), .ended)
        return true
    }

    /// Vero se il punto è su una maniglia della testata (e mette il cursore giusto).
    func headingMouseMoved(at point: NSPoint) -> Bool {
        hoveredHeadingGrip = headingGrip(at: point)
        guard let id = hoveredHeadingGrip else { return false }
        (id.grip.isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        return true
    }

    /// Le cornici delle parti della testata sulla pagina, la parte scelta, le maniglie e il valore.
    func drawHeading(onPage index: Int, in context: CGContext) {
        guard let design, let heading = design.heading else { return }
        let parts = designHeadingParts().filter { $0.page == index }
        guard !parts.isEmpty else { return }
        let color = design.headingEditable ? Theme.accent : NSColor.systemGray
        for placed in parts where heading.parts.indices.contains(placed.part) {
            let selected = design.selectedHeadingPart == placed.part
            context.saveGState()
            context.setStrokeColor(color.withAlphaComponent(selected ? 0.9 : 0.45).cgColor)
            context.setLineWidth(selected ? 1.5 : 0.75)
            if !selected { context.setLineDash(phase: 0, lengths: [3, 3]) }
            context.stroke(placed.rect.insetBy(dx: -2, dy: -1))
            context.restoreGState()
            if selected {
                let name = NSAttributedString(string: heading.parts[placed.part].title,
                                              attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: color])
                name.draw(at: NSPoint(x: placed.rect.minX - name.size().width - 8, y: placed.rect.midY - name.size().height / 2))
            }
        }
        let pageRects = Set(parts.map(\.part))
        for (id, rect) in headingGripRects() where pageRects.contains(id.part) {
            let lit = design.activeHeadingGrip == id || hoveredHeadingGrip == id
            context.saveGState()
            context.setFillColor((lit ? Theme.activeTop : color).cgColor)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: min(rect.width, rect.height) / 2, cornerHeight: min(rect.width, rect.height) / 2, transform: nil))
            context.fillPath()
            context.restoreGState()
            if lit, heading.parts.indices.contains(id.part), let shown = parts.first(where: { $0.part == id.part }) {
                let points = heading.parts[id.part].value(of: id.grip, shown: NSRect(x: 0, y: 0, width: shown.rect.width / scale, height: shown.rect.height / scale))
                let millimetres = PageSetup.millimetres(fromPoints: points).formatted(.number.precision(.fractionLength(0...1)))
                let text = design.headingEditable ? "\(id.grip.title)  \(millimetres) mm" : "The heading belongs to the style: turn the eye on to change it"
                let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.accentInk])
                let size = label.size()
                var box = NSRect(x: rect.maxX + 6, y: rect.midY - size.height / 2 - 3, width: size.width + 12, height: size.height + 6)
                if box.maxX > visibleRect.maxX - 4 { box.origin.x = rect.minX - box.width - 6 }
                color.setFill()
                NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
                label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
            }
        }
    }
}
