import AppKit
import Typesetting

/// Le misure del capoverso che si trascinano sulla pagina.
enum DesignHandle: CaseIterable, Hashable {
    case leftIndent, firstLineIndent, rightIndent, spaceBefore, spaceAfter, lineSpacing

    /// La proprietà dello stile che la maniglia cambia.
    var property: InspectorProperty {
        switch self {
        case .leftIndent: .leftIndent
        case .firstLineIndent: .firstLineIndent
        case .rightIndent: .rightIndent
        case .spaceBefore: .spaceBefore
        case .spaceAfter: .spaceAfter
        case .lineSpacing: .lineSpacing
        }
    }

    var title: String {
        switch self {
        case .leftIndent: "Left indent"
        case .firstLineIndent: "First line"
        case .rightIndent: "Right indent"
        case .spaceBefore: "Space before"
        case .spaceAfter: "Space after"
        case .lineSpacing: "Between lines"
        }
    }

    /// Vero per le maniglie che si spostano in orizzontale.
    var isHorizontal: Bool { self == .leftIndent || self == .firstLineIndent || self == .rightIndent }

    /// Il valore dopo uno spostamento (in punti di pagina, in basso è positivo) a partire da `start`.
    func value(from start: CGFloat, moved delta: CGSize) -> CGFloat {
        switch self {
        case .leftIndent, .firstLineIndent: start + delta.width
        case .rightIndent: start - delta.width
        case .spaceBefore: start - delta.height
        case .spaceAfter, .lineSpacing: start + delta.height
        }
    }

    /// Il minimo che la misura può avere: solo la prima riga può sporgere a sinistra.
    var minimum: CGFloat { self == .firstLineIndent ? -.greatestFiniteMagnitude : 0 }
}

enum DesignDragPhase { case began, changed, ended }

/// Un lato dello specchio di stampa, come si vede sulla pagina.
enum MarginSide: CaseIterable, Hashable {
    case top, bottom, left, right

    var isHorizontal: Bool { self == .left || self == .right }

    var title: String {
        switch self {
        case .top: "Top margin"
        case .bottom: "Bottom margin"
        case .left: "Left margin"
        case .right: "Right margin"
        }
    }

    /// Il campo del formato che il lato cambia: con le pagine affacciate, sulle pagine pari i margini interno ed
    /// esterno si scambiano di posto.
    func field(onPage page: Int, facing: Bool) -> WritableKeyPath<PageSetup, CGFloat> {
        let swapped = facing && page % 2 == 1
        switch self {
        case .top: return \.top
        case .bottom: return \.bottom
        case .left: return swapped ? \.right : \.left
        case .right: return swapped ? \.left : \.right
        }
    }

    /// Il margine dopo uno spostamento (in punti di pagina, in basso positivo).
    func value(from start: CGFloat, moved delta: CGSize) -> CGFloat {
        switch self {
        case .top: start + delta.height
        case .bottom: start - delta.height
        case .left: start + delta.width
        case .right: start - delta.width
        }
    }
}

/// Da che parte un capoverso tiene con sé le righe di un vicino.
enum KeepSide: Hashable {
    case next, previous

    func title(_ count: Int) -> String {
        if count == 0 { return self == .next ? "Not kept with the next" : "Not kept with the previous" }
        let lines = count == 1 ? "1 line" : "\(count) lines"
        return self == .next ? "Keep with \(lines) of the next" : "Keep with \(lines) of the previous"
    }
}

/// Ciò che la pagina deve sapere per disegnare la progettazione: quale capoverso, le sue misure, quali sono bloccate.
struct ParagraphDesignOverlay: Equatable {
    /// La posizione d'inizio del capoverso, come la portano le righe composte.
    var paragraphLocation: Int
    var values: [DesignHandle: CGFloat]
    /// Le misure calcolate da una formula dello stile: non si trascinano.
    var locked: Set<DesignHandle> = []
    /// La maniglia trascinata ora.
    var active: DesignHandle?
    /// Con quante righe del seguente e del precedente il capoverso resta nella stessa pagina (0 = nessuna).
    var keep: [KeepSide: Int] = [:]
    var keepLocked: Set<KeepSide> = []
    var activeKeep: KeepSide?
    /// La testata dello stile del capoverso (nella bozza), la parte scelta, se si può cambiare (solo nello stile, dal vivo).
    var heading: HeadingComposition?
    var selectedHeadingPart: Int?
    var headingEditable = false
    var activeHeadingGrip: HeadingGripID?
    /// I filetti liberi del capoverso (nella bozza), quello scelto e la maniglia trascinata.
    var rules: [ParagraphRule] = []
    var selectedRule: Int?
    var activeRuleGrip: RuleGripID?

