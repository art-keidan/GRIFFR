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
        case .document: "Document"
        case .section: "Section"
        case .page: "Page"
        case .table: "Table"
        case .cell: "Cell"
        case .paragraph: "Paragraph"
        case .line: "Line"
        case .word: "Word"
        case .character: "Character"
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

    /// Un passo del percorso in testa all'ispettore: un oggetto, o una delle sezioni che contengono il cursore.
    struct PathStep: Equatable, Identifiable {
        enum Target: Equatable, Hashable {
            case object(InspectedObject)
            /// La sezione di quel livello (1 la più esterna).
            case section(Int)
        }
        let target: Target
        let title: String
        var id: Target { target }
    }

    /// Documento › sezioni › Pagina › (Tabella › Cella) › Paragrafo › Riga › Parola › Carattere, come la selezione li ha.
    @Published var path: [PathStep] = []
    /// Il passo scelto: l'oggetto che l'ispettore mostra.
    @Published var pathChoice: PathStep.Target = .object(.paragraph)
    var choosePath: ((PathStep.Target) -> Void)?
    /// Tiene qui il valore dato a mano che una regola sospende: un'eccezione alla regola, in questo punto.
    var keepHere: ((InspectorProperty, StyleValues) -> Void)?
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
                case .boolean(let enabled): argument = enabled ? "Yes" : "No"
                case .integer(let count): argument = String(count)
                case .text(let value): argument = value.isEmpty ? "None" : value
                case .styleName(let name): argument = name ?? "Same style"
                case .pageStart(let spacing):
                    switch spacing { case .disabled: argument = "Off"; case .distance(let points): argument = points.formatted() + " pt" }
                case .font(let role): argument = roleTitle(role)
                case .face(let name), .family(let name): argument = name
                case .length(let value, let unit): argument = value.formatted() + " " + unit.rawValue
                case .language(let value): argument = value ?? "Document language"
                case .color(let value): argument = value ?? "Automatic"
                case .smallCaps(let mode): argument = mode.rawValue
                case .hyphenates(let enabled): argument = enabled ? "On" : "Off"
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
        if !graphiteAvailable { return "graphite2 is not installed on this Mac: composing with Core Text" }
        if !fontHasGraphite {
            let name = shownFontName.map { CTFontCopyDisplayName(CTFontCreateWithName($0 as CFString, 12, nil)) as String }
            return "\(name.map { "“\($0)”" } ?? "This font") has no Graphite tables: composing with Core Text"
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
        case .own: editsStyle ? "Set in this style" : "Set here"
        case .style(let name): editsStyle ? "From “\(name)”, which it is based on" : "From the style “\(name)”"
        case .document: "From the document"
        case .rule(let summary): "From the rule: \(summary)"
        }
        if value.isMixed { text += " · the selection has different values" }
        return text
    }

    func change(_ property: InspectorProperty, _ build: (inout StyleValues) -> Void) {
        guard !formulaIsLocked(property) else { return }
        var values = StyleValues()
        build(&values)
        set?(property, values)
    }
}

