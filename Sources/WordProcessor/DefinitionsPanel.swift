import AppKit
import Combine
import SwiftUI
import Typesetting

/// Il pannello dell'interfaccia avanzata: le schede Ispettore, Liste, Flottanti, Regole. Nelle schede delle
/// definizioni ogni modifica passa al documento da sola, dopo una breve pausa (così scrivere un nome non fa un passo di
/// «Annulla» per lettera); se il documento cambia per altre vie (Annulla, Ripeti, Incolla), le schede si ricaricano.
@MainActor
final class DefinitionsPanel {
    enum Tab: Int, CaseIterable {
        case inspector, styles, lists, floats, rules, pages, tables

        var title: String {
            switch self {
            case .inspector: "Ispettore"
            case .styles: "Stili"
            case .lists: "Liste"
            case .floats: "Flottanti"
            case .rules: "Regole"
            case .pages: "Pagine"
            case .tables: "Tabelle"
            }
        }
    }

    let view = NSView()
    private let tabs = NSSegmentedControl(labels: ["Isp.", "Stili", "Liste", "Flott.", "Regole", "Pagine", "Tabelle"],
                                          trackingMode: .selectOne, target: nil, action: nil)
    private let content = NSView()
    private var hosts: [Tab: NSView] = [:]
    private(set) var tab = Tab.inspector

    private(set) var lists: ListsSheetModel?
    private(set) var floats: FloatStylesSheetModel?
    private(set) var rules: RulesSheetModel?
    private(set) var pageTypes: PageTypesSheetModel?
    private(set) var tableStyles: TableStylesSheetModel?
    private var watchers: [Tab: AnyCancellable] = [:]
    private var pending: [Tab: Timer] = [:]
    /// Vero mentre il pannello stesso cambia un modello: quel cambiamento non va riapplicato.
    private var isAdjusting = false

    /// Applicano al documento ciò che dice una scheda; vero se il documento è cambiato.
    var applyLists: ((ListsSheetModel.Result) -> Bool)?
    var applyFloats: ((FloatStylesSheetModel.Result) -> Bool)?
    var applyRules: ((RulesSheetModel.Result) -> Bool)?
    var applyPageTypes: ((PageTypesSheetModel.Result) -> Bool)?
    var applyTableStyles: ((TableStylesSheetModel.Result) -> Bool)?
    /// La scheda Stili: il modello lo prepara l'editor, che lo tiene in pari (`refreshStyles`).
    var stylesModel: StylesTabModel?
    /// Le modifiche della scheda Stili in attesa (le tiene l'editor): si applicano anch'esse quando si svuota l'attesa.
    var onFlush: (() -> Void)?
    var refreshStyles: (() -> Void)?
    /// Le definizioni del documento, per costruire e confrontare le schede.
    var settings: (() -> Typesetting.Document)?
    /// I ruoli delle sezioni del testo (le impostazioni non hanno il testo).
    var sectionRoles: (() -> [String])?

    /// La pausa dopo l'ultima modifica, prima di applicarla.
    static let pause: TimeInterval = 0.4

    init(inspector: NSView) {
        tabs.controlSize = .small
        tabs.segmentStyle = .texturedRounded
        for tab in Tab.allCases { tabs.setToolTip(tab.title, forSegment: tab.rawValue) }
        tabs.setAccessibilityLabel("Sezione degli strumenti dettagliati")
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        let bar = Bands.band([tabs, Bands.spacer()], height: 32)
        bar.fill = Theme.side
        for subview in [bar, content] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: bar.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosts[.inspector] = inspector
        place(inspector)
        tabs.selectedSegment = 0
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        show(Tab(rawValue: sender.selectedSegment) ?? .inspector)
    }

    private func place(_ child: NSView) {
        content.subviews.forEach { $0.removeFromSuperview() }
        child.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: content.topAnchor),
            child.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    /// Mostra una scheda, costruendola dal documento se serve.
    func show(_ tab: Tab) {
        // Prima di lasciare una scheda, ciò che vi si è appena scritto va al documento.
        flushPending()
        self.tab = tab
        tabs.selectedSegment = tab.rawValue
        if tab != .inspector { reload(tab, force: hosts[tab] == nil) }
        if let host = hosts[tab] { place(host) }
    }

    /// Mostra la scheda Regole con la regola `index` scelta.
    func showRule(at index: Int) {
        show(.rules)
        guard let rules, rules.rows.indices.contains(index) else { return }
        isAdjusting = true
        rules.selection = rules.rows[index].id
        isAdjusting = false
    }

