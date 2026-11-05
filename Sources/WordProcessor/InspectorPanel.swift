import AppKit
import SwiftUI
import Typesetting

/// L'oggetto di cui l'ispettore mostra le proprietà, scelto nel percorso sotto la barra.
enum InspectedObject: String, CaseIterable {
    case document, section, page, table, cell, paragraph, line, word, character

    var level: StyleTarget? {
        switch self {
        case .document, .section, .page, .table, .cell, .line: nil
        case .paragraph: .paragraph
        case .word: .word
        case .character: .character
        }
    }

    var title: String {
        switch self {
        case .document: "Documento"
        case .section: "Sezione"
        case .page: "Pagina"
        case .table: "Tabella"
        case .cell: "Cella"
        case .paragraph: "Paragrafo"
        case .line: "Riga"
        case .word: "Parola"
        case .character: "Carattere"
        }
    }
}

/// Dove va un valore cambiato nell'ispettore: solo nel testo scelto, o nello stile (e quindi in tutto il testo
/// che lo usa).
enum InspectorEditMode {
    case here, style
}

/// Lo stato dell'ispettore. L'editor lo riempie a ogni cambio di selezione e riceve le modifiche dalle chiusure.
@MainActor
final class InspectorModel: ObservableObject {
    @Published var object: InspectedObject = .paragraph
    /// Le proprietà dell'oggetto scelto, nel punto della selezione.
    @Published var values: [InspectedValue] = []
    /// Per ogni proprietà, lo stile che riceverebbe il valore «nello stile».
    @Published var receivers: [InspectorProperty: String] = [:]
    @Published var formulaDefinitions: [InspectorProperty: StyleFormulaDefinition] = [:]
    var openFormula: ((String) -> Void)?
    var replaceFormula: ((InspectorProperty) -> Void)?

    func formulaIsLocked(_ property: InspectorProperty) -> Bool {
        (editsStyle || mode(property) == .style) && formulaDefinitions[property]?.isCalculated == true
    }

    func formulaSummary(_ property: InspectorProperty) -> String? {
        formulaDefinitions[property].map { definition in
            if let calculation = definition.calculation { return calculation }
            return definition.formulas.map { formula in
                let op = formula.operation
                let argument: String
                switch op.argument {
                case .boolean(let enabled): argument = enabled ? "Sì" : "No"
                case .integer(let count): argument = String(count)
                case .text(let value): argument = value.isEmpty ? "Nessuna" : value
                case .styleName(let name): argument = name ?? "Stesso stile"
                case .pageStart(let spacing):
                    switch spacing { case .disabled: argument = "Disattivata"; case .distance(let points): argument = points.formatted() + " pt" }
                case .font(let role): argument = roleTitle(role)
                case .face(let name), .family(let name): argument = name
                case .length(let value, let unit): argument = value.formatted() + " " + unit.rawValue
                case .language(let value): argument = value ?? "Lingua documento"
                case .color(let value): argument = value ?? "Automatico"
                case .smallCaps(let mode): argument = mode.rawValue
                case .hyphenates(let enabled): argument = enabled ? "Attiva" : "Disattivata"
                case .alignment(let alignment): argument = alignment.rawValue
                }
                return op.predicate.title + " · " + op.property.title + " · " + argument + (formula.when.isAlways ? "" : " · " + formula.when.summary)
            }.joined(separator: "; ")
        }
    }
    /// Lo stile dell'oggetto scelto, se ne ha uno.
    @Published var styleName: String?
    @Published var modes: [InspectorProperty: InspectorEditMode] = [:]
    /// Le proprietà dinamiche dell'oggetto scelto: le calcola la composizione, non si impostano.
    @Published var facts: [Fact] = []
    /// Per il carattere: le funzioni, gli assi e il corpo ottico, ciascuno con la sua provenienza.
    @Published var details: [InspectedDetail] = []
    /// Lo stile che riceverebbe un dettaglio «nello stile», e se lo può ricevere (non se il testo ha un altro font).
    @Published var detailReceiver: String?
    @Published var detailsMovable = false
    var resetDetail: ((FontDetail) -> Void)?
    var moveDetailToStyle: ((FontDetail) -> Void)?

    struct Fact: Hashable {
        var title: String
        var value: String
    }

    // Scelte offerte.
    @Published var families: [String] = []
    /// Se il menu delle famiglie raggruppa in sottomenu quelle con la stessa prima parola (Impostazioni › Fonts).
    @Published var groupsFamilies = false
    @Published var faces: [FaceChoice] = []
    @Published var languages: [LanguageChoice] = []
    @Published var lists: [String] = []

    struct FaceChoice: Hashable {
        var name: String
        var title: String
    }

    struct LanguageChoice: Hashable {
        var code: String
        var name: String
    }

    // Il documento.
    @Published var documentLanguage: String?
    @Published var hyphenates = true
    @Published var usesOpticalMargins = true
    @Published var appliesFontTracking = true
    @Published var glyphExpansionLimit = LayoutOptions.defaultGlyphExpansionLimit
    @Published var noteList: String?
    /// La sezione scelta nel percorso: che cosa è e che cosa contiene; `nil` se il cursore non è in una sezione.
    @Published var section: SectionInfo?
    var setSectionRole: ((String) -> Void)?
    var setSectionStart: ((SectionStart) -> Void)?
    var setSectionPageTypes: ((SectionPageTypes) -> Void)?
    var setSectionPageNumbering: ((String?) -> Void)?
    var moveSection: ((Int) -> Void)?
    var removeSection: (() -> Void)?

    struct SectionInfo: Equatable {
        var role: String
        /// Le prime parole del titolo, o «senza titolo».
        var title: String
        var depth: Int
        var paragraphs: Int
        var sections: Int
        var canMoveInside: Bool
        var canMoveOutside: Bool
        var start: SectionStart = .continuous
        var pageTypes = SectionPageTypes()
        /// I tipi di pagina del documento, da scegliere.
        var typeNames: [String] = []
        var pageNumbering: String?
        /// Le Liste del documento, per i numeri di pagina.
        var listNames: [String] = []
    }

    /// La tabella del cursore: le sue misure e la cella del cursore; `nil` se il cursore non è in una tabella.
    @Published var table: TableInfo?
    var setTableHeaderRows: ((Int) -> Void)?
    var tableCommand: ((TableCommand) -> Void)?
    var setTableStyle: ((String?) -> Void)?
    var setTableFloat: ((String?) -> Void)?
    var changeTable: ((TableValueChange) -> Void)?
    /// La cella del cursore e il suo aspetto; `nil` fuori dalle tabelle.
    @Published var cell: CellInfo?
    var changeCell: ((CellValueChange) -> Void)?
    var splitCell: (() -> Void)?

