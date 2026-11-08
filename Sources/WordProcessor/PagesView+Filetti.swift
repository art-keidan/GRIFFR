import AppKit
import Typesetting

/// Che cosa si prende di un filetto libero: il filetto intero (lo si sposta lontano o vicino al bordo a cui è
/// agganciato), o uno dei due capi (lo si allunga o lo si accorcia).
enum RuleGrip: Hashable { case body, start, end }

struct RuleGripID: Hashable {
    var rule: Int
    var grip: RuleGrip
}

extension ParagraphRule {
    /// Il filetto dopo uno spostamento del mouse (in punti di pagina, in basso e a destra positivi).
    func moved(_ grip: RuleGrip, by delta: CGSize) -> ParagraphRule {
        var result = self
        let dx = Double(delta.width), dy = Double(delta.height)
        switch (grip, anchor) {
        case (.body, .top): result.offset -= dy
        case (.body, .bottom): result.offset += dy
        case (.body, .left): result.offset -= dx
        case (.body, .right): result.offset += dx
        case (.start, .top), (.start, .bottom): result.start -= dx
        case (.end, .top), (.end, .bottom): result.end += dx
        case (.start, .left), (.start, .right): result.start -= dy
        case (.end, .left), (.end, .right): result.end += dy
        }
        return result
    }
}

extension PagesView {
    /// I filetti posati del capoverso progettato, in coordinate della vista.
    func designPlacedRules() -> [(rule: Int, page: Int, rect: NSRect)] {
        guard let design, let layout else { return [] }
        var result: [(Int, Int, NSRect)] = []
        for (index, page) in layout.pages.enumerated() {
            for placed in page.paragraphRules where placed.paragraphLocation == design.paragraphLocation {
                result.append((placed.rule, index, viewRect(for: placed.rect, onPage: index)))
            }
        }
        return result
    }

    /// Le maniglie del filetto scelto: una sul filetto, una per capo (per un filetto a lato, sul suo primo pezzo).
    func ruleGripRects() -> [RuleGripID: NSRect] {
        guard let design, let selected = design.selectedRule, design.rules.indices.contains(selected),
              let placed = designPlacedRules().first(where: { $0.rule == selected }) else { return [:] }
        let rect = placed.rect
        if design.rules[selected].anchor.isHorizontal {
            return [RuleGripID(rule: selected, grip: .body): NSRect(x: rect.midX - 9, y: rect.midY - 3, width: 18, height: 6),
                    RuleGripID(rule: selected, grip: .start): NSRect(x: rect.minX - 3, y: rect.midY - 7, width: 6, height: 14),
                    RuleGripID(rule: selected, grip: .end): NSRect(x: rect.maxX - 3, y: rect.midY - 7, width: 6, height: 14)]
        }
        return [RuleGripID(rule: selected, grip: .body): NSRect(x: rect.midX - 3, y: rect.midY - 9, width: 6, height: 18),
                RuleGripID(rule: selected, grip: .start): NSRect(x: rect.midX - 7, y: rect.minY - 3, width: 14, height: 6),
                RuleGripID(rule: selected, grip: .end): NSRect(x: rect.midX - 7, y: rect.maxY - 3, width: 14, height: 6)]
    }

    func ruleGrip(at point: NSPoint) -> RuleGripID? {
        // I capi prima del corpo: su un filetto corto stanno vicini.
        let rects = ruleGripRects()
        return rects.filter { $0.key.grip != .body }.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
            ?? rects.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
    }

    /// Il filetto sotto il punto, con un po' di tolleranza (i filetti sono sottili).
    func placedRule(at point: NSPoint) -> Int? {
        designPlacedRules().first { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }?.rule
    }