    func value(_ handle: DesignHandle) -> CGFloat { values[handle] ?? 0 }
}

/// La parte di un capoverso che sta su una pagina, in coordinate della vista.
struct DesignFragment {
    let page: Int
    /// Le righe, ciascuna larga quanto il suo testo, e la loro linea di base.
    let lines: [NSRect]
    let baselines: [CGFloat]
    /// Il numero, nel capoverso, della prima riga di questa parte.
    let firstLineNumber: Int
    /// La colonna (o la cella) in cui il capoverso sta.
    let columnMinX: CGFloat
    let columnMaxX: CGFloat
    /// Vero se il capoverso comincia (o finisce) su questa pagina.
    let isFirst: Bool
    let isLast: Bool

    var top: CGFloat { lines.map(\.minY).min() ?? 0 }
    var bottom: CGFloat { lines.map(\.maxY).max() ?? 0 }
    /// Il riquadro del capoverso: tutta la colonna, dall'alto della prima riga al basso dell'ultima.
    var area: NSRect { NSRect(x: columnMinX, y: top, width: columnMaxX - columnMinX, height: bottom - top) }
}

extension PagesView {
    /// Le parti del capoverso progettato, pagina per pagina, nella composizione mostrata.
    func designFragments() -> [DesignFragment] {
        guard let design, let layout else { return [] }
        var fragments: [DesignFragment] = []
        var seenFirst = false
        var lineCount = 0
        for (index, page) in layout.pages.enumerated() {
            let lines = page.lines.filter { $0.paragraphLocation == design.paragraphLocation }
            guard !lines.isEmpty else { continue }
            let setup = layout.setup(forPage: index)
            let column = lines.first?.cell ?? setup.textRect(forPage: index)
            let rects = lines.map { line in
                viewRect(for: CGRect(x: line.origin.x, y: line.origin.y - line.descent, width: max(line.width, 1), height: line.ascent + line.descent), onPage: index)
            }
            let columnRect = viewRect(for: CGRect(x: column.minX, y: column.minY, width: column.width, height: max(column.height, 1)), onPage: index)
            let baselines = lines.map { viewRect(for: CGRect(x: $0.origin.x, y: $0.origin.y, width: 1, height: 0), onPage: index).minY }
            fragments.append(DesignFragment(page: index, lines: rects, baselines: baselines, firstLineNumber: lineCount,
                                            columnMinX: columnRect.minX, columnMaxX: columnRect.maxX, isFirst: !seenFirst, isLast: false))
            seenFirst = true
            lineCount += lines.count
        }
        if let last = fragments.popLast() {
            fragments.append(DesignFragment(page: last.page, lines: last.lines, baselines: last.baselines, firstLineNumber: last.firstLineNumber,
                                            columnMinX: last.columnMinX, columnMaxX: last.columnMaxX, isFirst: last.isFirst, isLast: true))
        }
        return fragments
    }