    struct TableInfo: Equatable {
        var rows: Int
        var columns: Int
        var headerRows: Int
        /// La cella del cursore, contando da 1.
        var row: Int
        var column: Int
        var style: String? = nil
        var styleNames: [String] = []
        /// Ciò che la tabella dice per sé, e l'aspetto che ne risulta.
        var values = TableValues()
        var resolved = TableValues.initial
        /// Lo stile di flottante della tabella, e quelli tra cui scegliere (gli stili di figura, più «Tabella» se manca).
        var floatStyle: String? = nil
        var floatChoices: [String] = []
    }

    struct CellInfo: Equatable {
        /// Contando da 1.
        var row: Int
        var column: Int
        var values: CellValues
        /// Ciò che la cella prende dalla tabella, se non dice altro.
        var tableBackground: String
        var tableAlignment: CellVerticalAlignment
        var tablePadding: CellInsets
        var tableRuleWidth: Double
        /// Quante colonne e righe copre (più di una se è unita).
        var columnSpan = 1
        var rowSpan = 1
    }

    /// La pagina del documento (formato, margini, pagine affacciate) e chi la cambia.
    @Published var pageSetup = PageSetup.a4
    /// Il tipo della pagina del cursore: è quello che il modulo cambia (`nil` per il predefinito).
    @Published var pageTypeName: String?
    var setPageSetup: ((PageSetup) -> Void)?

    /// Graphite: se la libreria è installata.
    @Published var graphiteAvailable = Graphite.isAvailable

    /// Il font che il testo scelto ha davvero (quello mostrato in «Faccia»): può non essere quello chiesto, se quel
    /// font non ha i caratteri del testo e il programma ne ha messo un altro.
    private var shownFontName: String? { values.first { $0.property == .face }?.value.fontName }

    /// Vero se il font mostrato ha le tabelle Graphite. Si ricava dai valori mostrati, così non resta indietro.
    var fontHasGraphite: Bool { shownFontName.map(Self.hasGraphiteTables) ?? false }

    private static var graphiteTables: [String: Bool] = [:]
    private static func hasGraphiteTables(_ name: String) -> Bool {
        if let known = graphiteTables[name] { return known }
        let result = Graphite.hasTables(CTFontCreateWithName(name as CFString, 12, nil))
        graphiteTables[name] = result
        return result
    }

    /// Perché il testo che chiede Graphite resta a Core Text; `nil` se Graphite lo compone davvero.
    var graphiteProblem: String? {
        if !graphiteAvailable { return "graphite2 non è installata su questo Mac: si compone con Core Text" }
        if !fontHasGraphite {
            let name = shownFontName.map { CTFontCopyDisplayName(CTFontCreateWithName($0 as CFString, 12, nil)) as String }
            return "\(name.map { "«\($0)»" } ?? "Questo font") non ha tabelle Graphite: si compone con Core Text"
        }
        return nil
    }

    /// Il pannello delle funzioni del font, che è il gruppo finale del carattere.
    let features: FeaturePanelModel

    /// Vero per il modulo di uno stile nella scheda Stili: i valori sono quelli dello stile, non del testo.
    var editsStyle = false

    var set: ((InspectorProperty, StyleValues) -> Void)?
    var reset: ((InspectorProperty) -> Void)?
    var moveToStyle: ((InspectorProperty) -> Void)?
    var setDocumentLanguage: ((String?) -> Void)?
    var setHyphenates: ((Bool) -> Void)?
    var setGlyphExpansionLimit: ((Double) -> Void)?
    var glyphExpansionDragging: ((Bool) -> Void)?
    var setNoteList: ((String?) -> Void)?
    /// Crea uno stile dell'oggetto scelto con l'aspetto che ha qui.
    var createStyle: (() -> Void)?
    /// Crea una regola che trovi i pezzi di testo come quello selezionato.
    var createRule: (() -> Void)?

    init(features: FeaturePanelModel) {
        self.features = features
    }

    func mode(_ property: InspectorProperty) -> InspectorEditMode { modes[property] ?? .here }

    /// Il testo sotto un valore: da dove viene.
    func sourceText(_ value: InspectedValue) -> String {
        var text = switch value.source {
        case .own: editsStyle ? "Fissato in questo stile" : "Dato qui"
        case .style(let name): editsStyle ? "Da «\(name)», su cui si basa" : "Dallo stile «\(name)»"
        case .document: "Dal documento"
        case .rule(let summary): "Dalla regola: \(summary)"
        }
        if value.isMixed { text += " · la selezione ha valori diversi" }
        return text
    }

    func change(_ property: InspectorProperty, _ build: (inout StyleValues) -> Void) {
        guard !formulaIsLocked(property) else { return }
        var values = StyleValues()
        build(&values)
        set?(property, values)
    }

    /// L'ispettore come vista AppKit. I tipi di SwiftUI restano nei file dei pannelli: nel resto dell'app i suoi
    /// `Document` e `TextSelection` si confonderebbero con quelli del nostro motore.
    /// La vista AppKit dell'ispettore. Non comunica alla finestra le misure del suo contenuto: altrimenti l'altezza del
    /// testo seguirebbe quella dell'oggetto scelto (con «Parola», poche righe, metà finestra restava vuota).
    func makeHostingView() -> NSView { InspectorHostingView(model: self) }
}

/// L'evento dei monitor AppKit arriva e viene consumato sul thread principale; il contenitore dichiara questo passaggio
/// al controllore di concorrenza senza fingere che NSEvent sia Sendable.
private struct InspectorMonitorEvent: @unchecked Sendable { let value: NSEvent }

/// Tiene la navigazione dei campi SwiftUI: Tab li percorre nell'ordine visivo, Maiusc-Tab al contrario.
@MainActor
final class InspectorHostingView: NSView {
    private let host: NSView
    private var focusMonitor: Any?

    init(model: InspectorModel) {
        let host = NSHostingView(rootView: InspectorView(model: model).themed())
        host.sizingOptions = []
        self.host = host
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor), host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non è usato") }

