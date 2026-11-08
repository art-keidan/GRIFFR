import AppKit
import Typesetting

// MARK: - L'albero degli oggetti

/// Dove va un oggetto trascinato rispetto alla destinazione: prima, dopo, (per un titolo) dentro la sua sezione, o (un
/// capoverso) dopo la sua sezione, tornando a quella esterna.
enum OutlineDropPlacement: Equatable {
    case before, inside, after, afterSection
}

/// Lo stato dell'albero degli oggetti, a sinistra nell'interfaccia avanzata: gli oggetti del documento, quello in cui
/// sta il cursore, i titoli chiusi, il filtro. La vista è `ObjectTreeView`, una lista nativa del Mac.
@MainActor
final class ObjectTreeModel {
    enum Change { case items, selection }

    var items: [OutlineItem] = [] { didSet { if items != oldValue { onChange?(.items) } } }
    var filter = "" { didSet { if filter != oldValue { onChange?(.items) } } }
    /// L'oggetto evidenziato: quello del cursore, o quello appena scelto.
    var selection: OutlineItem.ID? { didSet { if selection != oldValue { onChange?(.selection) } } }
    /// I titoli chiusi (all'inizio sono tutti aperti).
    var collapsed: Set<OutlineItem.ID> = []
    /// Un clic su un oggetto: il cursore va lì.
    var onChoose: ((OutlineItem) -> Void)?
    /// Un capoverso o una sezione trascinati su un'altra destinazione.
    var onMoveItem: ((_ source: OutlineItem, _ target: OutlineItem, _ placement: OutlineDropPlacement) -> Void)?
    /// La vista, avvisata quando cambiano gli oggetti o la selezione.
    var onChange: ((Change) -> Void)?

    var isFiltering: Bool { !filter.trimmingCharacters(in: .whitespaces).isEmpty }
    var shown: [OutlineItem] { DocumentOutline.filtered(items, by: filter) }

    func item(_ id: OutlineItem.ID) -> OutlineItem? {
        func find(_ list: [OutlineItem]) -> OutlineItem? {
            for item in list {
                if item.id == id { return item }
                if let children = item.children, let found = find(children) { return found }
            }
            return nil
        }
        return find(items)
    }

    /// Un solo ingresso per il clic e per le prove: evidenzia la riga e porta il cursore al testo.
    func choose(_ item: OutlineItem) {
        selection = item.id
        onChoose?(item)
    }

    private func contains(_ id: OutlineItem.ID, in item: OutlineItem) -> Bool {
        item.id == id || (item.children?.contains { contains(id, in: $0) } ?? false)
    }

    /// Solo capoversi e titoli si trascinano, e non nella mappa filtrata (le posizioni non sarebbero quelle vere).
    func canDrag(_ id: OutlineItem.ID) -> Bool {
        guard !isFiltering, let item = item(id) else { return false }
        if case .heading = item.kind { return true }
        return item.kind == .paragraph
    }

    // MARK: Il rilascio

    /// Un rilascio tradotto in uno spostamento del documento, e la posizione della lista in cui mostrarlo: `parent`
    /// è il titolo che contiene la linea (`nil` per il primo livello), `index` la posizione fra i suoi figli, oppure
    /// `nil` quando il rilascio va sul titolo stesso (dentro la sua sezione).
    struct Drop: Equatable {
        var target: OutlineItem
        var placement: OutlineDropPlacement
        var parent: OutlineItem.ID?
        var index: Int?
    }

    private static func isHeading(_ item: OutlineItem) -> Bool {
        if case .heading = item.kind { return true }
        return false
    }

    /// I figli di un titolo, o il primo livello; `nil` se `parent` non è un titolo della mappa.
    private func children(of parent: OutlineItem.ID?) -> [OutlineItem]? {
        guard let parent else { return items }
        guard let item = item(parent), Self.isHeading(item) else { return nil }
        return item.children ?? []
    }