    /// Dove stanno le maniglie, in coordinate della vista: ciascuna una volta sola, sulla parte giusta del capoverso.
    func designHandleRects() -> [DesignHandle: NSRect] {
        guard let design else { return [:] }
        let fragments = designFragments()
        guard let first = fragments.first, let last = fragments.last else { return [:] }
        var result: [DesignHandle: NSRect] = [:]
        let left = first.columnMinX + design.value(.leftIndent) * scale
        let firstLine = left + design.value(.firstLineIndent) * scale
        let right = first.columnMaxX - design.value(.rightIndent) * scale
        let middle = first.lines.count > 1 ? (first.lines[1].minY + first.area.maxY) / 2 : first.area.midY
        let barHeight = min(max(first.area.height - 4, 12), 26)
        result[.leftIndent] = NSRect(x: left - 4, y: middle - barHeight / 2, width: 8, height: barHeight)
        result[.rightIndent] = NSRect(x: right - 4, y: first.area.midY - barHeight / 2, width: 8, height: barHeight)
        result[.firstLineIndent] = NSRect(x: firstLine - 6, y: first.top - 11, width: 12, height: 10)
        // Gli spazi si prendono nel margine sinistro, sul bordo della loro fascia: così non coprono il testo.
        let beforeTop = first.top - design.value(.spaceBefore) * scale
        result[.spaceBefore] = NSRect(x: first.columnMinX - 30, y: beforeTop - 3, width: 22, height: 6)
        let afterBottom = last.bottom + design.value(.spaceAfter) * scale
        result[.spaceAfter] = NSRect(x: last.columnMinX - 30, y: afterBottom - 3, width: 22, height: 6)
        // L'interlinea si prende per le linee di base, tracciate sotto le lettere: qui quella della seconda riga.
        if first.lines.count > 1 {
            result[.lineSpacing] = NSRect(x: left, y: first.baselines[1] - 3, width: max(right - left, 8), height: 6)
        }
        return result
    }

    /// La linea di base sotto un punto (dalla seconda riga in giù): il suo numero nel capoverso.
    func designBaseline(at point: NSPoint) -> Int? {
        guard let design else { return nil }
        for fragment in designFragments() {
            let left = fragment.columnMinX + design.value(.leftIndent) * scale
            let right = fragment.columnMaxX - design.value(.rightIndent) * scale
            guard point.x >= left - 4, point.x <= right + 4 else { continue }
            for (offset, y) in fragment.baselines.enumerated() where abs(point.y - y) <= 3 {
                let number = fragment.firstLineNumber + offset
                if number >= 1 { return number }
            }
        }
        return nil
    }

    // MARK: Tenere con le righe dei vicini

    /// Le righe del capoverso che segue (o precede) quello progettato, dalla più vicina, in coordinate della vista.
    func neighbourLines(_ side: KeepSide) -> [NSRect] {
        guard let design, let layout else { return [] }
        var all: [(page: Int, line: PlacedLine)] = []
        for (index, page) in layout.pages.enumerated() { for line in page.lines where !line.isNote { all.append((index, line)) } }
        guard let first = all.firstIndex(where: { $0.line.paragraphLocation == design.paragraphLocation }),
              let last = all.lastIndex(where: { $0.line.paragraphLocation == design.paragraphLocation }) else { return [] }
        var picked: [(page: Int, line: PlacedLine)] = []
        switch side {
        case .next:
            guard last + 1 < all.count else { return [] }
            let location = all[last + 1].line.paragraphLocation
            for item in all[(last + 1)...] { guard item.line.paragraphLocation == location, picked.count < LineKeeping.lineRange.upperBound else { break }; picked.append(item) }
        case .previous:
            guard first > 0 else { return [] }
            let location = all[first - 1].line.paragraphLocation
            for item in all[..<first].reversed() { guard item.line.paragraphLocation == location, picked.count < LineKeeping.previousRange.upperBound else { break }; picked.append(item) }
        }
        return picked.map { item in
            viewRect(for: CGRect(x: item.line.origin.x, y: item.line.origin.y - item.line.descent, width: max(item.line.width, 1),
                                 height: item.line.ascent + item.line.descent), onPage: item.page)
        }
    }

    /// La maniglia della tenuta: nel margine destro, al bordo dell'ultima riga tenuta (o del capoverso, se nessuna).
    func keepHandleRect(_ side: KeepSide) -> NSRect? {
        guard let design, let first = designFragments().first, let last = designFragments().last else { return nil }
        let neighbours = neighbourLines(side)
        guard !neighbours.isEmpty else { return nil }
        let count = min(design.keep[side] ?? 0, neighbours.count)
        let x = (side == .next ? last.columnMaxX : first.columnMaxX) + 14
        let y: CGFloat = switch side {
        case .next: count > 0 ? neighbours[count - 1].maxY : last.bottom
        case .previous: count > 0 ? neighbours[count - 1].minY : first.top
        }
        return NSRect(x: x - 6, y: y - 6, width: 12, height: 12)
    }