    isolated deinit { if let focusMonitor { NSEvent.removeMonitor(focusMonitor) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
            focusMonitor = nil
        } else if focusMonitor == nil {
            // SwiftUI non lascia che la normale catena nextKeyView gestisca Tab nei suoi campi.
            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let event = InspectorMonitorEvent(value: event)
                let handled = MainActor.assumeIsolated { self?.moveFocus(with: event.value) ?? false }
                return handled ? nil : event.value
            }
        }
    }

    private func editableFields() -> [NSTextField] {
        var found: [(field: NSTextField, rect: NSRect)] = []
        func collect(_ view: NSView) {
            if let field = view as? NSTextField, field.isEditable, field.isEnabled, !field.isHiddenOrHasHiddenAncestor,
               !field.refusesFirstResponder {
                found.append((field, field.convert(field.bounds, to: self)))
            }
            for child in view.subviews { collect(child) }
        }
        collect(self)
        return found.sorted { left, right in
            if abs(left.rect.midY - right.rect.midY) > 6 { return left.rect.midY > right.rect.midY }
            return left.rect.minX < right.rect.minX
        }.map(\.field)
    }

    private func moveFocus(with event: NSEvent) -> Bool {
        guard event.keyCode == 48, let window,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        let responder = window.firstResponder
        let field = responder as? NSTextField ?? (responder as? NSTextView)?.delegate as? NSTextField
        guard let field, field.isDescendant(of: self) else { return false }
        let fields = editableFields()
        guard let index = fields.firstIndex(where: { $0 === field }) else { return false }
        let forward = !event.modifierFlags.contains(.shift)
        let next = fields[(index + (forward ? 1 : fields.count - 1)) % fields.count]
        // Come Invio: prima conferma il contenuto, poi passa al campo. Le misure differiscono il commit di un giro,
        // così il clic o il cambio di focus non può far sparire il controllo sotto il puntatore.
        if let action = field.action { _ = NSApp.sendAction(action, to: field.target, from: field) }
        window.makeFirstResponder(next)
        next.selectText(nil)
        return true
    }
}

extension View {
    /// I controlli di SwiftUI (caselle, menu, pulsanti) nell'azzurro del disegno invece che nel colore d'accento del sistema.
    func themed() -> some View { tint(Color(nsColor: Theme.accent)) }

    /// Un campo largo `width` in un foglio; nella scheda del pannello al più `width`, perché possa stringersi.
    @ViewBuilder func fieldWidth(_ width: CGFloat, embedded: Bool) -> some View {
        if embedded { frame(minWidth: 40, maxWidth: width) } else { frame(width: width) }
    }

    /// Il modulo di una scheda del pannello (a gruppi, largo quanto il pannello) o di un foglio (largo `width`).
    @ViewBuilder func definitionForm(embedded: Bool, width: CGFloat) -> some View {
        if embedded {
            formStyle(.grouped).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            frame(width: width, alignment: .leading)
        }
    }
}

struct InspectorView: View {
    /// La larghezza sotto la quale l'ispettore non scende: quella in cui stanno le righe più larghe del carattere
    /// («Posizione verticale» con il suo menu, 330 punti) più la barra di scorrimento, quando è sempre visibile.
    static let minimumWidth: CGFloat = 360

    @ObservedObject var model: InspectorModel
    /// Solo le righe delle proprietà, senza intestazione né scorrimento proprio: il modulo di uno stile.
    var rowsOnly = false

    var body: some View {
        if rowsOnly {
            VStack(alignment: .leading, spacing: 14) { rows }
        } else {
            panelBody
        }
    }

    private var panelBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                switch model.object {
                case .document:
                    documentRows
                    factRows
                case .page:
                    Text(model.pageTypeName.map { "Tipo «\($0)»" } ?? "Tipo predefinito")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .help(model.pageTypeName == nil ? "Vale per le pagine senza un tipo proprio." : "Le modifiche valgono per tutte le pagine di questo tipo.")
                    PageSetupForm(setup: model.pageSetup) { transform in
                        var page = model.pageSetup
                        transform(&page)
                        if let page = PageSetupForm.checked(page) { model.setPageSetup?(page) }
                    }
                    factRows
                case .section:
                    if let section = model.section {
                        SectionForm(info: section, setRole: { model.setSectionRole?($0) }, setStart: { model.setSectionStart?($0) },
                                    setPageTypes: { model.setSectionPageTypes?($0) }, setPageNumbering: { model.setSectionPageNumbering?($0) },
                                    move: { model.moveSection?($0) }, remove: { model.removeSection?() })
                    } else {
                        Text("Il cursore non è in una sezione. Una sezione si apre dal menu Inserisci.").foregroundStyle(.secondary)
                    }
                    factRows
                case .table:
                    if let table = model.table {
                        TableForm(info: table, setHeaderRows: { model.setTableHeaderRows?($0) }, setStyle: { model.setTableStyle?($0) },
                                  setFloat: { model.setTableFloat?($0) },
                                  change: { model.changeTable?($0) }, command: { model.tableCommand?($0) })
                    } else {
                        Text("Il cursore non è in una tabella. Una tabella si inserisce dal menu Inserisci.").foregroundStyle(.secondary)
                    }
                    factRows
                case .cell:
                    if let cell = model.cell {
                        CellForm(info: cell, change: { model.changeCell?($0) }, split: { model.splitCell?() })
                    } else {
                        Text("Il cursore non è in una tabella.").foregroundStyle(.secondary)
                    }
                case .line:
                    factRows
                case .character:
                    rows
                    detailRows
                    factRows
                    Divider()
                    FeaturePanelView(model: model.features, embedded: true)
                default:
                    rows
                    factRows
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: Self.minimumWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.object.title).font(.title3.bold())
            if model.object.level != nil {
                Text(model.styleName.map { "Stile «\($0)»" } ?? "Senza stile").foregroundStyle(.secondary)
                if !model.editsStyle {
                    HStack(spacing: 8) {
                        Button { model.createStyle?() } label: { Image(systemName: "paintbrush") }
                            .help("Crea uno stile con l'aspetto di questo \(model.object.title.lowercased())")
                            .accessibilityLabel("Crea uno stile da qui")
                        if model.object == .word || model.object == .character {
                            Button { model.createRule?() } label: { Image(systemName: "wand.and.rays") }
                                .help("Crea una regola per il testo come quello selezionato")
                                .accessibilityLabel("Crea una regola da qui")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
        }
    }

    /// Funzioni, assi e corpo ottico: si scelgono nel pannello delle funzioni e con i cursori; qui si vede da dove
    /// vengono, e ciascuno si toglie o si porta nello stile da solo.
    @ViewBuilder private var detailRows: some View {
        if !model.details.isEmpty {
            Divider()
            Text("Funzioni e assi").font(.headline)
                .help("Ciascuno si toglie o si porta nello stile da solo, senza toccare gli altri.")
            ForEach(model.details) { detail in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(detail.title).frame(width: 118, alignment: .leading).lineLimit(2)
                        Text(detail.value).frame(maxWidth: .infinity, alignment: .leading)
                        detailMenu(detail)
                    }
                    Text(detailSourceText(detail)).font(.caption)
                        .foregroundStyle(sourceColor(detail.source))
                        .padding(.leading, 122)
                }
            }
        }
    }