    /// Applica subito le modifiche in attesa della pausa.
    func flushPending() {
        onFlush?()
        let waiting = pending
        pending = [:]
        for (tab, timer) in waiting {
            timer.invalidate()
            apply(tab)
        }
    }

    // MARK: Le schede e il documento

    /// Butta via le modifiche in attesa della pausa, senza applicarle (il documento è stato sostituito: «Ripristina
    /// versione salvata»). Le schede si ricaricano poi dal documento nuovo, con `documentChanged`.
    func discardPending() {
        for timer in pending.values { timer.invalidate() }
        pending = [:]
    }

    /// Il documento è cambiato: le schede già costruite che non dicono più ciò che dice il documento si ricaricano.
    /// Non durante una modifica in attesa di essere applicata: sarà lei a portare il documento in pari.
    func documentChanged() {
        for tab in [Tab.lists, .floats, .rules, .pages, .tables] where hosts[tab] != nil && pending[tab] == nil { reload(tab, force: false) }
        if hosts[.styles] != nil { refreshStyles?() }
    }

    private func reload(_ tab: Tab, force: Bool) {
        guard let document = settings?() else { return }
        switch tab {
        case .inspector: return
        case .styles:
            refreshStyles?()
            guard hosts[.styles] == nil, let model = stylesModel else { return }
            let host = NSHostingView(rootView: StylesTabView(model: model).themed())
            host.sizingOptions = []
            hosts[.styles] = host
        case .lists:
            if !force, let lists, lists.result().lists == document.lists, lists.result().noteList == document.noteList,
               lists.result().pageNumbering == document.pageNumbering { return }
            let selected = lists?.selectedIndex.flatMap { lists?.rows[$0].definition.name }
            let model = ListsSheetModel(lists: document.lists, noteList: document.noteList, pageNumbering: document.pageNumbering)
            model.documentRoles = sectionRoles?() ?? document.sectionRoles
            if let selected, let row = model.rows.first(where: { $0.definition.name == selected }) { model.selection = row.id }
            lists = model
            install(tab, model, ListsSheetView(model: model))
        case .floats:
            if !force, let floats, floats.result().floatStyles == document.floatStyles { return }
            let selected = floats?.selectedIndex.flatMap { floats?.rows[$0].style.name }
            let model = FloatStylesSheetModel(styles: document.floatStyles, lists: document.lists.map(\.name),
                                              paragraphStyles: document.styles.styles.filter { $0.target == .paragraph }.map(\.name))
            if let selected, let row = model.rows.first(where: { $0.style.name == selected }) { model.selection = row.id }
            floats = model
            install(tab, model, FloatStylesSheetView(model: model))
        case .rules:
            if !force, let rules, rules.result().rules == document.rules { return }
            let selected = rules?.selectedIndex
            let model = RulesSheetModel(rules: document.rules, styles: document.styles)
            if let selected, model.rows.indices.contains(selected) { model.selection = model.rows[selected].id }
            rules = model
            install(tab, model, RulesSheetView(model: model))
        case .pages:
            if !force, let pageTypes, pageTypes.result().types == document.pageTypes { return }
            let selected = pageTypes?.selectedIndex.flatMap { pageTypes?.rows[$0].type.name }
            let model = PageTypesSheetModel(types: document.pageTypes, defaultSetup: document.pageSetup)
            if let selected, let row = model.rows.first(where: { $0.type.name == selected }) { model.selection = row.id }
            pageTypes = model
            install(tab, model, PageTypesSheetView(model: model))
        case .tables:
            if !force, let tableStyles, tableStyles.result().styles == document.tableStyles { return }
            let selected = tableStyles?.selectedIndex.flatMap { tableStyles?.rows[$0].style.name }
            let model = TableStylesSheetModel(styles: document.tableStyles)
            if let selected, let row = model.rows.first(where: { $0.style.name == selected }) { model.selection = row.id }
            tableStyles = model
            install(tab, model, TableStylesSheetView(model: model))
        }
    }