    /// Quante righe del vicino sono comprese fino al punto: per il seguente quelle sopra, per il precedente quelle sotto.
    func keepCount(_ side: KeepSide, at y: CGFloat, mids: [CGFloat]) -> Int {
        switch side {
        case .next: mids.filter { $0 < y }.count
        case .previous: mids.filter { $0 > y }.count
        }
    }

    private func drawKeep(onPage index: Int, pageFrame: NSRect, in context: CGContext) {
        guard let design else { return }
        for side in [KeepSide.next, .previous] {
            guard let handle = keepHandleRect(side), pageFrame.insetBy(dx: -40, dy: -20).intersects(handle) else { continue }
            let neighbours = neighbourLines(side)
            let count = min(design.keep[side] ?? 0, neighbours.count)
            let locked = design.keepLocked.contains(side)
            let lit = design.activeKeep == side || hoveredKeep == side
            let color = locked ? NSColor.systemGray : Theme.accent
            // Le righe del vicino tenute: appena colorate sopra il velo, e una graffa nel margine.
            if count > 0 {
                context.setFillColor(color.withAlphaComponent(0.12).cgColor)
                for rect in neighbours.prefix(count) where pageFrame.intersects(rect) { context.fill(rect.insetBy(dx: -2, dy: 0)) }
            }
            if let fragment = side == .next ? designFragments().last : designFragments().first {
                let from = side == .next ? (fragment.lines.last?.midY ?? fragment.bottom) : (fragment.lines.first?.midY ?? fragment.top)
                context.saveGState()
                context.setStrokeColor(color.withAlphaComponent(lit ? 0.9 : 0.55).cgColor)
                context.setLineWidth(1.5)
                context.move(to: CGPoint(x: handle.midX, y: from))
                context.addLine(to: CGPoint(x: handle.midX, y: handle.midY))
                context.strokePath()
                // Una tacca per ogni riga tenuta.
                for rect in neighbours.prefix(count) where pageFrame.intersects(rect) {
                    context.move(to: CGPoint(x: handle.midX - 3, y: rect.midY))
                    context.addLine(to: CGPoint(x: handle.midX + 3, y: rect.midY))
                }
                context.strokePath()
                context.restoreGState()
            }
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)
            context.setFillColor((lit ? Theme.activeTop : color).cgColor)
            context.fillEllipse(in: handle)
            context.restoreGState()
            let number = NSAttributedString(string: "\(count)", attributes: [.font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: NSColor.white])
            let size = number.size()
            number.draw(at: NSPoint(x: handle.midX - size.width / 2, y: handle.midY - size.height / 2))
            if lit {
                drawLabel(locked ? "\(side.title(count)): formula — click to open" : side.title(count), color: color, near: handle, horizontal: true)
            }
        }
    }

    // MARK: I margini

    /// Lo specchio di stampa di una pagina, in coordinate della vista.
    func designTextRect(onPage index: Int) -> NSRect? {
        guard let layout, layout.pages.indices.contains(index) else { return nil }
        return viewRect(for: layout.setup(forPage: index).textRect(forPage: index), onPage: index)
    }

    /// Le maniglie dei margini di una pagina: a metà di ogni lato dello specchio.
    func marginHandleRects(onPage index: Int) -> [MarginSide: NSRect] {
        guard let rect = designTextRect(onPage: index) else { return [:] }
        return [.top: NSRect(x: rect.midX - 14, y: rect.minY - 3, width: 28, height: 6),
                .bottom: NSRect(x: rect.midX - 14, y: rect.maxY - 3, width: 28, height: 6),
                .left: NSRect(x: rect.minX - 3, y: rect.midY - 14, width: 6, height: 28),
                .right: NSRect(x: rect.maxX - 3, y: rect.midY - 14, width: 6, height: 28)]
    }

    /// La maniglia di margine sotto un punto.
    func marginHandle(at point: NSPoint) -> (page: Int, side: MarginSide)? {
        guard let layout else { return nil }
        for index in layout.pages.indices where frame(ofPage: index).insetBy(dx: -10, dy: -10).contains(point) {
            for (side, rect) in marginHandleRects(onPage: index) where rect.insetBy(dx: -4, dy: -4).contains(point) { return (index, side) }
        }
        return nil
    }

    /// La maniglia sotto un punto, con un po' di tolleranza intorno.
    func designHandle(at point: NSPoint) -> DesignHandle? {
        let rects = designHandleRects()
        // La maniglia trascinata o più piccola vince: la prima riga sta sopra la fascia dello spazio prima.
        let order: [DesignHandle] = [.firstLineIndent, .leftIndent, .rightIndent, .lineSpacing, .spaceBefore, .spaceAfter]
        return order.first { rects[$0]?.insetBy(dx: -4, dy: -4).contains(point) == true }
    }

    // MARK: Gesti

    func designMouseDown(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let design else { return false }
        if headingGrip(at: point) != nil, headingMouseDown(at: point) { return true }
        if ruleGrip(at: point) != nil, ruleMouseDown(at: point) { return true }
        if let handle = designHandle(at: point) {
            if design.locked.contains(handle) {
                onDesignLockedHandle?(handle)
                return true
            }
            designDrag = (handle, point, 1)
            onDesignDrag?(handle, .zero, .began, modifiers)
            return true
        }
        // Una linea di base più in basso: spostandola di un punto, l'interlinea cambia di un punto diviso per le righe
        // che la separano dalla prima.
        if let number = designBaseline(at: point) {
            if design.locked.contains(.lineSpacing) {
                onDesignLockedHandle?(.lineSpacing)
                return true
            }
            designDrag = (.lineSpacing, point, 1 / CGFloat(number))
            onDesignDrag?(.lineSpacing, .zero, .began, modifiers)
            return true
        }
        for side in [KeepSide.next, .previous] {
            guard let rect = keepHandleRect(side), rect.insetBy(dx: -4, dy: -4).contains(point) else { continue }
            if design.keepLocked.contains(side) {
                onKeepLocked?(side)
                return true
            }
            keepDrag = (side, neighbourLines(side).map(\.midY))
            onKeepDrag?(side, design.keep[side] ?? 0, .began)
            return true
        }
        if let margin = marginHandle(at: point) {
            marginDrag = (margin.page, margin.side, point)
            onMarginDrag?(margin.page, margin.side, .zero, .began, modifiers)
            return true
        }
        // Un clic su un filetto, o sulla fascia di una parte della testata, lo sceglie.
        if ruleMouseDown(at: point) { return true }
        if headingMouseDown(at: point) { return true }
        return false
    }

    func designMouseDragged(to point: NSPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        if headingMouseDragged(to: point) { return true }
        if ruleMouseDragged(to: point, modifiers: modifiers) { return true }
        if let drag = designDrag {
            var delta = designDelta(from: drag.start, to: point)
            delta.height *= drag.factor
            onDesignDrag?(drag.handle, delta, .changed, modifiers)
            return true
        }
        if let drag = marginDrag {
            onMarginDrag?(drag.page, drag.side, designDelta(from: drag.start, to: point), .changed, modifiers)
            return true
        }
        if let drag = keepDrag {
            onKeepDrag?(drag.side, keepCount(drag.side, at: point.y, mids: drag.mids), .changed)
            return true
        }
        return false
    }

    func designMouseUp(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        if headingMouseUp(at: point) { return true }
        if ruleMouseUp(at: point, modifiers: modifiers) { return true }
        if let drag = designDrag {
            designDrag = nil
            var delta = designDelta(from: drag.start, to: point)
            delta.height *= drag.factor
            onDesignDrag?(drag.handle, delta, .ended, modifiers)
            return true
        }
        if let drag = marginDrag {
            marginDrag = nil
            onMarginDrag?(drag.page, drag.side, designDelta(from: drag.start, to: point), .ended, modifiers)
            return true
        }
        if let drag = keepDrag {
            keepDrag = nil
            onKeepDrag?(drag.side, keepCount(drag.side, at: point.y, mids: drag.mids), .ended)
            return true
        }
        return false
    }

    func designMouseMoved(at point: NSPoint) -> Bool {
        guard design != nil else { return false }
        if headingMouseMoved(at: point) { return true }
        if ruleMouseMoved(at: point) { return true }
        hoveredDesignHandle = designHandle(at: point) ?? (designBaseline(at: point) != nil ? .lineSpacing : nil)
        hoveredKeep = hoveredDesignHandle == nil ? [KeepSide.next, .previous].first { keepHandleRect($0)?.insetBy(dx: -4, dy: -4).contains(point) == true } : nil
        hoveredMargin = hoveredDesignHandle == nil && hoveredKeep == nil ? marginHandle(at: point) : nil
        if hoveredKeep != nil {
            NSCursor.resizeUpDown.set()
            return true
        }
        if let handle = hoveredDesignHandle {
            if design?.locked.contains(handle) == true { NSCursor.pointingHand.set() } else if handle.isHorizontal { NSCursor.resizeLeftRight.set() } else { NSCursor.resizeUpDown.set() }
            return true
        }
        if let margin = hoveredMargin {
            (margin.side.isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
            return true
        }
        return false
    }

    private func designDelta(from start: NSPoint, to point: NSPoint) -> CGSize {
        CGSize(width: (point.x - start.x) / scale, height: (point.y - start.y) / scale)
    }

    // MARK: Disegno

    /// Il resto della pagina velato, le fasce degli spazi, le guide dei rientri e le maniglie.
    func drawDesign(onPage index: Int, pageFrame: NSRect, in context: CGContext) {
        guard let design else { return }
        let fragments = designFragments()
        let here = fragments.filter { $0.page == index }
        // Tutto ciò che non è il capoverso si attenua: resta leggibile, ma passa in secondo piano.
        context.saveGState()
        let veil = CGMutablePath()
        veil.addRect(pageFrame)
        // Un po' più largo della colonna: le lettere che sporgono nei margini ottici restano nitide.
        for fragment in here { veil.addRect(fragment.area.insetBy(dx: -8, dy: -3)) }
        context.addPath(veil)
        context.setFillColor(NSColor.white.withAlphaComponent(0.78).cgColor)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
        drawMargins(onPage: index, in: context)
        drawKeep(onPage: index, pageFrame: pageFrame, in: context)
        drawHeading(onPage: index, in: context)
        drawRules(onPage: index, in: context)
        guard !here.isEmpty else { return }

        let accent = Theme.accent
        let rects = designHandleRects()
        // Le fasce degli spazi prima e dopo.
        for fragment in here {
            if fragment.isFirst, design.value(.spaceBefore) > 0 {
                let height = design.value(.spaceBefore) * scale
                fillBand(NSRect(x: fragment.columnMinX, y: fragment.top - height, width: fragment.columnMaxX - fragment.columnMinX, height: height), in: context)
            }
            if fragment.isLast, design.value(.spaceAfter) > 0 {
                let height = design.value(.spaceAfter) * scale
                fillBand(NSRect(x: fragment.columnMinX, y: fragment.bottom, width: fragment.columnMaxX - fragment.columnMinX, height: height), in: context)
            }
            // I rientri sinistro e destro: il tratteggio fra il bordo della colonna e la guida, come per gli spazi.
            let indentLeft = design.value(.leftIndent) * scale, indentRight = design.value(.rightIndent) * scale
            if indentLeft > 0 {
                fillBand(NSRect(x: fragment.columnMinX, y: fragment.top, width: indentLeft, height: fragment.bottom - fragment.top), in: context)
            }
            if indentRight > 0 {
                fillBand(NSRect(x: fragment.columnMaxX - indentRight, y: fragment.top, width: indentRight, height: fragment.bottom - fragment.top), in: context)
            }
            // Le linee di base sotto le lettere: si trascinano per cambiare la distanza fra le righe.
            let lit = design.active == .lineSpacing || hoveredDesignHandle == .lineSpacing
            let baselineLeft = fragment.columnMinX + design.value(.leftIndent) * scale
            let baselineRight = fragment.columnMaxX - design.value(.rightIndent) * scale
            context.saveGState()
            context.setLineWidth(lit ? 1.2 : 0.8)
            for (offset, y) in fragment.baselines.enumerated() {
                let draggable = fragment.firstLineNumber + offset >= 1
                let alpha: CGFloat = design.locked.contains(.lineSpacing) ? 0.25 : (lit ? 0.85 : (draggable ? 0.45 : 0.25))
                context.setStrokeColor((design.locked.contains(.lineSpacing) ? NSColor.systemGray : accent).withAlphaComponent(alpha).cgColor)
                context.move(to: CGPoint(x: baselineLeft, y: y + 0.5))
                context.addLine(to: CGPoint(x: baselineRight, y: y + 0.5))
                context.strokePath()
            }
            context.restoreGState()
            // La colonna, appena accennata, e le guide dei rientri.
            context.saveGState()
            context.setLineWidth(1)
            context.setStrokeColor(accent.withAlphaComponent(0.25).cgColor)
            context.setLineDash(phase: 0, lengths: [2, 3])
            for x in [fragment.columnMinX, fragment.columnMaxX] {
                context.move(to: CGPoint(x: x, y: fragment.top - 6))
                context.addLine(to: CGPoint(x: x, y: fragment.bottom + 6))
            }
            context.strokePath()
            context.setStrokeColor(accent.withAlphaComponent(0.7).cgColor)
            context.setLineDash(phase: 0, lengths: [4, 3])
            let left = fragment.columnMinX + design.value(.leftIndent) * scale
            let right = fragment.columnMaxX - design.value(.rightIndent) * scale
            for x in [left, right] {
                context.move(to: CGPoint(x: x, y: fragment.top - 4))
                context.addLine(to: CGPoint(x: x, y: fragment.bottom + 4))
            }
            if fragment.isFirst, let line = fragment.lines.first {
                let x = left + design.value(.firstLineIndent) * scale
                context.move(to: CGPoint(x: x, y: line.minY - 2))
                context.addLine(to: CGPoint(x: x, y: line.maxY))
            }
            context.strokePath()
            context.restoreGState()
        }
        // Le maniglie che stanno su questa pagina.
        let pageHandles = rects.filter { _, rect in pageFrame.insetBy(dx: -40, dy: -40).intersects(rect) && here.contains { $0.area.insetBy(dx: -60, dy: -200).intersects(rect) } }
        for (handle, rect) in pageHandles where handle != .lineSpacing {
            drawHandle(handle, in: rect, locked: design.locked.contains(handle), lit: design.active == handle || hoveredDesignHandle == handle, context: context)
        }
        // Il valore della maniglia trascinata o sotto il mouse.
        if let shown = design.active ?? hoveredDesignHandle, var rect = pageHandles[shown] {
            if shown == .lineSpacing { rect = NSRect(x: rect.maxX + 4, y: rect.minY, width: 1, height: rect.height) }
            drawValueLabel(for: shown, value: design.value(shown), locked: design.locked.contains(shown), near: rect)
        }
    }

    /// Lo specchio di stampa di ogni pagina, tratteggiato, con le maniglie dei margini.
    private func drawMargins(onPage index: Int, in context: CGContext) {
        guard let rect = designTextRect(onPage: index), let layout else { return }
        context.saveGState()
        context.setStrokeColor(Theme.accent.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(0.75)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(rect)
        context.restoreGState()
        let setup = layout.setup(forPage: index)
        for (side, handle) in marginHandleRects(onPage: index) {
            let active = activeMargin.map { $0.page == index && $0.side == side } ?? false
            let hovered = hoveredMargin.map { $0.page == index && $0.side == side } ?? false
            context.saveGState()
            context.setFillColor((active || hovered ? Theme.activeTop : Theme.accent).withAlphaComponent(active || hovered ? 1 : 0.75).cgColor)
            context.addPath(CGPath(roundedRect: handle, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()
            context.restoreGState()
            if active || hovered {
                let value = setup[keyPath: side.field(onPage: index, facing: setup.facing)]
                let millimetres = PageSetup.millimetres(fromPoints: value).formatted(.number.precision(.fractionLength(0...1)))
                drawLabel("\(side.title)  \(millimetres) mm", color: Theme.accent, near: handle, horizontal: !side.isHorizontal)
            }
        }
    }

    private func drawLabel(_ text: String, color: NSColor, near rect: NSRect, horizontal: Bool) {
        let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.accentInk])
        let size = label.size()
        var box = NSRect(x: rect.maxX + 6, y: rect.midY - size.height / 2 - 3, width: size.width + 12, height: size.height + 6)
        if box.maxX > visibleRect.maxX - 4 { box.origin.x = rect.minX - box.width - 6 }
        color.setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
    }

    private func fillBand(_ rect: NSRect, in context: CGContext) {
        context.saveGState()
        context.setFillColor(Theme.accent.withAlphaComponent(0.10).cgColor)
        context.fill(rect)
        // Righe oblique sottili, come nelle quote dei disegni tecnici.
        context.clip(to: rect)
        context.setStrokeColor(Theme.accent.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(0.75)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.maxY))
            context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 6
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawHandle(_ handle: DesignHandle, in rect: NSRect, locked: Bool, lit: Bool, context: CGContext) {
        let fill = locked ? NSColor.systemGray : (lit ? Theme.activeTop : Theme.accent)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        context.setFillColor(fill.cgColor)
        if handle == .firstLineIndent {
            // Un triangolo che punta all'inizio della prima riga, come sul righello.
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.closePath()
            context.fillPath()
        } else {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: min(rect.width, rect.height) / 2, cornerHeight: min(rect.width, rect.height) / 2, transform: nil))
            context.fillPath()
        }
        context.restoreGState()
        if locked {
            let mark = NSAttributedString(string: "ƒ", attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white])
            let size = mark.size()
            mark.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    private func drawValueLabel(for handle: DesignHandle, value: CGFloat, locked: Bool, near rect: NSRect) {
        let number = Double(value).formatted(.number.precision(.fractionLength(0...1)))
        let text = locked ? "\(handle.title): formula — click to open" : "\(handle.title)  \(number) pt"
        let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.accentInk])
        let size = label.size()
        var box = NSRect(x: rect.maxX + 6, y: rect.midY - size.height / 2 - 3, width: size.width + 12, height: size.height + 6)
        if !handle.isHorizontal || handle == .firstLineIndent {
            box.origin = NSPoint(x: rect.maxX + 6, y: rect.midY - box.height / 2)
        }
        // Dentro lo spazio visibile, anche vicino al bordo destro.
        if box.maxX > visibleRect.maxX - 4 { box.origin.x = rect.minX - box.width - 6 }
        (locked ? NSColor.systemGray : Theme.accent).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
    }

    // MARK: I pulsanti intorno al capoverso

    /// Mette i pulsanti sopra il capoverso (sopra lo spazio prima), o sotto se in cima alla pagina non c'è posto.
    func positionDesignBar() {
        if let actions = designActions {
            let size = actions.fittingSize
            actions.frame = NSRect(x: visibleRect.maxX - size.width - 12, y: visibleRect.minY + 10, width: size.width, height: size.height)
            actions.isHidden = design == nil
        }
        guard let bar = designBar else { return }
        guard design != nil else {
            bar.isHidden = true
            return
        }
        // Fissa in alto a sinistra della zona visibile, come Salva e Annulla a destra: non copre mai il testo. Se è più larga
        // della zona visibile, le sue icone vanno a capo.
        onDesignBarWidth?(max(visibleRect.width - 40, 200))
        let size = bar.fittingSize
        var frame = NSRect(x: visibleRect.minX + 12, y: visibleRect.minY + 10, width: size.width, height: size.height)
        // In una finestra stretta la barra arriverebbe sotto Salva e Annulla: scende sotto il loro riquadro.
        if let actions = designActions, !actions.isHidden, frame.maxX > actions.frame.minX - 8 {
            frame.origin.y = actions.frame.maxY + 6
        }
        bar.frame = frame
        bar.isHidden = false
    }
}