    private func detailSourceText(_ detail: InspectedDetail) -> String {
        var text = switch detail.source {
        case .own: "Dato qui · nello stile: \(detail.inherited.lowercased())"
        case .style(let name): "Dallo stile «\(name)»"
        case .document: "Dal documento"
        case .rule(let summary): "Dalla regola: \(summary)"
        }
        if detail.isMixed { text += " · la selezione ha valori diversi" }
        return text
    }

    private func detailMenu(_ detail: InspectedDetail) -> some View {
        let receiver = model.detailReceiver
        return Menu {
            Button(receiver.map { "Porta questo valore nello stile «\($0)»" } ?? "Porta questo valore nello stile") { model.moveDetailToStyle?(detail.detail) }
                .disabled(receiver == nil || !model.detailsMovable || detail.source != .own)
            Button("Torna al valore ereditato") { model.resetDetail?(detail.detail) }
                .disabled(detail.source != .own)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.detailsMovable || receiver == nil ? "Il valore dato qui"
              : "Il testo ha un font diverso da quello dello stile: porta prima nello stile la famiglia")
    }

    /// Le proprietà dinamiche: si leggono soltanto.
    @ViewBuilder private var factRows: some View {
        if !model.facts.isEmpty {
            Divider()
            Text("Dalla composizione").font(.headline)
                .help("Valori calcolati componendo le pagine: cambiano mentre si scrive e non si impostano.")
            ForEach(model.facts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline) {
                    Text(fact.title).frame(width: 118, alignment: .leading)
                    Text(fact.value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        if model.values.isEmpty {
            Text("Il documento è vuoto.").foregroundStyle(.secondary)
        }
        ForEach(model.values, id: \.property) { value in
            row(value)
        }
    }

    private func row(_ value: InspectedValue) -> some View {
        // I filetti hanno un riquadro per ciascuno, con più campi: stanno sotto il titolo, a tutta larghezza.
        let wide = value.property == .decorations
        return VStack(alignment: .leading, spacing: 3) {
            if wide {
                HStack(alignment: .firstTextBaseline) {
                    Text(value.property.title)
                    Spacer()
                    menu(value)
                }
                control(value).disabled(model.formulaIsLocked(value.property))
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(value.property.title).frame(width: 118, alignment: .leading)
                    control(value).disabled(model.formulaIsLocked(value.property)).frame(maxWidth: .infinity, alignment: .leading)
                    menu(value)
                }
            }
            if let summary = model.formulaSummary(value.property), let definition = model.formulaDefinitions[value.property] {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary).font(.caption).foregroundStyle(Color(nsColor: Theme.accent))
                    Button("Bacheca") { model.openFormula?(definition.owner) }.font(.caption)
                }.padding(.leading, wide ? 0 : 122)
            }
            Text(model.sourceText(value)).font(.caption)
                .foregroundStyle(sourceColor(value.source))
                .padding(.leading, wide ? 0 : 122)
        }
    }

    /// Il colore della provenienza: arancio per ciò che è dato qui, azzurro per ciò che dà una regola.
    private func sourceColor(_ source: ValueSource) -> AnyShapeStyle {
        switch source {
        case .own: AnyShapeStyle(.orange)
        case .rule: AnyShapeStyle(Color(nsColor: Theme.accent))
        default: AnyShapeStyle(.secondary)
        }
    }

    /// Il menu accanto al valore: dove vanno le modifiche, e che cosa fare del valore dato qui.
    @ViewBuilder private func menu(_ value: InspectedValue) -> some View {
        if model.editsStyle { styleMenu(value) } else { textMenu(value) }
    }