    private func install<Model: ObservableObject, Content: View>(_ tab: Tab, _ model: Model, _ root: Content)
        where Model.ObjectWillChangePublisher == ObservableObjectPublisher {
        let host = NSHostingView(rootView: root.themed())
        // Come l'ispettore: il contenuto non detta le misure alla finestra.
        host.sizingOptions = []
        hosts[tab] = host
        watchers[tab] = model.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.changed(tab) }
        }
        if self.tab == tab { place(host) }
    }

    private func changed(_ tab: Tab) {
        guard !isAdjusting else { return }
        pending[tab]?.invalidate()
        // Un timer del ciclo degli eventi, non un blocco della coda principale: scatta anche mentre il ciclo gira dentro
        // un altro blocco (come nelle prove), e anche durante un trascinamento.
        let timer = Timer(timeInterval: Self.pause, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pending[tab] = nil
                self?.apply(tab)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pending[tab] = timer
    }

    /// Porta al documento ciò che dice la scheda, se è valido; poi lo stato della scheda diventa la nuova base.
    private func apply(_ tab: Tab) {
        isAdjusting = true
        defer { isAdjusting = false }
        switch tab {
        case .inspector, .styles: return
        case .lists:
            guard let lists, lists.problem == nil else { return }
            if applyLists?(lists.result()) == true { lists.markApplied() }
        case .floats:
            guard let floats, floats.problem == nil else { return }
            if applyFloats?(floats.result()) == true { floats.markApplied() }
        case .rules:
            guard let rules, rules.problem == nil else { return }
            let result = rules.result()
            // Gli stili predefiniti aggiunti ora fanno parte del documento: la scheda li deve conoscere come tali.
            if applyRules?(result) == true, !result.addedStyles.isEmpty { reload(.rules, force: true) }
        case .pages:
            guard let pageTypes, pageTypes.problem == nil else { return }
            if applyPageTypes?(pageTypes.result()) == true { pageTypes.markApplied() }
        case .tables:
            guard let tableStyles, tableStyles.problem == nil else { return }
            if applyTableStyles?(tableStyles.result()) == true { tableStyles.markApplied() }
        }
    }
}

// MARK: - La scheda Stili

/// Lo stato della scheda Stili: gli stili del documento, quello scelto, e il modulo delle sue proprietà (un ispettore
/// in modalità stile). Le modifiche vanno al documento subito, attraverso le chiamate qui sotto.
@MainActor
final class StylesTabModel: ObservableObject {
    @Published var sheet = StyleSheet()
    @Published var selection: String? {
        didSet {
            guard selection != oldValue else { return }
            nameDraft = selection ?? ""
            onSelect?(selection)
        }
    }
    @Published var nameDraft = ""
    let inspector: InspectorModel

    var onNew: ((StyleTarget) -> Void)?
    var onDuplicate: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onRename: ((String, String) -> Void)?
    var onParent: ((String, String?) -> Void)?
    var onOpensSection: ((String, String?) -> Void)?
    /// Il livello di paragrafazione di uno stile: `nil` come lo stile di base, 0 nessuno.
    var onOutlineLevel: ((String, Int?) -> Void)?
    var onSelect: ((String?) -> Void)?

    init(inspector: InspectorModel) {
        self.inspector = inspector
    }

    var selected: NamedStyle? { selection.flatMap(sheet.style(named:)) }

    /// Gli stili di una specie in albero: ciascuno sotto quello su cui si basa, nell'ordine del documento.
    func rows(_ target: StyleTarget) -> [(name: String, depth: Int)] {
        let ofTarget = sheet.styles.filter { $0.target == target }
        let names = Set(ofTarget.map(\.name))
        var result: [(String, Int)] = []
        func add(_ style: NamedStyle, depth: Int) {
            guard !result.contains(where: { $0.0 == style.name }) else { return }
            result.append((style.name, depth))
            for child in ofTarget where child.basedOn == style.name { add(child, depth: depth + 1) }
        }
        for style in ofTarget where style.basedOn.map({ !names.contains($0) }) ?? true { add(style, depth: 0) }
        // Ciò che resta fuori (un giro nei dati) si mostra comunque, in fondo.
        for style in ofTarget where !result.contains(where: { $0.0 == style.name }) { add(style, depth: 0) }
        return result
    }

    /// Che cosa non va nel nome che si sta scrivendo; `nil` se va bene.
    var renameProblem: String? {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard let selection, name != selection else { return nil }
        if name.isEmpty { return "Lo stile ha bisogno di un nome." }
        if sheet.style(named: name) != nil { return "C'è già uno stile «\(name)»." }
        return nil
    }

    func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard let selection, name != selection, renameProblem == nil else { return }
        onRename?(selection, name)
    }

    static func title(_ target: StyleTarget) -> String {
        switch target {
        case .paragraph: "Paragrafo"
        case .word: "Parola"
        case .character: "Carattere"
        }
    }
}