extension View {
    /// I controlli di SwiftUI (caselle, menu, pulsanti) nell'azzurro del disegno invece che nel colore d'accento del sistema,
    /// e i pulsanti con il passaggio del mouse.
    func themed() -> some View { tint(Color(nsColor: Theme.accent)).buttonStyle(.hover()) }

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
                    collapsible("document", "Document") { documentRows }
                    factRows
                case .page:
                    collapsible("page", "Page setup") {
                        Text(model.pageTypeName.map { "Type “\($0)”" } ?? "Default type")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .help(model.pageTypeName == nil ? "Applies to pages without their own type." : "Changes apply to all pages of this type.")
                        PageSetupForm(setup: model.pageSetup) { transform in
                            var page = model.pageSetup
                            transform(&page)
                            if let page = PageSetupForm.checked(page) { model.setPageSetup?(page) }
                        }
                    }
                    factRows
                case .section:
                    if let section = model.section {
                        collapsible("section", "Section") {
                            SectionForm(info: section, setRole: { model.setSectionRole?($0) }, setStart: { model.setSectionStart?($0) },
                                        setPageTypes: { model.setSectionPageTypes?($0) }, setPageNumbering: { model.setSectionPageNumbering?($0) },
                                        move: { model.moveSection?($0) }, remove: { model.removeSection?() })
                        }
                    } else {
                        Text("The cursor is not in a section. Open a section from the Insert menu.").foregroundStyle(.secondary)
                    }
                    factRows
                case .table:
                    if let table = model.table {
                        collapsible("table", "Table") {
                            TableForm(info: table, setHeaderRows: { model.setTableHeaderRows?($0) }, setStyle: { model.setTableStyle?($0) },
                                      setFloat: { model.setTableFloat?($0) },
                                      change: { model.changeTable?($0) }, command: { model.tableCommand?($0) })
                        }
                    } else {
                        Text("The cursor is not in a table. Insert a table from the Insert menu.").foregroundStyle(.secondary)
                    }
                    factRows
                case .cell:
                    if let cell = model.cell {
                        collapsible("cell", "Cell") {
                            CellForm(info: cell, change: { model.changeCell?($0) }, split: { model.splitCell?() })
                        }
                    } else {
                        Text("The cursor is not in a table.").foregroundStyle(.secondary)
                    }
                case .line:
                    factRows
                case .character:
                    filterBar
                    rows
                    detailRows
                    factRows
                    collapsible("features", "Font features") {
                        FeaturePanelView(model: model.features, embedded: true)
                    }
                default:
                    filterBar
                    rows
                    factRows
                }
                if model.object.level != nil && !model.values.isEmpty {
                    Divider()
                    legend
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: Self.minimumWidth)
    }

    /// Il percorso degli oggetti: si sceglie qui che cosa guarda l'ispettore.
    @ViewBuilder private var pathBar: some View {
        if !model.path.isEmpty {
            FlowLayout(spacing: 2, lineSpacing: 2) {
                ForEach(Array(model.path.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 2) {
                        if index > 0 { Text("›").foregroundStyle(.secondary).accessibilityHidden(true) }
                        pathButton(step)
                    }
                }
            }
            .font(.system(size: 11))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Object path")
        }
    }

    private func pathButton(_ step: InspectorModel.PathStep) -> some View {
        let chosen = step.target == model.pathChoice
        return Button { model.choosePath?(step.target) } label: {
            Text(step.title).lineLimit(1)
                .fontWeight(chosen ? .semibold : .regular)
                .foregroundStyle(chosen ? Color(nsColor: Theme.glyph) : Color(nsColor: Theme.secondary))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(chosen ? Color(nsColor: Theme.controlBottom) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(chosen ? Color(nsColor: Theme.controlLine) : .clear))
        }
        .buttonStyle(.hover(.plain))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            pathBar.padding(.bottom, 8)
            Text(model.object.title).font(.title3.bold())
            if model.object.level != nil {
                Text(model.styleName.map { "Style “\($0)”" } ?? "No style").foregroundStyle(.secondary)
                if !model.editsStyle {
                    HStack(spacing: 8) {
                        Button { model.createStyle?() } label: { Image(systemName: "paintbrush") }
                            .help("Create a style that looks like this \(model.object.title.lowercased())")
                            .accessibilityLabel("Create a Style from Here")
                        if model.object == .word || model.object == .character {
                            Button { model.createRule?() } label: { Image(systemName: "wand.and.rays") }
                                .help("Create a rule for text like the selected text")
                                .accessibilityLabel("Create a Rule from Here")
                        }
                    }
                    .buttonStyle(.hover(.borderless))
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
        }
    }

    /// Funzioni, assi e corpo ottico: si scelgono nel pannello delle funzioni e con i cursori; qui si vede da dove
    /// vengono, e ciascuno si toglie o si porta nello stile da solo.
    @ViewBuilder private var detailRows: some View {
        let details = onlySet ? model.details.filter { $0.source != .document } : model.details
        if !details.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                groupHeader(id: "details", title: "Features and axes", sources: details.map(\.source))
                    .help("Each one can be removed or moved into the style on its own, without touching the others.")
                if isOpen("details") {
                    ForEach(details) { detail in detailRow(detail) }
                }
            }
        }
    }

    private func detailRow(_ detail: InspectedDetail) -> some View {
        let showing = explainedDetail == detail.id
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Text(detail.title).lineLimit(1).frame(width: 118, alignment: .leading)
                    .foregroundStyle(detail.source == .document ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Text(detail.value).frame(maxWidth: .infinity, alignment: .leading)
                Button { explainedDetail = showing ? nil : detail.id } label: {
                    SourceDot(source: detail.source, size: 9).frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.hover(.plain))
                .help(detailSourceText(detail))
                .accessibilityLabel("\(detail.title): \(detailSourceText(detail))")
                .accessibilityHint("Shows where the value comes from and what you can do with it")
            }
            if showing {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detailSourceText(detail)).font(.caption.weight(.semibold)).foregroundStyle(sourceColor(detail.source))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        detailMenu(detail)
                        Text("Move into the style or back to the inherited value").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: Theme.control)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: Theme.line)))
            }
        }
    }

    /// Un modulo intero (pagina, sezione, tabella, cella) in un gruppo richiudibile come gli altri.
    private func collapsible<Content: View>(_ id: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            groupHeader(id: id, title: title, sources: [])
            if isOpen(id) { content() }
        }
    }

    private func detailSourceText(_ detail: InspectedDetail) -> String {
        var text = switch detail.source {
        case .own: "Set here · in the style: \(detail.inherited.lowercased())"
        case .style(let name): "From the style “\(name)”"
        case .document: "From the document"
        case .rule(let summary): "From the rule: \(summary)"
        }
        if detail.isMixed { text += " · the selection has different values" }
        return text
    }

    private func detailMenu(_ detail: InspectedDetail) -> some View {
        let receiver = model.detailReceiver
        return Menu {
            Button(receiver.map { "Move this value into the style “\($0)”" } ?? "Move this value into the style") { model.moveDetailToStyle?(detail.detail) }
                .disabled(receiver == nil || !model.detailsMovable || detail.source != .own)
            Button("Back to the inherited value") { model.resetDetail?(detail.detail) }
                .disabled(detail.source != .own)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).hoverable()
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.detailsMovable || receiver == nil ? "The value set here"
              : "The text has a different font from the style: move the family into the style first")
    }

    // MARK: Gruppi e righe

    /// Un gruppo richiudibile di proprietà.
    struct PropertyGroup: Identifiable {
        let id: String
        let title: String
        let properties: [InspectorProperty]
    }

    static let groups: [PropertyGroup] = [
        .init(id: "align", title: "Alignment and indents", properties: [.alignment, .leftIndent, .rightIndent, .firstLineIndent]),
        .init(id: "space", title: "Spacing", properties: [.spaceBefore, .spaceAfter, .openingDistance]),
        .init(id: "lines", title: "Lines", properties: [.lineHeightMultiple, .lineSpacing]),
        .init(id: "keep", title: "Keeping", properties: [.keepWithNext, .nextLines, .previousLines, .keepTogether, .orphanLines, .widowLines]),
        .init(id: "list", title: "List", properties: [.list]),
        .init(id: "font", title: "Font", properties: [.family, .face, .size]),
        .init(id: "form", title: "Form", properties: [.smallCaps, .verticalPosition, .decorations, .color, .shaping]),
        .init(id: "language", title: "Language", properties: [.language, .hyphenates]),
    ]

    /// I gruppi chiusi o aperti a mano: all'inizio sono aperti tutti, tranne i fatti dell'impaginato.
    @State private var toggledGroups: Set<String> = []
    /// Vero con il filtro «Set»: si nascondono i valori che vengono dal documento.
    @State private var onlySet = false
    /// La proprietà di cui si vede la spiegazione (provenienza e azioni).
    @State private var explained: InspectorProperty?
    /// La funzione o l'asse del carattere di cui si vede la spiegazione.
    @State private var explainedDetail: InspectedDetail.ID?

    private func isOpen(_ group: String) -> Bool {
        group == "facts" ? toggledGroups.contains(group) : !toggledGroups.contains(group)
    }

    private func toggle(_ group: String) {
        if toggledGroups.contains(group) { toggledGroups.remove(group) } else { toggledGroups.insert(group) }
    }

    /// I valori raggruppati, nell'ordine dei gruppi; quelli che nessun gruppo nomina vanno in «Other».
    private func groupedValues(_ values: [InspectedValue]) -> [(group: PropertyGroup, values: [InspectedValue])] {
        var result: [(group: PropertyGroup, values: [InspectedValue])] = []
        var placed = Set<InspectorProperty>()
        for group in Self.groups {
            let members = values.filter { group.properties.contains($0.property) }
            placed.formUnion(members.map(\.property))
            if !members.isEmpty { result.append((group, members)) }
        }
        let others = values.filter { !placed.contains($0.property) }
        if !others.isEmpty { result.append((PropertyGroup(id: "other", title: "Other", properties: others.map(\.property)), others)) }
        return result
    }

    /// Il filtro All / Set, con il conto di ciò che nasconde.
    @ViewBuilder private var filterBar: some View {
        if !model.values.isEmpty {
            HStack(spacing: 8) {
                Picker("Show", selection: $onlySet) {
                    Text("All").tag(false)
                    Text("Set").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                .help("Set: hide the values that come from the document")
                Spacer()
                let hidden = model.values.filter { $0.source == .document }.count
                if onlySet && hidden > 0 {
                    Text("\(hidden) from the document hidden").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Che cosa vogliono dire i pallini.
    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([ValueSource.document, .style(""), .own, .rule("")], id: \.legendTitle) { source in
                HStack(spacing: 4) {
                    SourceDot(source: source, size: 7)
                    Text(source.legendTitle)
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// Le proprietà dinamiche: si leggono soltanto, in un gruppo chiuso all'inizio.
    @ViewBuilder private var factRows: some View {
        if !model.facts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                groupHeader(id: "facts", title: "From the layout", sources: [])
                    .help("Values computed while laying out the pages: they change as you type and cannot be set.")
                if isOpen("facts") {
                    ForEach(model.facts, id: \.self) { fact in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fact.title).frame(width: 118, alignment: .leading)
                            Text(fact.value).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        if model.values.isEmpty {
            Text("The document is empty.").foregroundStyle(.secondary)
        }
        let shown = onlySet && !rowsOnly ? model.values.filter { $0.source != .document } : model.values
        ForEach(groupedValues(shown), id: \.group.id) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                groupHeader(id: entry.group.id, title: entry.group.title, sources: entry.values.map(\.source))
                if isOpen(entry.group.id) {
                    ForEach(entry.values, id: \.property) { value in row(value) }
                }
            }
        }
    }

    /// L'intestazione di un gruppo: si apre e si chiude; chiusa mostra i pallini di ciò che contiene.
    private func groupHeader(id: String, title: String, sources: [ValueSource]) -> some View {
        let open = isOpen(id)
        var kinds: [ValueSource] = []
        for source in sources where source != .document && !kinds.contains(where: { $0.legendTitle == source.legendTitle }) {
            kinds.append(source)
        }
        return Button { toggle(id) } label: {
            HStack(spacing: 6) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10)
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                Spacer()
                if !open {
                    HStack(spacing: 3) { ForEach(kinds, id: \.legendTitle) { SourceDot(source: $0, size: 7) } }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.hover(.plain))
        .accessibilityLabel(title)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }

    private func row(_ value: InspectedValue) -> some View {
        // I filetti hanno un riquadro per ciascuno, con più campi: stanno sotto il titolo, a tutta larghezza.
        let wide = value.property == .decorations
        let property = value.property
        let showing = explained == property
        return VStack(alignment: .leading, spacing: 3) {
            if wide {
                HStack(alignment: .center) {
                    rowTitle(value)
                    Spacer()
                    rowMarks(value)
                }
                control(value).disabled(model.formulaIsLocked(property))
            } else {
                HStack(alignment: .center, spacing: 6) {
                    rowTitle(value).frame(width: 118, alignment: .leading)
                    control(value).disabled(model.formulaIsLocked(property)).frame(maxWidth: .infinity, alignment: .leading)
                    rowMarks(value)
                }
            }
            if !showing, let brief = ruleBrief(value) {
                Text(brief.text).font(.caption).foregroundStyle(brief.color)
                    .lineLimit(2).padding(.leading, wide ? 0 : 124)
            }
            if !showing, value.isMixed {
                Text("The selection has different values").font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, wide ? 0 : 124)
            }
            if showing { explanation(value) }
        }
    }

    private func rowTitle(_ value: InspectedValue) -> some View {
        Text(value.property.title).lineLimit(1)
            .foregroundStyle(value.source == .document ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }

    /// Accanto al valore: la formula, il pennello se le modifiche vanno nello stile, il pallino della provenienza.
    @ViewBuilder private func rowMarks(_ value: InspectedValue) -> some View {
        let property = value.property
        if model.formulaDefinitions[property] != nil {
            Text("ƒ").font(.system(size: 11, weight: .semibold, design: .serif)).italic()
                .foregroundStyle(Color(nsColor: Theme.accent))
                .help(model.formulaSummary(property) ?? "Calculated by a formula")
                .accessibilityLabel("Formula")
        }
        if !model.editsStyle && model.mode(property) == .style {
            Image(systemName: "paintbrush").font(.system(size: 10)).foregroundStyle(Color(nsColor: Theme.accent))
                .help("Changes go into the style").accessibilityLabel("Changes go into the style")
        }
        Button { explained = explained == property ? nil : property } label: {
            SourceDot(source: value.source, size: 9).frame(width: 16, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(.hover(.plain))
        .help(model.sourceText(value))
        .accessibilityLabel("\(property.title): \(model.sourceText(value))")
        .accessibilityHint("Shows where the value comes from and what you can do with it")
    }

    /// La spiegazione aperta dal pallino: da dove viene il valore, la formula, e le azioni del menu.
    private func explanation(_ value: InspectedValue) -> some View {
        let property = value.property
        return VStack(alignment: .leading, spacing: 6) {
            Text(model.sourceText(value)).font(.caption.weight(.semibold)).foregroundStyle(sourceColor(value.source))
                .fixedSize(horizontal: false, vertical: true)
            if let summary = model.formulaSummary(property), let definition = model.formulaDefinitions[property] {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary).font(.caption).foregroundStyle(Color(nsColor: Theme.accent))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Composer") { model.openFormula?(definition.owner) }.font(.caption)
                }
            }
            ruleDetails(value)
            HStack(spacing: 6) {
                menu(value)
                Text(model.editsStyle ? "This style's value" : (model.mode(property) == .style ? "Changes go into the style" : "Changes apply only here"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: Theme.control)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: Theme.line)))
    }

    /// La riga breve sotto un valore che una regola tocca: chi lo decide, e che cosa resta sospeso o scavalcato.
    private func ruleBrief(_ value: InspectedValue) -> (text: String, color: Color)? {
        let property = value.property
        switch value.source {
        case .rule(let summary):
            var text = "Rule: " + summary
            if let suspended = value.rules?.suspended { text += " · yours (\(property.text(of: suspended))) suspended" }
            if let others = value.rules?.outranked, !others.isEmpty {
                text += " · overrides \(others.count) other \(others.count == 1 ? "rule" : "rules")"
            }
            return (text, Color(nsColor: Theme.ruleSource))
        case .own:
            guard let influence = value.rules, let winner = influence.winner else { return nil }
            return ("Wins over the rule: " + winner, Color(nsColor: Theme.ownSource))
        default:
            return nil
        }
    }

    /// Nella spiegazione: lo stile della regola, le regole scavalcate, il valore sospeso o quello che la regola darebbe.
    @ViewBuilder private func ruleDetails(_ value: InspectedValue) -> some View {
        let property = value.property
        if let influence = value.rules {
            VStack(alignment: .leading, spacing: 5) {
                if let owner = influence.owner {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("A contextual formula of the style “\(owner)”.").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Se la formula della riga è già di questo stile, il suo pulsante c'è sopra.
                        if model.formulaDefinitions[property]?.owner != owner {
                            Button("Composer") { model.openFormula?(owner) }.font(.caption)
                        }
                    }
                }
                if !influence.outranked.isEmpty {
                    Text("Also set by " + influence.outranked.map { "“\($0)”" }.joined(separator: ", ")
                         + ": where two rules meet, the first one that changes the value wins.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let suspended = influence.suspended, !model.editsStyle {
                    Text("The value set here, \(property.text(of: suspended)), is kept but not applied while the rule holds.")
                        .font(.caption).foregroundStyle(Color(nsColor: Theme.ownSource)).fixedSize(horizontal: false, vertical: true)
                    Button("Keep \(property.text(of: suspended)) here") { model.keepHere?(property, suspended) }
                        .font(.caption)
                        .help("Makes an exception: the rule no longer changes this value here")
                }
                if let yielded = influence.yielded, let winner = influence.winner, !model.editsStyle {
                    Text("The value set here wins over the rule “\(winner)”, which would give \(property.text(of: yielded)).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Let the Rule Apply") { model.reset?(property) }
                        .font(.caption)
                        .help("Removes the value set here: the rule decides again")
                }
            }
        }
    }

    /// Il colore della provenienza: arancio per ciò che è dato qui, verde per una regola, azzurro per uno stile.
    private func sourceColor(_ source: ValueSource) -> AnyShapeStyle {
        switch source {
        case .own: AnyShapeStyle(Color(nsColor: Theme.ownSource))
        case .rule: AnyShapeStyle(Color(nsColor: Theme.ruleSource))
        case .style: AnyShapeStyle(Color(nsColor: Theme.accent))
        case .document: AnyShapeStyle(.secondary)
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
                Button("Open the formula in the composer") { model.openFormula?(definition.owner) }
                if definition.isCalculated {
                    Button("Use the result as a fixed value") { model.replaceFormula?(value.property) }
                }
                Divider()
            }
            Button("Remove from this style (it inherits it)") { model.reset?(value.property) }
                .disabled(value.source != .own)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).hoverable()
        .menuIndicator(.hidden)
        .fixedSize()
        .help("This style's value")
    }

    private func textMenu(_ value: InspectedValue) -> some View {
        let property = value.property
        let receiver = model.receivers[property]
        return Menu {
            Toggle("Change only here", isOn: Binding(get: { model.mode(property) == .here }, set: { if $0 { model.modes[property] = .here } }))
            Toggle(receiver.map { "Change in the style “\($0)”" } ?? "Change in the style (the text has none)",
                   isOn: Binding(get: { model.mode(property) == .style }, set: { if $0 { model.modes[property] = .style } }))
                .disabled(receiver == nil)
            Divider()
            if let definition = model.formulaDefinitions[property] {
                Button("Open the formula in the composer") { model.openFormula?(definition.owner) }
                if definition.isCalculated {
                    Button("Replace the formula in the style with the value here") { model.replaceFormula?(property) }
                }
                Divider()
            }
            Button(receiver.map { (model.formulaDefinitions[property]?.isCalculated == true ? "Replace the formula with this value in “\($0)”" : "Move this value into the style “\($0)”") } ?? "Move this value into the style") { model.moveToStyle?(property) }
                .disabled(receiver == nil || value.source != .own)
            Button("Back to the inherited value") { model.reset?(property) }
                .disabled(value.source != .own)
        } label: {
            Image(systemName: model.mode(property) == .style ? "paintbrush" : "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).hoverable()
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.mode(property) == .style ? "Changes go into the style" : "Changes apply only here")
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
                Menu(list.isEmpty ? "Add a Line" : "Add") {
                    Button("Underline") { commit(list + [.underline]) }
                    Button("Strikethrough") { commit(list + [.strikethrough]) }
                    Button("Overline") { commit(list + [LineDecoration(position: .over)]) }
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
                    Text("On the baseline").tag(0)
                    Text("Superscript").tag(1)
                    Text("Subscript").tag(2)
                    Text("Custom").tag(3)
                }
                .labelsHidden()
                if let position {
                    HStack(spacing: 6) {
                        Text("alzata").foregroundStyle(.secondary)
                        number(position.shift, unit: "em") { shift in
                            model.change(.verticalPosition) { $0.verticalPosition = VerticalPosition(shift: shift, scale: position.scale, usesFontGlyphs: position.usesFontGlyphs).encoded }
                        }
                        Text("size").foregroundStyle(.secondary)
                        number(position.scale, unit: "×") { scale in
                            let scale = min(max(scale, 0.2), 1)
                            model.change(.verticalPosition) { $0.verticalPosition = VerticalPosition(shift: position.shift, scale: scale, usesFontGlyphs: position.usesFontGlyphs).encoded }
                        }
                    }
                    Toggle("The font's glyphs, if it has them", isOn: Binding(get: { position.usesFontGlyphs }, set: { on in
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
                Button("Automatic") { model.change(.color) { $0.color = "" } }
                    .disabled((v.color ?? "").isEmpty)
            }
        case .language:
            Picker("", selection: Binding(get: { v.language ?? "" }, set: { code in model.change(.language) { $0.language = code } })) {
                Text("The document's").tag("")
                ForEach(model.languages, id: \.self) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
        case .hyphenates:
            Toggle("Splits words at the end of lines", isOn: Binding(get: { v.hyphenates ?? true }, set: { on in model.change(.hyphenates) { $0.hyphenates = on } }))
        case .alignment:
            Picker("", selection: Binding(get: { v.alignment ?? .natural }, set: { alignment in model.change(.alignment) { $0.alignment = alignment } })) {
                Text("Natural").tag(ParagraphStyle.Alignment.natural)
                Text("Left").tag(ParagraphStyle.Alignment.left)
                Text("Center").tag(ParagraphStyle.Alignment.center)
                Text("Right").tag(ParagraphStyle.Alignment.right)
                Text("Justified").tag(ParagraphStyle.Alignment.justified)
                Text("Decimal").tag(ParagraphStyle.Alignment.decimal)
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
                .help("Multiple of the line height; 0 means the font's natural height")
        case .lineSpacing:
            measurement(v.lineSpacing ?? 0) { x in model.change(.lineSpacing) { $0.lineSpacing = x } }
        case .openingDistance:
            // Una misura di pagina: in millimetri come i margini, e accetta qualsiasi unità.
            LengthField(points: CGFloat(v.openingDistance ?? 0)) { x in model.change(.openingDistance) { $0.openingDistance = Double(x) } }
                .help("From the top margin, only for the paragraph that opens a sequence of pages: the title of a section that starts on a new page, or the first of the document")
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
        case .nextLines:
            linesPicker(v.keeping.nextLines ?? 1) { lines in model.change(.nextLines) { $0.keeping.nextLines = lines } }
        case .previousLines:
            Stepper(value: Binding(get: { v.keeping.previousLines ?? 0 }, set: { lines in model.change(.previousLines) { $0.keeping.previousLines = lines } }),
                    in: LineKeeping.previousRange) { Text("\(v.keeping.previousLines ?? 0)") }
        case .list:
            Picker("", selection: Binding(get: { v.listName ?? "" }, set: { name in model.change(.list) { $0.listName = name } })) {
                Text("None").tag("")
                if let name = v.listName, !name.isEmpty, !model.lists.contains(name) { Text(name).tag(name) }
                ForEach(model.lists, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    /// Le righe minime della tenuta: nessuna (1) o da 2 a 9.
    private func linesPicker(_ lines: Int, set: @escaping (Int) -> Void) -> some View {
        Picker("", selection: Binding(get: { lines }, set: set)) {
            Text("none").tag(1)
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
                    Text("Under").tag(LineDecoration.Position.under)
                    Text("Through").tag(LineDecoration.Position.through)
                    Text("Over").tag(LineDecoration.Position.over)
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
                Button { remove() } label: { Image(systemName: "minus.circle") }.buttonStyle(.hover(.borderless)).help("Remove Line")
            }
            HStack(spacing: 6) {
                label("Distance")
                measurement(decoration.offset, allowsNegative: true) { value in changed { $0.offset = value } }
            }
            HStack(spacing: 6) {
                label("Thickness")
                measurement(decoration.thickness ?? 0) { value in changed { $0.thickness = value > 0 ? value : nil } }
                    .help("0 means the thickness the font declares")
            }
            HStack(spacing: 6) {
                label("Color")
                ColorPicker("Color", selection: Binding(
                    get: { Color(nsColor: decoration.color.flatMap { TextStyling.color(hex: $0) } ?? .black) },
                    set: { color in changed { $0.color = TextStyling.hex(of: NSColor(color)) } }), supportsOpacity: false)
                    .labelsHidden()
                Button("The text's") { changed { $0.color = nil } }.disabled(decoration.color == nil)
            }
            if decoration.position == .under {
                Toggle("Skips descenders", isOn: Binding(get: { decoration.skipsDescenders }, set: { on in changed { $0.skipsDescenders = on } }))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }

    /// Una misura in punti che accetta anche millimetri, centimetri, pollici, pica e calcoli.
    private func measurement(_ value: Double, allowsNegative: Bool = false, commit: @escaping (Double) -> Void) -> some View {
        LengthField(points: CGFloat(value), unit: .points, allowsNegative: allowsNegative) { commit(Double($0)) }
            .help("Accepts mm, cm, in, pt, pc and arithmetic; without a unit the value is in points")
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
                Text("Language").frame(width: 118, alignment: .leading)
                Picker("", selection: Binding(get: { model.documentLanguage ?? "" }, set: { model.setDocumentLanguage?($0.isEmpty ? nil : $0) })) {
                    Text("None").tag("")
                    ForEach(model.languages, id: \.self) { Text($0.name).tag($0.code) }
                }
                .labelsHidden()
            }
            Toggle("Hyphenation: splits words at the end of lines", isOn: Binding(get: { model.hyphenates }, set: { model.setHyphenates?($0) }))
            Toggle("Optical margins", isOn: Binding(get: { model.usesOpticalMargins }, set: { model.features.setOpticalMargins?($0) }))
            Toggle("Size-specific tracking (trak table)", isOn: Binding(get: { model.appliesFontTracking }, set: { model.features.setFontTracking?($0) }))
            HStack(spacing: 8) {
                Text("Glyph expansion").frame(width: 118, alignment: .leading)
                Slider(value: Binding(get: { model.glyphExpansionLimit }, set: { model.setGlyphExpansionLimit?($0) }),
                       in: 0...0.03, step: 0.001) { model.glyphExpansionDragging?($0) }
                    .controlSize(.small)
                    .help("In justified text; 0% turns expansion off")
                Text(model.glyphExpansionLimit, format: .percent.precision(.fractionLength(0...1)))
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("Notes numbered with").frame(width: 118, alignment: .leading)
                Picker("", selection: Binding(get: { model.noteList ?? "" }, set: { model.setNoteList?($0.isEmpty ? nil : $0) })) {
                    Text("1, 2, 3 (no list)").tag("")
                    ForEach(model.lists, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            Text("The document's styles, lists, float styles and rules are changed in the tabs above.").font(.caption).foregroundStyle(.secondary)
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
            Text("Note text is not counted.").font(.caption).foregroundStyle(.secondary)
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
        ("Letter (US)", 215.9, 279.4), ("Legal (US)", 215.9, 355.6), ("Tabloid (US)", 279.4, 431.8),
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
            row("Size") {
                Picker("", selection: Binding(get: { Self.format(of: setup.paperSize) ?? "" }, set: { name in
                    guard let format = Self.formats.first(where: { $0.name == name }) else { return }
                    let width = PageSetup.points(fromMillimetres: format.width), height = PageSetup.points(fromMillimetres: format.height)
                    change { page in
                        let landscape = page.paperSize.width > page.paperSize.height
                        page.paperSize = landscape ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
                    }
                })) {
                    ForEach(Self.formats, id: \.name) { Text($0.name).tag($0.name) }
                    if Self.format(of: setup.paperSize) == nil { Text("Custom").tag("") }
                }
                .labelsHidden()
            }
            row("Orientation") {
                Picker("", selection: Binding(get: { isLandscape }, set: { landscape in
                    change { page in
                        if (page.paperSize.width > page.paperSize.height) != landscape {
                            page.paperSize = CGSize(width: page.paperSize.height, height: page.paperSize.width)
                        }
                    }
                })) {
                    Text("Portrait").tag(false)
                    Text("Landscape").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            row("Width") { LengthField(points: setup.paperSize.width) { value in change { $0.paperSize.width = value } } }
            row("Height") { LengthField(points: setup.paperSize.height) { value in change { $0.paperSize.height = value } } }
            Toggle("Facing pages, as in a book", isOn: Binding(get: { setup.facing }, set: { on in change { $0.facing = on } }))
            row("Top margin") { LengthField(points: setup.top) { value in change { $0.top = value } } }
            row("Bottom margin") { LengthField(points: setup.bottom) { value in change { $0.bottom = value } } }
            row(setup.facing ? "Inside margin" : "Left margin") { LengthField(points: setup.left) { value in change { $0.left = value } } }
            row(setup.facing ? "Outside margin" : "Right margin") { LengthField(points: setup.right) { value in change { $0.right = value } } }
            Text("Measures and arithmetic: mm, cm, in, pt, pc. Example: 3 pt + 5 cm.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .help("The measures apply to all pages of the document. Millimeters, centimeters, inches, points and picas (also 1p6) are accepted, with arithmetic such as 210 − 2 × 25.")
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
            line("Title") { Text(info.title).foregroundStyle(info.title == "untitled" ? .secondary : .primary) }
            line("Role") {
                HStack(spacing: 4) {
                    TextField("", text: $roleText)
                        .frame(maxWidth: 150)
                        .focused($editingRole)
                        .onSubmit { commitRole() }
                        .onChange(of: editingRole) { _, focused in if !focused { commitRole() } }
                    Menu {
                        ForEach(Typesetting.Section.Role.builtIn, id: \.self) { role in Button(role) { setRole(role) } }
                    } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton).hoverable().menuIndicator(.hidden).fixedSize()
                }
            }
            .help("The role says what the section is, apart from its depth and the style of its title. Choose one or type it.")
            line("Starts") {
                Picker("", selection: Binding(get: { info.start }, set: { setStart($0) })) {
                    Text("continuously").tag(SectionStart.continuous)
                    Text("on a new page").tag(SectionStart.newPage)
                    Text("on the next odd page").tag(SectionStart.oddPage)
                }
                .labelsHidden()
                .fixedSize()
            }
            .help("Following sections of the same role inherit this choice.")
            VStack(alignment: .leading, spacing: 8) {
                typePicker("Pages", \.pages, inherited: "as the outer section")
                typePicker("Even pages", \.evenPages, inherited: "as the others")
                typePicker("First page", \.firstPage, inherited: "as the others")
            }
            .help("Types are defined in the Pages tab. Pages and even pages also apply to inner sections; the first page only to this one.")
            line("Page numbers") {
                Picker("", selection: Binding(get: { info.pageNumbering }, set: { setPageNumbering($0) })) {
                    Text("continue").tag(String?.none)
                    ForEach(info.listNames, id: \.self) { Text("restart with “\($0)”").tag(Optional($0)) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .help("Numbering restarts from the first page with the chosen list and continues in the following sections until the next restart.")
            line("Level") {
                HStack(spacing: 8) {
                    Text("\(info.depth)")
                    Button("Out") { move(-1) }.disabled(!info.canMoveOutside)
                    Button("In") { move(1) }.disabled(!info.canMoveInside)
                }
                .controlSize(.small)
            }
            .help("The section moves with its inner sections. In: it becomes the last inner section of the previous one. Out: the following siblings become its inner sections.")
            line("Contains") {
                Text("\(info.paragraphs) \(info.paragraphs == 1 ? "paragraph" : "paragraphs"), \(info.sections) \(info.sections == 1 ? "inner section" : "inner sections")")
            }
            Button("Remove Section") { remove() }
                .controlSize(.small)
                .help("The title stays as a paragraph; the text goes to the previous section, inner sections move up a level")
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
                    Text("\(current) (no longer exists)").tag(Optional(current))
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
            Text("Page Setup").font(.headline)
            PageSetupForm(setup: model.setup) { transform in
                var page = model.setup
                transform(&page)
                if let page = PageSetupForm.checked(page) { model.setup = page }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.finish?(nil) }.keyboardShortcut(.cancelAction)
                Button("OK") { model.finish?(model.setup) }.keyboardShortcut(.defaultAction).buttonStyle(.hover(.prominent))
            }
        }
        .padding(18)
        .frame(width: 400)
    }
}

// MARK: - Provenienza

extension ValueSource {
    /// Il nome breve della provenienza, per la legenda e per distinguere i pallini.
    var legendTitle: String {
        switch self {
        case .document: "document"
        case .style: "style"
        case .own: "set here"
        case .rule: "rule"
        }
    }
}

/// Il pallino della provenienza: vuoto per il documento, pieno nel colore dello stile, di ciò che è dato qui o della regola.
struct SourceDot: View {
    let source: ValueSource
    var size: CGFloat = 9

    var body: some View {
        Group {
            switch source {
            case .document: Circle().strokeBorder(Color(nsColor: Theme.secondary), lineWidth: 1.5)
            case .style: Circle().fill(Color(nsColor: Theme.accent))
            case .own: Circle().fill(Color(nsColor: Theme.ownSource))
            case .rule: Circle().fill(Color(nsColor: Theme.ruleSource))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Una fila che va a capo: gli elementi uno dopo l'altro, e su una riga nuova quando non ci stanno più.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += line + lineSpacing; x = 0; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