    /// Un titolo lasciato sopra un altro titolo: diventa l'ultima sezione interna.
    func dropOnto(source sourceID: OutlineItem.ID, item targetID: OutlineItem.ID) -> Drop? {
        guard canDrag(sourceID), let source = item(sourceID), Self.isHeading(source),
              let target = item(targetID), Self.isHeading(target), !contains(targetID, in: source) else { return nil }
        return Drop(target: target, placement: .inside, parent: targetID, index: nil)
    }

    /// Una linea fra due righe, che la lista propone come «figlio numero `index` di `parent`», tradotta in uno
    /// spostamento possibile. Il testo di una sezione può tornare dopo le sue sezioni interne:
    /// - un titolo va fra le sezioni o davanti a un capoverso (che resta alla sua sezione, con quelli che lo seguono);
    ///   in fondo a una sezione diventa la sua ultima sezione interna;
    /// - un capoverso va fra il testo, subito dopo il titolo, o dopo una sezione interna (torna alla sezione esterna).
    func dropBetween(source sourceID: OutlineItem.ID, parent: OutlineItem.ID?, index proposed: Int) -> Drop? {
        guard canDrag(sourceID), let source = item(sourceID), let kids = children(of: parent) else { return nil }
        if let parent, contains(parent, in: source) { return nil }
        let index = min(max(proposed, 0), kids.count)
        let firstHeading = kids.firstIndex(where: Self.isHeading)
        // Subito prima o subito dopo sé stesso: l'oggetto è già lì.
        if index < kids.count, kids[index].id == sourceID { return nil }
        if index > 0, kids[index - 1].id == sourceID { return nil }

        func isText(_ item: OutlineItem) -> Bool { item.kind == .paragraph || item.kind == .listItem }
        if Self.isHeading(source) {
            // Davanti a un capoverso: lui e quelli che lo seguono restano alla loro sezione, dopo quella spostata.
            if index < kids.count, isText(kids[index]) {
                return Drop(target: kids[index], placement: .before, parent: parent, index: index)
            }
            if index < kids.count, Self.isHeading(kids[index]) {
                return Drop(target: kids[index], placement: .before, parent: parent, index: index)
            }
            if let previous = kids[..<index].lastIndex(where: Self.isHeading) {
                return kids[previous].id == sourceID ? nil : Drop(target: kids[previous], placement: .after, parent: parent, index: index)
            }
            if let firstHeading {
                return kids[firstHeading].id == sourceID ? nil : Drop(target: kids[firstHeading], placement: .before, parent: parent, index: firstHeading)
            }
            guard let parent, let owner = item(parent) else { return nil }
            return Drop(target: owner, placement: .inside, parent: parent, index: kids.count)
        }

        // Un capoverso: accanto a un capoverso o a una voce d'elenco, dopo una sezione interna (torna a questa), o subito
        // dopo il titolo.
        if index < kids.count, isText(kids[index]) {
            return Drop(target: kids[index], placement: .before, parent: parent, index: index)
        }
        // Le note e le figure stanno dopo il loro capoverso: si saltano.
        if let previous = kids[..<index].lastIndex(where: { !$0.isFloating }) {
            if isText(kids[previous]) { return Drop(target: kids[previous], placement: .after, parent: parent, index: index) }
            if Self.isHeading(kids[previous]) { return Drop(target: kids[previous], placement: .afterSection, parent: parent, index: index) }
            return nil
        }
        if index < kids.count, Self.isHeading(kids[index]) {
            return Drop(target: kids[index], placement: .before, parent: parent, index: index)
        }
        guard let parent, let owner = item(parent) else { return nil }
        return Drop(target: owner, placement: .after, parent: parent, index: index)
    }

    /// La vista AppKit dell'albero.
    func makeView() -> NSView { ObjectTreeView(model: self) }
}

// MARK: - La vista