    func ruleMouseDown(at point: NSPoint) -> Bool {
        if let id = ruleGrip(at: point), let placed = designPlacedRules().first(where: { $0.rule == id.rule }), let design,
           design.rules.indices.contains(id.rule) {
            let horizontal = design.rules[id.rule].anchor.isHorizontal
            // L'asse lungo cui la maniglia si muove: il corpo di traverso al filetto, i capi lungo il filetto.
            let alongX = (id.grip == .body) != horizontal
            let rect = placed.rect
            let along: CGFloat = switch (id.grip, alongX) {
            case (.body, true): rect.midX
            case (.body, false): rect.midY
            case (.start, true): rect.minX
            case (.start, false): rect.minY
            case (.end, true): rect.maxX
            case (.end, false): rect.maxY
            }
            ruleDrag = (id, point, along, alongX, ruleTargets(alongX: alongX, excluding: id.rule))
            onRuleDrag?(id, .zero, .began, [])
            return true
        }
        if let rule = placedRule(at: point) {
            onRuleSelect?(rule)
            return true
        }
        return false
    }

    /// Lo spostamento del mouse, con l'attrazione delle posizioni notevoli lungo l'asse del gesto (⌘ la spegne).
    private func ruleDelta(to point: NSPoint, modifiers: NSEvent.ModifierFlags) -> CGSize {
        guard let drag = ruleDrag else { return .zero }
        var delta = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
        // Solo lungo l'asse: di traverso il filetto non si muove.
        if drag.alongX { delta.height = 0 } else { delta.width = 0 }
        let moved = drag.along + (drag.alongX ? delta.width : delta.height)
        var guide: (Bool, CGFloat)?
        if !modifiers.contains(.command), let target = drag.targets.min(by: { abs($0 - moved) < abs($1 - moved) }), abs(target - moved) <= 4 {
            if drag.alongX { delta.width = target - drag.along } else { delta.height = target - drag.along }
            guide = (drag.alongX, target)
        }
        ruleGuide = guide.map { (alongX: $0.0, value: $0.1) }
        return CGSize(width: delta.width / scale, height: delta.height / scale)
    }

    func ruleMouseDragged(to point: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        guard let drag = ruleDrag else { return false }
        onRuleDrag?(drag.id, ruleDelta(to: point, modifiers: modifiers), .changed, modifiers)
        return true
    }

    func ruleMouseUp(at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        guard let drag = ruleDrag else { return false }
        let delta = ruleDelta(to: point, modifiers: modifiers)
        ruleDrag = nil
        ruleGuide = nil
        onRuleDrag?(drag.id, delta, .ended, modifiers)
        return true
    }

    /// Le posizioni notevoli lungo un asse, per il filetto che si trascina: i bordi del testo e della colonna, le guide dei
    /// rientri, le linee di base della prima e dell'ultima riga, i bordi degli spazi prima e dopo, la metà dello spazio verso
    /// i capoversi vicini, la metà dei margini, gli altri filetti del capoverso.
    func ruleTargets(alongX: Bool, excluding rule: Int) -> [CGFloat] {
        guard let design, let first = designFragments().first, let last = designFragments().last else { return [] }
        var targets: [CGFloat] = []
        let others = designPlacedRules().filter { $0.rule != rule }
        if alongX {
            for fragment in [first, last] {
                let left = fragment.columnMinX + design.value(.leftIndent) * scale
                let right = fragment.columnMaxX - design.value(.rightIndent) * scale
                targets += [fragment.columnMinX, fragment.columnMaxX, left, right]
                if let page = frameOfPage(fragment.page) {
                    targets += [(page.minX + fragment.columnMinX) / 2, (fragment.columnMaxX + page.maxX) / 2]
                }
            }
            targets += others.flatMap { [$0.rect.minX, $0.rect.midX, $0.rect.maxX] }
        } else {
            targets += [first.top, last.bottom]
            if let baseline = first.baselines.first { targets.append(baseline) }
            if let baseline = last.baselines.last { targets.append(baseline) }
            targets += [first.top - design.value(.spaceBefore) * scale, last.bottom + design.value(.spaceAfter) * scale]
            if let previous = neighbourLines(.previous).first { targets.append((previous.maxY + first.top) / 2) }
            if let next = neighbourLines(.next).first { targets.append((last.bottom + next.minY) / 2) }
            targets += others.flatMap { [$0.rect.minY, $0.rect.midY, $0.rect.maxY] }
        }
        return targets
    }