struct StylesTabView: View {
    @ObservedObject var model: StylesTabModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach([StyleTarget.paragraph, .word, .character], id: \.self) { target in
                    Section(StylesTabModel.title(target)) {
                        ForEach(model.rows(target), id: \.name) { row in
                            Text(row.name).padding(.leading, CGFloat(row.depth) * 14).tag(row.name)
                        }
                    }
                }
            }
            .frame(height: 220)
            HStack(spacing: 4) {
                Menu {
                    Button("Stile di paragrafo") { model.onNew?(.paragraph) }
                    Button("Stile di parola") { model.onNew?(.word) }
                    Button("Stile di carattere") { model.onNew?(.character) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Uno stile nuovo (basato su quello scelto, se è della stessa specie)")
                Button { model.selection.map { model.onDuplicate?($0) } } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(model.selection == nil)
                    .help("Duplica lo stile scelto")
                Button { model.selection.map { model.onRemove?($0) } } label: { Image(systemName: "minus") }
                    .disabled(model.selection == nil)
                    .help("Togli lo stile: il testo passa allo stile su cui si basava")
                Spacer()
            }
            .padding(.horizontal, 10)
            if let style = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Nome").frame(width: 118, alignment: .leading)
                            TextField("", text: $model.nameDraft)
                                .focused($nameFocused)
                                .onSubmit { model.commitName() }
                                .onChange(of: nameFocused) { _, focused in if !focused { model.commitName() } }
                        }
                        if let problem = model.renameProblem {
                            Text(problem).font(.caption).foregroundStyle(.red)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Basato su").frame(width: 118, alignment: .leading)
                            Picker("", selection: Binding(get: { style.basedOn }, set: { model.onParent?(style.name, $0) })) {
                                Text("Nessuno").tag(String?.none)
                                ForEach(model.sheet.possibleParents(of: style.name), id: \.self) { Text($0).tag(Optional($0)) }
                            }
                            .labelsHidden()
                        }
                        if style.target == .paragraph {
                            outlineLevelRow(style)
                            opensSectionRow(style)
                        }
                        Divider()
                        InspectorView(model: model.inspector, rowsOnly: true)
                            .help("Stile di \(StylesTabModel.title(style.target).lowercased()): le modifiche valgono per tutto il testo che lo usa, tranne ciò che è dato a mano.")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Nessuno stile scelto.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 8)
    }
}

extension StylesTabView {
    /// «Livello»: la posizione nella paragrafazione dei titoli che hanno questo stile; ereditato, nessuno, o 1–9.
    @ViewBuilder func outlineLevelRow(_ style: NamedStyle) -> some View {
        let own = style.values.outlineLevel
        let inherited = style.basedOn.flatMap { model.sheet.resolveParagraph(styleName: $0).outlineLevel }
        HStack(alignment: .firstTextBaseline) {
            Text("Livello").frame(width: 118, alignment: .leading)
            Picker("", selection: Binding(get: { own ?? (style.basedOn == nil ? 0 : nil) }, set: { model.onOutlineLevel?(style.name, $0) })) {
                if style.basedOn != nil { Text(inherited.map { "Come lo stile di base (\($0))" } ?? "Come lo stile di base (nessuno)").tag(Int?.none) }
                Text("Nessuno").tag(Optional(0))
                ForEach(1...9, id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
            .labelsHidden()
        }
    }

    /// «Apre una sezione»: il ruolo della sezione che nasce dando lo stile a un paragrafo; ereditato, nessuno, o un ruolo.
    @ViewBuilder func opensSectionRow(_ style: NamedStyle) -> some View {
        let own = style.values.opensSection
        let inherited = style.basedOn.flatMap { model.sheet.values(of: $0).opensSection }.flatMap { $0.isEmpty ? nil : $0 }
        let roles = Typesetting.Section.Role.builtIn + [own].compactMap { $0 }.filter { !$0.isEmpty && !Typesetting.Section.Role.builtIn.contains($0) }
        HStack(alignment: .firstTextBaseline) {
            Text("Apre una sezione").frame(width: 118, alignment: .leading)
            Picker("", selection: Binding(get: { own ?? (style.basedOn == nil ? "" : nil) }, set: { model.onOpensSection?(style.name, $0) })) {
                if style.basedOn != nil { Text(inherited.map { "Come lo stile di base (\($0))" } ?? "Come lo stile di base (no)").tag(String?.none) }
                Text("No").tag(Optional(""))
                ForEach(roles, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .labelsHidden()
        }
        .help("Il paragrafo che riceve questo stile diventa il titolo di una sezione del ruolo scelto. La sezione resta anche se lo stile cambia.")
    }
}