    /// Nel modulo di uno stile: togliere il valore dallo stile, che torna a ereditarlo.
    private func styleMenu(_ value: InspectedValue) -> some View {
        Menu {
            if let definition = model.formulaDefinitions[value.property] {
                Button("Apri la formula nella bacheca") { model.openFormula?(definition.owner) }
                if definition.isCalculated {
                    Button("Usa il risultato come valore fisso") { model.replaceFormula?(value.property) }
                }
                Divider()
            }
            Button("Togli da questo stile (lo eredita)") { model.reset?(value.property) }
                .disabled(value.source != .own)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Il valore di questo stile")
    }

    private func textMenu(_ value: InspectedValue) -> some View {
        let property = value.property
        let receiver = model.receivers[property]
        return Menu {
            Toggle("Cambia solo qui", isOn: Binding(get: { model.mode(property) == .here }, set: { if $0 { model.modes[property] = .here } }))
            Toggle(receiver.map { "Cambia nello stile «\($0)»" } ?? "Cambia nello stile (il testo non ne ha)",
                   isOn: Binding(get: { model.mode(property) == .style }, set: { if $0 { model.modes[property] = .style } }))
                .disabled(receiver == nil)
            Divider()
            if let definition = model.formulaDefinitions[property] {
                Button("Apri la formula nella bacheca") { model.openFormula?(definition.owner) }
                if definition.isCalculated {
                    Button("Sostituisci la formula nello stile con il valore qui") { model.replaceFormula?(property) }
                }
                Divider()
            }
            Button(receiver.map { (model.formulaDefinitions[property]?.isCalculated == true ? "Sostituisci la formula con questo valore in «\($0)»" : "Porta questo valore nello stile «\($0)»") } ?? "Porta questo valore nello stile") { model.moveToStyle?(property) }
                .disabled(receiver == nil || value.source != .own)
            Button("Torna al valore ereditato") { model.reset?(property) }
                .disabled(value.source != .own)
        } label: {
            Image(systemName: model.mode(property) == .style ? "paintbrush" : "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.mode(property) == .style ? "Le modifiche vanno nello stile" : "Le modifiche valgono solo qui")
    }

    /// Il menu delle famiglie con i sottomenu: «Noto ▸ Noto Sans, Noto Serif…». La famiglia corrente ha il segno di spunta.
    private func groupedFamilyMenu(current: String) -> some View {
        let choose: (String) -> Void = { family in model.change(.family) { $0.family = family } }
        func row(_ family: String) -> some View {
            Button { choose(family) } label: {
                if family == current { Label(family, systemImage: "checkmark") } else { Text(family) }
            }
        }
        return Menu(current.isEmpty ? "—" : current) {
            ForEach(Array(FontFamilyMenu.entries(model.families).enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .family(let family): row(family)
                case .group(let word, let members):
                    Menu(word) { ForEach(members, id: \.self) { row($0) } }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func control(_ value: InspectedValue) -> some View {
        let v = value.value
        switch value.property {
        case .family:
            if model.groupsFamilies {
                groupedFamilyMenu(current: v.family ?? "")
            } else {
                Picker("", selection: Binding(get: { v.family ?? "" }, set: { family in model.change(.family) { $0.family = family } })) {
                    if let family = v.family, !model.families.contains(family) { Text(family).tag(family) }
                    ForEach(model.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        case .face:
            Picker("", selection: Binding(get: { v.fontName ?? "" }, set: { name in model.change(.face) { $0.fontName = name } })) {
                if let name = v.fontName, !model.faces.contains(where: { $0.name == name }) { Text(name).tag(name) }
                ForEach(model.faces, id: \.self) { Text($0.title).tag($0.name) }
            }
            .labelsHidden()
        case .size:
            number(v.size ?? 12, unit: "pt") { size in model.change(.size) { $0.size = max(1, min(size, 2000)) } }
        case .smallCaps:
            Picker("", selection: Binding(get: { v.smallCaps ?? .off }, set: { choice in model.change(.smallCaps) { $0.smallCaps = choice } })) {
                ForEach(SmallCaps.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case .decorations:
            let list = LineDecoration.decode(v.decorations ?? "") ?? []
            let commit: ([LineDecoration]) -> Void = { new in model.change(.decorations) { $0.decorations = LineDecoration.encode(new) } }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, decoration in
                    decorationEditor(decoration, set: { var copy = list; copy[index] = $0; commit(copy) },
                                     remove: { var copy = list; copy.remove(at: index); commit(copy) })
                }
                Menu(list.isEmpty ? "Aggiungi un filetto" : "Aggiungi") {
                    Button("Sottolineato") { commit(list + [.underline]) }
                    Button("Barrato") { commit(list + [.strikethrough]) }
                    Button("Soprallineato") { commit(list + [LineDecoration(position: .over)]) }
                }
                .fixedSize()
            }
        case .shaping:
            let usesGraphite = (v.graphite ?? "off") != "off"
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: Binding(
                    get: { usesGraphite ? 1 : 0 },
                    set: { choice in model.change(.shaping) { $0.graphite = choice == 1 ? (usesGraphite ? v.graphite : "on") : "off" } })) {
                    Text("Core Text").tag(0)
                    Text("Graphite").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                if usesGraphite, let problem = model.graphiteProblem {
                    Text(problem).font(.caption).foregroundStyle(Color(nsColor: Theme.warn)).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .verticalPosition:
            let position = (v.verticalPosition).flatMap(VerticalPosition.init(encoded:))
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: Binding(
                    get: { position == nil ? 0 : (position == .superscript ? 1 : (position == .subscript ? 2 : 3)) },
                    set: { choice in
                        let chosen: VerticalPosition? = [nil, .superscript, .subscript, position ?? VerticalPosition(shift: 0.3, scale: 0.7)][choice]
                        model.change(.verticalPosition) { $0.verticalPosition = chosen?.encoded ?? "" }
                    })) {
                    Text("Sulla linea di base").tag(0)
                    Text("Apice").tag(1)
                    Text("Pedice").tag(2)
                    Text("Personalizzata").tag(3)
                }
                .labelsHidden()
                if let position {
                    HStack(spacing: 6) {
                        Text("alzata").foregroundStyle(.secondary)
                        number(position.shift, unit: "em") { shift in
                            model.change(.verticalPosition) { $0.verticalPosition = VerticalPosition(shift: shift, scale: position.scale, usesFontGlyphs: position.usesFontGlyphs).encoded }
                        }
                        Text("corpo").foregroundStyle(.secondary)
                        number(position.scale, unit: "×") { scale in
                            let scale = min(max(scale, 0.2), 1)
                            model.change(.verticalPosition) { $0.verticalPosition = VerticalPosition(shift: position.shift, scale: scale, usesFontGlyphs: position.usesFontGlyphs).encoded }
                        }
                    }
                    Toggle("Glifi del font, se li ha", isOn: Binding(get: { position.usesFontGlyphs }, set: { on in
                        model.change(.verticalPosition) { $0.verticalPosition = VerticalPosition(shift: position.shift, scale: position.scale, usesFontGlyphs: on).encoded }
                    }))
                }
            }
        case .color:
            HStack {
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: (v.color).flatMap { TextStyling.color(hex: $0) } ?? .black) },
                    set: { color in model.change(.color) { $0.color = TextStyling.hex(of: NSColor(color)) ?? "" } }), supportsOpacity: false)
                    .labelsHidden()
                Button("Automatico") { model.change(.color) { $0.color = "" } }
                    .disabled((v.color ?? "").isEmpty)
            }
        case .language:
            Picker("", selection: Binding(get: { v.language ?? "" }, set: { code in model.change(.language) { $0.language = code } })) {
                Text("Quella del documento").tag("")
                ForEach(model.languages, id: \.self) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
        case .hyphenates:
            Toggle("Divide le parole a fine riga", isOn: Binding(get: { v.hyphenates ?? true }, set: { on in model.change(.hyphenates) { $0.hyphenates = on } }))
        case .alignment:
            Picker("", selection: Binding(get: { v.alignment ?? .natural }, set: { alignment in model.change(.alignment) { $0.alignment = alignment } })) {
                Text("Naturale").tag(ParagraphStyle.Alignment.natural)
                Text("A sinistra").tag(ParagraphStyle.Alignment.left)
                Text("Al centro").tag(ParagraphStyle.Alignment.center)
                Text("A destra").tag(ParagraphStyle.Alignment.right)
                Text("Giustificato").tag(ParagraphStyle.Alignment.justified)
                Text("Sulla virgola").tag(ParagraphStyle.Alignment.decimal)
            }
            .labelsHidden()
        case .leftIndent:
            measurement(v.leftIndent ?? 0, allowsNegative: true) { x in model.change(.leftIndent) { $0.leftIndent = x } }
        case .rightIndent:
            measurement(v.rightIndent ?? 0, allowsNegative: true) { x in model.change(.rightIndent) { $0.rightIndent = x } }
        case .firstLineIndent:
            measurement(v.firstLineIndent ?? 0, allowsNegative: true) { x in model.change(.firstLineIndent) { $0.firstLineIndent = x } }
        case .spaceBefore:
            measurement(v.spaceBefore ?? 0) { x in model.change(.spaceBefore) { $0.spaceBefore = x } }
        case .spaceAfter:
            measurement(v.spaceAfter ?? 0) { x in model.change(.spaceAfter) { $0.spaceAfter = x } }
        case .lineHeightMultiple:
            number(v.lineHeightMultiple ?? 0, unit: "×") { x in model.change(.lineHeightMultiple) { $0.lineHeightMultiple = max(0, x) } }
                .help("Quante volte l'altezza della riga; 0 vuol dire l'altezza naturale del font")
        case .lineSpacing:
            measurement(v.lineSpacing ?? 0) { x in model.change(.lineSpacing) { $0.lineSpacing = x } }
        case .openingDistance:
            // Una misura di pagina: in millimetri come i margini, e accetta qualsiasi unità.
            LengthField(points: CGFloat(v.openingDistance ?? 0)) { x in model.change(.openingDistance) { $0.openingDistance = Double(x) } }
                .help("Dal margine superiore, solo per il paragrafo che apre una sequenza di pagine: il titolo di una sezione che comincia su una pagina nuova, o il primo del documento")
        case .keepWithNext:
            Toggle("", isOn: Binding(get: { v.keeping.withNext ?? false }, set: { on in model.change(.keepWithNext) { $0.keeping.withNext = on } }))
                .labelsHidden()
        case .keepTogether:
            Toggle("", isOn: Binding(get: { v.keeping.together ?? false }, set: { on in model.change(.keepTogether) { $0.keeping.together = on } }))
                .labelsHidden()
        case .orphanLines:
            linesPicker(v.keeping.linesAtEnd ?? 1) { lines in model.change(.orphanLines) { $0.keeping.linesAtEnd = lines } }
        case .widowLines:
            linesPicker(v.keeping.linesAtStart ?? 1) { lines in model.change(.widowLines) { $0.keeping.linesAtStart = lines } }
        case .list:
            Picker("", selection: Binding(get: { v.listName ?? "" }, set: { name in model.change(.list) { $0.listName = name } })) {
                Text("Nessuna").tag("")
                if let name = v.listName, !name.isEmpty, !model.lists.contains(name) { Text(name).tag(name) }
                ForEach(model.lists, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    /// Le righe minime della tenuta: nessuna (1) o da 2 a 9.
    private func linesPicker(_ lines: Int, set: @escaping (Int) -> Void) -> some View {
        Picker("", selection: Binding(get: { lines }, set: set)) {
            Text("nessuno").tag(1)
            ForEach(Array(LineKeeping.lineRange.dropFirst()), id: \.self) { Text("\($0)").tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// Un filetto: dove sta, che riga è, distanza, spessore, colore, salto delle discendenti.
    private func decorationEditor(_ decoration: LineDecoration, set: @escaping (LineDecoration) -> Void, remove: @escaping () -> Void) -> some View {
        func changed(_ build: (inout LineDecoration) -> Void) { var copy = decoration; build(&copy); set(copy) }
        func label(_ text: String) -> some View { Text(text).foregroundStyle(.secondary).frame(width: 70, alignment: .leading) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(get: { decoration.position }, set: { value in changed { $0.position = value } })) {
                    Text("Sotto").tag(LineDecoration.Position.under)
                    Text("In mezzo").tag(LineDecoration.Position.through)
                    Text("Sopra").tag(LineDecoration.Position.over)
                }
                .labelsHidden()
                .fixedSize()
                Picker("", selection: Binding(get: { decoration.pattern }, set: { value in changed { $0.pattern = value } })) {
                    Text("continua").tag(LineDecoration.Pattern.solid)
                    Text("doppia").tag(LineDecoration.Pattern.double)
                    Text("puntinata").tag(LineDecoration.Pattern.dotted)
                    Text("tratteggiata").tag(LineDecoration.Pattern.dashed)
                    Text("ondulata").tag(LineDecoration.Pattern.wavy)
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                Button { remove() } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Togli il filetto")
            }
            HStack(spacing: 6) {
                label("Distanza")
                measurement(decoration.offset, allowsNegative: true) { value in changed { $0.offset = value } }
            }
            HStack(spacing: 6) {
                label("Spessore")
                measurement(decoration.thickness ?? 0) { value in changed { $0.thickness = value > 0 ? value : nil } }
                    .help("0 vuol dire lo spessore che il font dichiara")
            }
            HStack(spacing: 6) {
                label("Colore")
                ColorPicker("Colore", selection: Binding(
                    get: { Color(nsColor: decoration.color.flatMap { TextStyling.color(hex: $0) } ?? .black) },
                    set: { color in changed { $0.color = TextStyling.hex(of: NSColor(color)) } }), supportsOpacity: false)
                    .labelsHidden()
                Button("Quello del testo") { changed { $0.color = nil } }.disabled(decoration.color == nil)
            }
            if decoration.position == .under {
                Toggle("Salta le discendenti", isOn: Binding(get: { decoration.skipsDescenders }, set: { on in changed { $0.skipsDescenders = on } }))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }

    /// Una misura in punti che accetta anche millimetri, centimetri, pollici, pica e calcoli.
    private func measurement(_ value: Double, allowsNegative: Bool = false, commit: @escaping (Double) -> Void) -> some View {
        LengthField(points: CGFloat(value), unit: .points, allowsNegative: allowsNegative) { commit(Double($0)) }
            .help("Si accettano mm, cm, in, pt, pc e calcoli; senza unità il valore è in punti")
    }

    /// Un campo numerico senza unità di lunghezza.
    private func number(_ value: Double, unit: String, commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(get: { value }, set: { if $0 != value { commit($0) } }), format: .number.precision(.fractionLength(0...2)))
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    // MARK: Documento

    private var documentRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lingua").frame(width: 118, alignment: .leading)
                Picker("", selection: Binding(get: { model.documentLanguage ?? "" }, set: { model.setDocumentLanguage?($0.isEmpty ? nil : $0) })) {
                    Text("Nessuna").tag("")
                    ForEach(model.languages, id: \.self) { Text($0.name).tag($0.code) }
                }
                .labelsHidden()
            }
            Toggle("Sillabazione: divide le parole a fine riga", isOn: Binding(get: { model.hyphenates }, set: { model.setHyphenates?($0) }))
            Toggle("Margini ottici", isOn: Binding(get: { model.usesOpticalMargins }, set: { model.features.setOpticalMargins?($0) }))
            Toggle("Spaziatura per corpo (tabella trak)", isOn: Binding(get: { model.appliesFontTracking }, set: { model.features.setFontTracking?($0) }))
            HStack(spacing: 8) {
                Text("Espansione glifi").frame(width: 118, alignment: .leading)
                Slider(value: Binding(get: { model.glyphExpansionLimit }, set: { model.setGlyphExpansionLimit?($0) }),
                       in: 0...0.03, step: 0.001) { model.glyphExpansionDragging?($0) }
                    .controlSize(.small)
                    .help("Nel testo giustificato; 0% disattiva l'espansione")
                Text(model.glyphExpansionLimit, format: .percent.precision(.fractionLength(0...1)))
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("Note numerate con").frame(width: 118, alignment: .leading)
                Picker("", selection: Binding(get: { model.noteList ?? "" }, set: { model.setNoteList?($0.isEmpty ? nil : $0) })) {
                    Text("1, 2, 3 (nessuna Lista)").tag("")
                    ForEach(model.lists, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            Text("Stili, Liste, stili di flottante e regole del documento si cambiano nelle schede qui sopra.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Il riquadro dei conteggi, aperto dalla barra di stato: il documento e, se c'è, la selezione.
struct CountsView: View {
    let sections: [(title: String, rows: [(String, String)])]

    /// Il riquadro come lo apre la barra di stato (SwiftUI resta in questo file).
    @MainActor
    static func makePopover(sections: [(title: String, rows: [(String, String)])]) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CountsView(sections: sections).themed())
        return popover
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sections[index].title).font(.headline)
                    ForEach(sections[index].rows.indices, id: \.self) { row in
                        HStack {
                            Text(sections[index].rows[row].0).foregroundStyle(.secondary)
                            Spacer(minLength: 24)
                            Text(sections[index].rows[row].1).monospacedDigit().textSelection(.enabled)
                        }
                    }
                }
            }
            Text("Il testo delle note non è contato.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
    }
}

// MARK: - La pagina

/// Il modulo della pagina: formato, orientamento, misure, pagine affacciate, margini. Sta nell'ispettore della Pagina e
/// nel foglio di File › Formato della pagina…; vale per tutto il documento.
struct PageSetupForm: View {
    let setup: PageSetup
    /// Applica un cambiamento alla pagina com'è in quel momento (non a una copia presa disegnando il modulo: due
    /// modifiche ravvicinate, come un campo che si chiude e un clic, si cancellerebbero a vicenda).
    let change: ((inout PageSetup) -> Void) -> Void

    /// I formati proposti, in millimetri, verticali.
    static let formats: [(name: String, width: Double, height: Double)] = [
        ("A3", 297, 420), ("A4", 210, 297), ("A5", 148, 210), ("B5", 176, 250),
        ("Lettera (US)", 215.9, 279.4), ("Legale (US)", 215.9, 355.6), ("Tabloid (US)", 279.4, 431.8),
    ]

    /// Il formato della pagina, in qualsiasi orientamento; `nil` se è personalizzato.
    static func format(of size: CGSize) -> String? {
        let width = PageSetup.millimetres(fromPoints: min(size.width, size.height)), height = PageSetup.millimetres(fromPoints: max(size.width, size.height))
        return formats.first { abs($0.width - width) < 0.6 && abs($0.height - height) < 0.6 }?.name
    }

    /// Le misure ammesse: margini non negativi, uno specchio di almeno mezzo pollice per lato, un foglio non enorme.
    static func isValid(_ setup: PageSetup) -> Bool {
        [setup.top, setup.bottom, setup.left, setup.right].allSatisfy { $0 >= 0 }
            && setup.paperSize.width - setup.left - setup.right >= 36 && setup.paperSize.height - setup.top - setup.bottom >= 36
            && max(setup.paperSize.width, setup.paperSize.height) <= PageSetup.points(fromMillimetres: 5000)
    }

    private var isLandscape: Bool { setup.paperSize.width > setup.paperSize.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Formato") {
                Picker("", selection: Binding(get: { Self.format(of: setup.paperSize) ?? "" }, set: { name in
                    guard let format = Self.formats.first(where: { $0.name == name }) else { return }
                    let width = PageSetup.points(fromMillimetres: format.width), height = PageSetup.points(fromMillimetres: format.height)
                    change { page in
                        let landscape = page.paperSize.width > page.paperSize.height
                        page.paperSize = landscape ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
                    }
                })) {
                    ForEach(Self.formats, id: \.name) { Text($0.name).tag($0.name) }
                    if Self.format(of: setup.paperSize) == nil { Text("Personalizzato").tag("") }
                }
                .labelsHidden()
            }
            row("Orientamento") {
                Picker("", selection: Binding(get: { isLandscape }, set: { landscape in
                    change { page in
                        if (page.paperSize.width > page.paperSize.height) != landscape {
                            page.paperSize = CGSize(width: page.paperSize.height, height: page.paperSize.width)
                        }
                    }
                })) {
                    Text("Verticale").tag(false)
                    Text("Orizzontale").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            row("Larghezza") { LengthField(points: setup.paperSize.width) { value in change { $0.paperSize.width = value } } }
            row("Altezza") { LengthField(points: setup.paperSize.height) { value in change { $0.paperSize.height = value } } }
            Toggle("Pagine affacciate, come in un libro", isOn: Binding(get: { setup.facing }, set: { on in change { $0.facing = on } }))
            row("Margine sopra") { LengthField(points: setup.top) { value in change { $0.top = value } } }
            row("Margine sotto") { LengthField(points: setup.bottom) { value in change { $0.bottom = value } } }
            row(setup.facing ? "Margine interno" : "Margine sinistro") { LengthField(points: setup.left) { value in change { $0.left = value } } }
            row(setup.facing ? "Margine esterno" : "Margine destro") { LengthField(points: setup.right) { value in change { $0.right = value } } }
            Text("Misure e calcoli: mm, cm, in, pt, pc. Esempio: 3 pt + 5 cm.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .help("Le misure valgono per tutte le pagine del documento. Si accettano millimetri, centimetri, pollici, punti e pica (anche 1p6), con calcoli come 210 − 2 × 25.")
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).frame(width: 118, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Una pagina cambiata, se le sue misure sono ammesse; altrimenti un segnale e `nil`.
    static func checked(_ page: PageSetup) -> PageSetup? {
        guard isValid(page) else {
            NSSound.beep()
            return nil
        }
        return page
    }
}

/// Un campo per una misura: mostra i millimetri, accetta qualsiasi unità (vedi `Length`) e la converte uscendo dal
/// campo o premendo Invio. Una misura che non si legge, o che la pagina non accetta, torna com'era.
/// Il modulo della sezione nell'ispettore: titolo, ruolo, livello, contenuto, e il pulsante per toglierla.
struct SectionForm: View {
    let info: InspectorModel.SectionInfo
    let setRole: (String) -> Void
    let setStart: (SectionStart) -> Void
    let setPageTypes: (SectionPageTypes) -> Void
    let setPageNumbering: (String?) -> Void
    let move: (Int) -> Void
    let remove: () -> Void
    @State private var roleText = ""
    @FocusState private var editingRole: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            line("Titolo") { Text(info.title).foregroundStyle(info.title == "senza titolo" ? .secondary : .primary) }
            line("Ruolo") {
                HStack(spacing: 4) {
                    TextField("", text: $roleText)
                        .frame(maxWidth: 150)
                        .focused($editingRole)
                        .onSubmit { commitRole() }
                        .onChange(of: editingRole) { _, focused in if !focused { commitRole() } }
                    Menu {
                        ForEach(Typesetting.Section.Role.builtIn, id: \.self) { role in Button(role) { setRole(role) } }
                    } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            .help("Il ruolo dice che cosa è la sezione, distinto dalla profondità e dallo stile del titolo. Si può scegliere o scrivere.")
            line("Comincia") {
                Picker("", selection: Binding(get: { info.start }, set: { setStart($0) })) {
                    Text("di seguito").tag(SectionStart.continuous)
                    Text("su una pagina nuova").tag(SectionStart.newPage)
                    Text("sulla prossima pagina dispari").tag(SectionStart.oddPage)
                }
                .labelsHidden()
                .fixedSize()
            }
            .help("Le sezioni successive dello stesso ruolo ereditano questa scelta.")
            VStack(alignment: .leading, spacing: 8) {
                typePicker("Pagine", \.pages, inherited: "come la sezione esterna")
                typePicker("Pagine pari", \.evenPages, inherited: "come le altre")
                typePicker("Prima pagina", \.firstPage, inherited: "come le altre")
            }
            .help("I tipi si definiscono nella scheda Pagine. Pagine e pari valgono anche per le sezioni interne; la prima pagina solo per questa.")
            line("Numeri di pagina") {
                Picker("", selection: Binding(get: { info.pageNumbering }, set: { setPageNumbering($0) })) {
                    Text("proseguono").tag(String?.none)
                    ForEach(info.listNames, id: \.self) { Text("ripartono con «\($0)»").tag(Optional($0)) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .help("La numerazione riparte dalla prima pagina con la Lista scelta e prosegue nelle sezioni successive fino a una nuova ripartenza.")
            line("Livello") {
                HStack(spacing: 8) {
                    Text("\(info.depth)")
                    Button("Più fuori") { move(-1) }.disabled(!info.canMoveOutside)
                    Button("Più dentro") { move(1) }.disabled(!info.canMoveInside)
                }
                .controlSize(.small)
            }
            .help("La sezione si sposta con le sue sezioni interne. Più dentro: diventa l'ultima interna della precedente. Più fuori: le sorelle seguenti diventano sue interne.")
            line("Contiene") {
                Text("\(info.paragraphs) \(info.paragraphs == 1 ? "paragrafo" : "paragrafi"), \(info.sections) \(info.sections == 1 ? "sezione interna" : "sezioni interne")")
            }
            Button("Togli la sezione") { remove() }
                .controlSize(.small)
                .help("Il titolo resta come paragrafo; il testo passa alla sezione che precede, le interne salgono di un livello")
        }
        .onAppear { roleText = info.role }
        .onChange(of: info.role) { _, role in roleText = role }
    }

    /// Un tipo di pagina della sezione: quello ereditato (`nil`), il predefinito, o uno con un nome.
    private func typePicker(_ title: String, _ path: WritableKeyPath<SectionPageTypes, String?>, inherited: String) -> some View {
        line(title) {
            Picker("", selection: Binding(get: { info.pageTypes[keyPath: path] }, set: { name in
                var types = info.pageTypes
                types[keyPath: path] = name
                setPageTypes(types)
            })) {
                Text(inherited).tag(String?.none)
                Text(PageType.defaultName).tag(Optional(PageType.defaultName))
                ForEach(info.typeNames, id: \.self) { Text($0).tag(Optional($0)) }
                // Un nome che non c'è più resta visibile finché non si cambia.
                if let current = info.pageTypes[keyPath: path], current != PageType.defaultName, !info.typeNames.contains(current) {
                    Text("\(current) (non c'è più)").tag(Optional(current))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func line<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).frame(width: 118, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commitRole() {
        let role = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !role.isEmpty, !role.contains("\n") else {
            roleText = info.role
            return
        }
        guard role != info.role else { return }
        // Come per le misure: si applica un attimo dopo, perché un clic che fa uscire dalla casella non vada perso.
        nonisolated(unsafe) let setRole = setRole
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { setRole(role) } }
    }
}

struct LengthField: View {
    let points: CGFloat
    /// L'unità in cui si mostra la misura, e quella di un numero scritto senza unità.
    var unit: LengthUnit = .millimetres
    /// I rientri e la distanza dei filetti possono essere negativi; le dimensioni e gli spazi no.
    var allowsNegative = false
    let commit: (CGFloat) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .frame(width: 96)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onAppear { text = Length.text(points, unit: unit) }
            .onChange(of: points) { _, new in text = Length.text(new, unit: unit) }
            .onChange(of: focused) { _, isFocused in if !isFocused { apply() } }
            .onSubmit { apply() }
    }

    static func validatedPoints(from text: String, defaultUnit: LengthUnit, allowsNegative: Bool = false) -> CGFloat? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        guard let value = Length.points(from: text, defaultUnit: defaultUnit), allowsNegative || value >= 0 else { return nil }
        return value
    }

    private func apply() {
        guard let value = Self.validatedPoints(from: text, defaultUnit: unit, allowsNegative: allowsNegative) else {
            NSSound.beep()
            text = Length.text(points, unit: unit)
            return
        }
        // Si rimette il valore di prima: se la pagina accetta il nuovo, `points` cambia e il campo lo mostra. La misura si
        // applica un attimo dopo: uscendo dal campo con un clic su un altro controllo, il modulo si ridisegnerebbe sotto
        // il clic, che andrebbe perso.
        text = Length.text(points, unit: unit)
        guard abs(value - points) > 0.001 else { return }
        // La chiusura resta sul thread principale: il ciclo degli eventi la esegue lì.
        nonisolated(unsafe) let commit = commit
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { commit(value) } }
    }
}

/// Il foglio di File › Formato della pagina…: lo stesso modulo dell'ispettore, su una copia, con Annulla e OK.
@MainActor
final class PageSetupSheetModel: ObservableObject {
    @Published var setup: PageSetup
    var finish: ((PageSetup?) -> Void)?

    init(setup: PageSetup) {
        self.setup = setup
    }

    func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: PageSetupSheetView(model: self).themed())
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(controller.view.fittingSize)
        return window
    }
}

struct PageSetupSheetView: View {
    @ObservedObject var model: PageSetupSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Formato della pagina").font(.headline)
            PageSetupForm(setup: model.setup) { transform in
                var page = model.setup
                transform(&page)
                if let page = PageSetupForm.checked(page) { model.setup = page }
            }
            HStack {
                Spacer()
                Button("Annulla") { model.finish?(nil) }.keyboardShortcut(.cancelAction)
                Button("OK") { model.finish?(model.setup) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 400)
    }
}