    func ruleMouseMoved(at point: NSPoint) -> Bool {
        hoveredRuleGrip = ruleGrip(at: point)
        guard let id = hoveredRuleGrip, let design, design.rules.indices.contains(id.rule) else {
            if placedRule(at: point) != nil {
                NSCursor.pointingHand.set()
                return true
            }
            return false
        }
        let horizontal = design.rules[id.rule].anchor.isHorizontal
        // Il corpo si muove di traverso al filetto, i capi lungo il filetto.
        let alongX = (id.grip == .body) != horizontal
        (alongX ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        return true
    }

    /// Il filetto scelto, evidenziato, le sue maniglie e le sue misure.
    func drawRules(onPage index: Int, in context: CGContext) {
        guard let design else { return }
        for placed in designPlacedRules() where placed.page == index {
            let selected = design.selectedRule == placed.rule
            context.saveGState()
            context.setStrokeColor(Theme.accent.withAlphaComponent(selected ? 0.9 : 0.4).cgColor)
            context.setLineWidth(selected ? 1.5 : 0.75)
            if !selected { context.setLineDash(phase: 0, lengths: [2, 2]) }
            context.stroke(placed.rect.insetBy(dx: -2.5, dy: -2.5))
            context.restoreGState()
        }
        // La guida della posizione notevole che attira il filetto, attraverso la pagina.
        if let guide = ruleGuide, let frame = frameOfPage(index) {
            context.saveGState()
            context.setStrokeColor(Theme.accent.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(0.75)
            context.setLineDash(phase: 0, lengths: [3, 2])
            if guide.alongX {
                context.move(to: CGPoint(x: guide.value, y: frame.minY))
                context.addLine(to: CGPoint(x: guide.value, y: frame.maxY))
            } else {
                context.move(to: CGPoint(x: frame.minX, y: guide.value))
                context.addLine(to: CGPoint(x: frame.maxX, y: guide.value))
            }
            context.strokePath()
            context.restoreGState()
        }
        let grips = ruleGripRects()
        guard let page = designPlacedRules().first(where: { $0.rule == design.selectedRule })?.page, page == index else { return }
        for (id, rect) in grips {
            let lit = design.activeRuleGrip == id || hoveredRuleGrip == id
            context.saveGState()
            context.setFillColor((lit ? Theme.activeTop : Theme.accent).cgColor)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: min(rect.width, rect.height) / 2, cornerHeight: min(rect.width, rect.height) / 2, transform: nil))
            context.fillPath()
            context.restoreGState()
        }
        if let shown = design.activeRuleGrip ?? hoveredRuleGrip, let rect = grips[shown], design.rules.indices.contains(shown.rule) {
            let rule = design.rules[shown.rule]
            func mm(_ points: Double) -> String { PageSetup.millimetres(fromPoints: CGFloat(points)).formatted(.number.precision(.fractionLength(0...1))) + " mm" }
            let text = switch shown.grip {
            case .body: "\(rule.anchor.title), \(mm(rule.offset)) from the text"
            case .start: "Start \(mm(rule.start))"
            case .end: "End \(mm(rule.end))"
            }
            let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.accentInk])
            let size = label.size()
            var box = NSRect(x: rect.maxX + 6, y: rect.midY - size.height / 2 - 3, width: size.width + 12, height: size.height + 6)
            if box.maxX > visibleRect.maxX - 4 { box.origin.x = rect.minX - box.width - 6 }
            Theme.accent.setFill()
            NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
            label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
        }
    }
}