/// La mappa: una lista nativa (`NSOutlineView`) con il campo del filtro sotto. Il trascinamento è quello del sistema:
/// la lista propone dove cadrebbe il rilascio (anche il livello, spostando il mouse a sinistra o a destra), il modello
/// lo traduce in uno spostamento possibile o lo rifiuta.
@MainActor
final class ObjectTreeView: NSVisualEffectView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    /// Un oggetto della mappa come riga della lista (la lista vuole oggetti, non valori).
    final class Node: NSObject {
        let item: OutlineItem
        let children: [Node]
        init(_ item: OutlineItem) {
            self.item = item
            children = (item.children ?? []).map(Node.init)
        }
    }

    static let dragType = NSPasteboard.PasteboardType("local.griffr.outline-item")

    private let model: ObjectTreeModel
    let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private let filterField = NSTextField()
    private let emptyLabel = NSTextField(labelWithString: "The document is empty.")
    private(set) var roots: [Node] = []
    private var nodes: [OutlineItem.ID: Node] = [:]
    /// Durante la ricostruzione aprire i titoli non va registrato come scelta di chi scrive.
    private var reloading = false
    private var draggedID: OutlineItem.ID?
    private var lastDrop: ObjectTreeModel.Drop?

    init(model: ObjectTreeModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 232, height: 400))
        material = .sidebar
        blendingMode = .behindWindow

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("oggetto"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.autoresizesOutlineColumn = false
        outline.indentationPerLevel = 12
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked(_:))
        outline.registerForDraggedTypes([Self.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.draggingDestinationFeedbackStyle = .sourceList

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        filterField.placeholderString = "Filter"
        filterField.bezelStyle = .roundedBezel
        filterField.delegate = self
        filterField.toolTip = "Show only the objects that contain these letters (in their first words, marker or style)"
        filterField.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .preferredFont(forTextStyle: .caption1)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [scroll, emptyLabel, filterField] as [NSView] { addSubview(view) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: filterField.topAnchor, constant: -8),
            emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            filterField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            filterField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            filterField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        model.onChange = { [weak self] change in
            switch change {
            case .items: self?.reload()
            case .selection: self?.showSelection()
            }
        }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Contenuto

    /// Ricostruisce le righe dagli oggetti; riapre i titoli che non erano chiusi e rimette la selezione.
    func reload() {
        reloading = true
        defer { reloading = false }
        roots = model.shown.map(Node.init)
        nodes = [:]
        func index(_ list: [Node]) { for node in list { nodes[node.item.id] = node; index(node.children) } }
        index(roots)
        outline.reloadData()
        let filtering = model.isFiltering
        func expand(_ list: [Node]) {
            for node in list where node.item.children != nil {
                if filtering || !model.collapsed.contains(node.item.id) {
                    outline.expandItem(node)
                    expand(node.children)
                }
            }
        }
        expand(roots)
        emptyLabel.isHidden = !model.items.isEmpty
        showSelection()
    }

    private func showSelection() {
        guard let id = model.selection, let node = nodes[id] else {
            outline.deselectAll(nil)
            return
        }
        let row = outline.row(forItem: node)
        guard row >= 0 else {
            outline.deselectAll(nil)
            return
        }
        if outline.selectedRow != row { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        outline.scrollRowToVisible(row)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
        model.choose(node.item)
    }

    func controlTextDidChange(_ notification: Notification) {
        model.filter = filterField.stringValue
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? Node else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.item.children != nil
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !reloading, !model.isFiltering, let node = notification.userInfo?["NSObject"] as? Node else { return }
        model.collapsed.remove(node.item.id)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !reloading, !model.isFiltering, let node = notification.userInfo?["NSObject"] as? Node else { return }
        model.collapsed.insert(node.item.id)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("riga")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? ObjectTreeCell ?? ObjectTreeCell()
        cell.identifier = identifier
        cell.show(node.item)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?,
                     item: Any, mouseLocation: NSPoint) -> String {
        (item as? Node)?.item.title ?? ""
    }

    // MARK: Trascinamento

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node, model.canDrag(node.item.id) else { return nil }
        let writer = NSPasteboardItem()
        writer.setString(String(node.item.id), forType: Self.dragType)
        return writer
    }

    /// Durante il trascinamento la riga di partenza non è evidenziata ma attenuata, e sotto il mouse viaggia solo il suo
    /// testo, spostato in basso a destra: l'evidenziazione e l'immagine hanno il colore della linea d'inserimento e la
    /// coprivano.
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                     forItems draggedItems: [Any]) {
        guard let node = draggedItems.first as? Node else { return }
        draggedID = node.item.id
        outline.deselectAll(nil)
        setDimmed(true, node)
        let image = Self.dragImage(for: node.item)
        var pointer = window.map { $0.convertPoint(fromScreen: screenPoint) } ?? screenPoint
        pointer = outline.convert(pointer, from: nil)
        session.enumerateDraggingItems(options: [], for: outline, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            item.setDraggingFrame(NSRect(x: pointer.x + 14, y: pointer.y + 6, width: image.size.width, height: image.size.height),
                                  contents: image)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                     operation: NSDragOperation) {
        // Dopo un rilascio la lista è ricostruita e le righe riusate: tutte tornano piene.
        outline.enumerateAvailableRowViews { rowView, _ in rowView.alphaValue = 1 }
        draggedID = nil
        lastDrop = nil
        showSelection()
    }

    private func setDimmed(_ dimmed: Bool, _ node: Node) {
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = dimmed ? 0.35 : 1
    }

    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        if draggedID == nil { rowView.alphaValue = 1 }
    }

    /// Il segno e le prime parole, senza sfondo.
    private static func dragImage(for item: OutlineItem) -> NSImage {
        let text = NSAttributedString(string: [item.label, item.title].filter { !$0.isEmpty }.joined(separator: " "), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: item.children != nil ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.75),
        ])
        let size = NSSize(width: min(ceil(text.size().width) + 4, 240), height: ceil(text.size().height) + 2)
        return NSImage(size: size, flipped: false) { rect in
            text.draw(with: rect.insetBy(dx: 2, dy: 1), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        lastDrop = nil
        guard info.draggingSource as? NSOutlineView === outline, let source = draggedID else { return [] }
        let proposedParent = item as? Node
        guard let drop = resolve(source: source, parent: proposedParent, index: index, location: info.draggingLocation) else { return [] }
        let shownParent = drop.parent.flatMap { nodes[$0] }
        let shownIndex = drop.index ?? NSOutlineViewDropOnItemIndex
        if shownParent !== proposedParent || shownIndex != index {
            outline.setDropItem(shownParent, dropChildIndex: shownIndex)
        }
        lastDrop = drop
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let source = draggedID.flatMap({ model.item($0) }), let drop = lastDrop else { return false }
        draggedID = nil
        lastDrop = nil
        model.onMoveItem?(source, drop.target, drop.placement)
        return true
    }

    /// La proposta della lista tradotta. Sopra un titolo un titolo entra; sopra un capoverso, o un capoverso sopra un
    /// titolo, conta la metà della riga: la parte alta vale «prima», la bassa «dopo» (o, su un titolo aperto,
    /// «primo nella sua sezione»).
    private func resolve(source: OutlineItem.ID, parent: Node?, index: Int, location: NSPoint) -> ObjectTreeModel.Drop? {
        guard index == NSOutlineViewDropOnItemIndex else {
            return model.dropBetween(source: source, parent: parent?.item.id, index: index)
        }
        guard let node = parent else { return nil }
        if let drop = model.dropOnto(source: source, item: node.item.id) { return drop }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return nil }
        let point = outline.convert(location, from: nil)
        let lower = point.y > outline.rect(ofRow: row).midY
        if lower, node.item.children != nil, outline.isItemExpanded(node) {
            return model.dropBetween(source: source, parent: node.item.id, index: 0)
        }
        let owner = outline.parent(forItem: node) as? Node
        let position = outline.childIndex(forItem: node) + (lower ? 1 : 0)
        return model.dropBetween(source: source, parent: owner?.item.id, index: position)
    }
}

/// Una riga della mappa: il segno (¶, §, ▣…) e le prime parole; i titoli in grassetto.
final class ObjectTreeCell: NSTableCellView {
    private let mark = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        mark.font = .preferredFont(forTextStyle: .caption1)
        mark.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.cell?.truncatesLastVisibleLine = true
        for field in [mark, title] {
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        textField = title
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            mark.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            mark.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            title.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 4),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ item: OutlineItem) {
        mark.stringValue = item.label
        mark.isHidden = item.label.isEmpty
        title.stringValue = item.title
        let size = NSFont.systemFontSize
        title.font = item.children != nil ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
    }
}
