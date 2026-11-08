import AppKit
import SwiftUI
import Typesetting

extension EditorWindowController {
    func applyStyleBoard(base: StyleSheet, updated: StyleSheet) -> String? {
        self.definitionsPanel.flushPending()
        self.flushStyleChanges()
        guard self.settings.styles == base else {
            return "The document's styles have changed. Reload the composer before applying."
        }
        self.endUndoStep(next: .none)
        let undo = (self.document as? NSDocument)?.undoManager
        undo?.beginUndoGrouping()
        self.changeStyles(to: updated, restyle: true, actionName: "Style Formulas")
        undo?.endUndoGrouping()
        undo?.setActionName("Style Formulas")
        return nil
    }

    @objc func openStyleComposer(_ sender: Any?) { showStyleComposer() }

    func showStyleComposer(style name: String? = nil) {
        if let controller = composerController {
            if let name { composerModel?.showingStyles = true; composerModel?.selectStyle(name) }
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        definitionsPanel.flushPending()
        flushStyleChanges()
        let range = TextStyling.bodyParagraph(in: store, at: selection.range.location).range
        let sample = store.attributedSubstring(from: range)
        let owner = range.length > 0 ? sample.attribute(.paragraphStyleName, at: 0, effectiveRange: nil) as? String : nil
        let model = ComposerBoardModel(sheet: settings.styles,
                                       owner: owner, sample: sample.string, resolver: fontRoleResolver,
                                       documentBase: settings.formulaBase ?? TextStyling.styleBase,
                                       wordOwner: range.length > 0 ? sample.attribute(.wordStyleName, at: 0, effectiveRange: nil) as? String : nil)
        composerModel = model
        if let name { model.selectStyle(name) }
        model.commit = { [weak self] base, updated in
            guard let self else { return "The document was closed." }
            return self.applyStyleBoard(base: base, updated: updated)
        }
        model.reload = { [weak self] in
            guard let self else { return nil }
            self.definitionsPanel.flushPending()
            self.flushStyleChanges()
            return self.settings.styles
        }
        let board = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        board.title = "Style Composer · " + ((document as? NSDocument)?.displayName ?? "Document")
        board.minSize = NSSize(width: 740, height: 480)
        board.isReleasedWhenClosed = false
        board.backgroundColor = Theme.desk
        board.contentViewController = NSHostingController(rootView: ComposerBoard(model: model).themed())
        board.setContentSize(NSSize(width: 1000, height: 700))
        board.center()
        let controller = NSWindowController(window: board)
        composerController = controller
        controller.showWindow(nil)
        board.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ComposerBoardModel: ObservableObject {
    enum Section: String { case styles, selections, reusable }
    @Published var section = Section.styles
    var showingStyles: Bool {
        get { section == .styles }
        set { section = newValue ? .styles : .selections }
    }
    @Published var previewFirstOnPage = false
    @Published var previewSequenceStart = false
    @Published var previewPreviousStyle: String?
    @Published var previewLineCount = 1
    @Published var previewLastLineFill = 100.0
    @Published var previewHyphens = 0
    @Published var selectedStyle: String?
    @Published var previewRole: FontRole? = nil
    @Published var sheet: StyleSheet
    @Published var sample: String
    @Published var problem: String?
    @Published var incomplete: Set<UUID> = []
    private var cleanDraft: StyleSheet
    private var isApplying = false
    private(set) var baseSheet: StyleSheet
    let owner: String?
    let resolver: FontRoleResolver
    let documentBase: CharacterStyle
    let wordOwner: String?
    var commit: ((StyleSheet, StyleSheet) -> String?)?
    var reload: (() -> StyleSheet?)?

    init(sheet: StyleSheet, owner: String?, sample: String, resolver: FontRoleResolver = FontRoleResolver(),
         documentBase: CharacterStyle = TextStyling.styleBase, wordOwner: String? = nil) {
        self.sheet = sheet
        self.cleanDraft = sheet
        self.selectedStyle = owner ?? sheet.styles.first?.name
        baseSheet = sheet
        self.owner = owner
        self.resolver = resolver
        self.documentBase = documentBase
        self.wordOwner = wordOwner
        self.sample = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.sample.isEmpty { self.sample = "Every word finds its place." }
    }

    var dirty: Bool { sheet != baseSheet }
    var validationIssue: String? {
        let formulaNames = sheet.reusableFormulas.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if formulaNames.contains("") || Set(formulaNames).count != formulaNames.count {
            return "Give each reusable formula a different name."
        }
        if (try? ReusableFormulaLibrary(definitions: sheet.reusableFormulas).validate()) == nil {
            do { try ReusableFormulaLibrary(definitions: sheet.reusableFormulas).validate() } catch { return sheet.reusableProblem(error) }
        }
        let names = sheet.selections.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !incomplete.isEmpty || names.contains("") || Set(names).count != names.count {
            return "Complete the operations and give the shared selections different names."
        }
        for style in sheet.styles {
            guard style.formulas.allSatisfy({ (try? $0.validate(for: style.target)) != nil }) else {
                return "Check the properties and arguments of the formulas of “" + style.name + "”."
            }
            if let problem = style.writes.lazy.compactMap(\.problem).first {
                return "“" + style.name + "” writes a result that cannot be computed: " + problem
            }
            if dirty || (showingStyles && style.name == selectedStyle) {
                if (try? preview(style)) == nil {
                    return "The style “" + style.name + "” produces no valid result on the sample. Check fonts and measures."
                }
            }
        }
        return sheet.formulaReferenceProblem()
    }
    var valid: Bool { validationIssue == nil }
    func selectStyle(_ name: String) {
        guard let i = sheet.styles.firstIndex(where: { $0.name == name }) else { return }
        selectedStyle = name
        let previous = sheet.styles[i]
        let converted = sheet.materializingFormulas(of: name) ?? previous
        if let j = cleanDraft.styles.firstIndex(where: { $0.name == name }), cleanDraft.styles[j] == previous {
            cleanDraft.styles[j] = converted
        }
        sheet.styles[i] = converted
    }

    func updateFormula(_ id: UUID, operation: StylePropertyOperation) {
        guard let i = sheet.styles.firstIndex(where: { $0.name == selectedStyle }),
              let j = sheet.styles[i].formulas.firstIndex(where: { $0.id == id }) else { return }
        var formula = sheet.styles[i].formulas[j]
        if operation.property != formula.operation.property, operation.property.isDirective {
            formula.target = .paragraph
            formula.when = operation.property == .pageStartSpacing ? StyleCondition(position: .firstOnPage) : StyleCondition()
        }
        if formula.operation.property != operation.property { formula.binding = nil }
        formula.operation = operation
        if operation.property == .applyStyle, case .styleName(let name) = operation.argument, let name,
           sheet.style(named: name)?.target == .paragraph { formula.target = .paragraph }
        guard (try? formula.validate(for: sheet.styles[i].target)) != nil else { return }
        sheet.styles[i].formulas[j] = formula
    }

    func updateQualifiers(_ id: UUID, when: StyleCondition? = nil, target: TextRule.Target? = nil) {
        guard let i = sheet.styles.firstIndex(where: { $0.name == selectedStyle }),
              let j = sheet.styles[i].formulas.firstIndex(where: { $0.id == id }) else { return }
        var formula = sheet.styles[i].formulas[j]
        if let when { formula.when = when }
        if let target { formula.target = target }
        guard (try? formula.validate(for: sheet.styles[i].target)) != nil else { return }
        sheet.styles[i].formulas[j] = formula
    }

    var previewContext: TextRule.ParagraphContext {
        TextRule.ParagraphContext(styleName: selectedStyle, previousStyleName: previewPreviousStyle,
            isSequenceStart: previewSequenceStart, isFirstOnPage: previewFirstOnPage)
    }
    var previewFacts: TextRule.NaturalFacts {
        StyleCondition.previewFacts(sample, lines: previewLineCount, lastLineFill: previewLastLineFill, hyphens: previewHyphens)
    }

    func addStyleFormula() {
        guard let name = selectedStyle else { return }
        selectStyle(name)
        guard let i = sheet.styles.firstIndex(where: { $0.name == name }) else { return }
        sheet.styles[i].formulas.append(StyleFormula(operation: StylePropertyOperation(.set, .size, .length(12, .points))))
    }

    func removeStyleFormula(_ id: UUID) {
        guard let i = sheet.styles.firstIndex(where: { $0.name == selectedStyle }) else { return }
        sheet.styles[i].formulas.removeAll { $0.id == id }
    }

    func moveStyleFormula(_ id: UUID, by offset: Int) {
        guard let i = sheet.styles.firstIndex(where: { $0.name == selectedStyle }),
              let j = sheet.styles[i].formulas.firstIndex(where: { $0.id == id }),
              let peer = sheet.styles[i].formulas.indices.filter({ sheet.styles[i].formulas[$0].phase == sheet.styles[i].formulas[j].phase }).firstIndex(of: j) else { return }
        let peers = sheet.styles[i].formulas.indices.filter { sheet.styles[i].formulas[$0].phase == sheet.styles[i].formulas[j].phase }
        guard peers.indices.contains(peer + offset) else { return }
        sheet.styles[i].formulas.swapAt(j, peers[peer + offset])
    }

    private func preview(_ style: NamedStyle, in sheet: StyleSheet) throws -> StylePredicateState {
        let character = previewRole.flatMap { resolver.applying(role: $0, to: documentBase) } ?? documentBase
        var input = StylePredicateState(character: character)
        if style.target != .paragraph, let owner, sheet.style(named: owner)?.target == .paragraph {
            input = try sheet.values(of: owner).evaluatingFormulas(from: input, resolver: resolver, context: previewContext, facts: previewFacts)
        }
        if style.target == .character, let wordOwner, sheet.style(named: wordOwner)?.target == .word {
            input = try sheet.values(of: wordOwner).evaluatingFormulas(from: input, resolver: resolver, context: previewContext, facts: previewFacts)
        }
        return try sheet.values(of: style.name).evaluatingFormulas(from: input, resolver: resolver, context: previewContext, facts: previewFacts)
    }

    func preview(_ style: NamedStyle) throws -> StylePredicateState { try preview(style, in: sheet) }

    func formulaStates(_ style: NamedStyle) throws -> [StyleFormulaTrace] {
        let character = previewRole.flatMap { resolver.applying(role: $0, to: documentBase) } ?? documentBase
        var input = StylePredicateState(character: character)
        if style.target != .paragraph, let owner, sheet.style(named: owner)?.target == .paragraph {
            input = try sheet.values(of: owner).evaluatingFormulas(from: input, resolver: resolver, context: previewContext, facts: previewFacts)
        }
        if style.target == .character, let wordOwner, sheet.style(named: wordOwner)?.target == .word {
            input = try sheet.values(of: wordOwner).evaluatingFormulas(from: input, resolver: resolver, context: previewContext, facts: previewFacts)
        }
        return try sheet.values(of: style.name).formulaTrace(from: input, resolver: resolver, context: previewContext, facts: previewFacts)
    }

    /// Una modifica esterna aggiorna la bacheca solo se non sovrascrive lavoro dell'autore.
    func documentChanged(sheet updated: StyleSheet) {
        guard !isApplying, updated != baseSheet else { return }
        guard sheet == cleanDraft else {
            problem = "The document's styles have changed. The draft is kept; reload before applying."
            return
        }
        install(sheet: updated)
    }

    private func install(sheet updated: StyleSheet) {
        sheet = updated
        cleanDraft = updated; baseSheet = updated
        incomplete = []; problem = nil
        if showingStyles {
            if let name = selectedStyle, updated.style(named: name) != nil { selectStyle(name) }
            else if let name = updated.styles.first?.name { selectStyle(name) }
            else { selectedStyle = nil }
        }
    }

    func addSelection() {
        var n = 1
        while sheet.selections.contains(where: { $0.name == "Formula \(n)" }) { n += 1 }
        let item = WordSelection(name: "Formula \(n)")
        sheet.selections.append(item)
        incomplete.insert(item.id)
    }
    func addReusableFormula() {
        var n = 1
        while sheet.reusableFormulas.contains(where: { $0.name == "Formula \(n)" }) { n += 1 }
        sheet.reusableFormulas.append(ReusableFormula(name: "Formula \(n)", resultType: .number, expression: .constant(.number(0))))
    }
    func removeReusableFormula(_ id: UUID) {
        let remaining = sheet.reusableFormulas.filter { $0.id != id }
        var candidate = sheet; candidate.reusableFormulas = remaining
        guard (try? candidate.resolvingReusable()) != nil else {
            problem = "The formula is used by another definition: remove that link first."
            return
        }
        sheet.reusableFormulas = remaining
        problem = nil
    }
    func removeSelection(_ id: UUID) {
        sheet.selections.removeAll { $0.id == id }
        incomplete.remove(id)
    }
    func apply() {
        guard valid, dirty else { return }
        var updated = sheet
        for i in updated.selections.indices {
            updated.selections[i].name = updated.selections[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for i in updated.reusableFormulas.indices {
            updated.reusableFormulas[i].name = updated.reusableFormulas[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let commit else { return }
        isApplying = true
        defer { isApplying = false }
        problem = commit(baseSheet, updated)
        if problem == nil { sheet = updated; cleanDraft = updated; baseSheet = updated }
    }
    func discard() {
        guard let current = reload?() else { return }
        install(sheet: current)
    }
}

struct ComposerPill: View {
    let title: String
    var placeholder = false
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Color(nsColor: placeholder ? Theme.secondary : Theme.glyph))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(nsColor: hovered ? Theme.hoverBottom : Theme.controlBottom))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: hovered ? Theme.hoverLine : Theme.controlLine)))
        .onHover { hovered = $0 }
    }
}

/// I pulsanti del compositore, con le stesse risposte di `BandButton`: passaggio, pressione e stato disattivato.
/// `prominent` è l'azione principale della finestra (Apply to Document), nell'azzurro pieno dei pulsanti attivi.
struct ComposerButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, prominent: prominent)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let hover = hovered && isEnabled
            let (fill, edge, ink): (NSColor, NSColor, NSColor) =
                if configuration.isPressed { (Theme.pressedBottom, Theme.hoverLine, Theme.glyph) }
                else if prominent && isEnabled { (hover ? Theme.activeHoverBottom : Theme.activeBottom, Theme.accent, Theme.accentInk) }
                else if hover { (Theme.hoverBottom, Theme.hoverLine, Theme.glyph) }
                else { (Theme.controlBottom, Theme.controlLine, isEnabled ? Theme.glyph : Theme.secondary) }
            configuration.label.padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(Color(nsColor: ink).opacity(isEnabled ? 1 : 0.45))
                .background(Color(nsColor: fill))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: edge)))
                .contentShape(RoundedRectangle(cornerRadius: 3))
                .onHover { hovered = $0 }
        }
    }
}

struct ComposerBoard: View {
    @ObservedObject var model: ComposerBoardModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Style Composer").font(.title3.weight(.semibold))
                Spacer()
                Picker("View", selection: $model.section) {
                    Text("Styles").tag(ComposerBoardModel.Section.styles)
                    Text("Selections").tag(ComposerBoardModel.Section.selections)
                    Text("Formulas").tag(ComposerBoardModel.Section.reusable)
                }.pickerStyle(.segmented).frame(width: 300)
                if model.section == .selections {
                    Button { model.addSelection() } label: { Label("Formula", systemImage: "plus") }
                }
                if model.section == .reusable {
                    Button { model.addReusableFormula() } label: { Label("Formula", systemImage: "plus") }
                }
            }.padding(.horizontal, 16).padding(.vertical, 10).background(Color(nsColor: Theme.bar))
            if model.showingStyles {
                ActionComposer(model: model)
            } else if model.section == .selections {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.sheet.selections.isEmpty {
                            Button("Add a Selection") { model.addSelection() }.padding(30)
                        }
                        ForEach(model.sheet.selections) { selection in card(selection) }
                    }.padding(24).frame(minWidth: 710, alignment: .leading)
                }.background(Color(nsColor: Theme.desk))
            }
            if model.section == .reusable {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.sheet.reusableFormulas.isEmpty { Text("Add a reusable formula.").foregroundStyle(.secondary) }
                        ForEach(model.sheet.reusableFormulas) { formula in reusableCard(formula) }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.background(Color(nsColor: Theme.desk))
            }
            if !model.showingStyles { bottomBar }
        }
        .buttonStyle(ComposerButtonStyle())
    }

    /// Fuori dal compositore delle azioni (che ha la sua anteprima): il testo di prova, lo stato e i comandi.
    private var bottomBar: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sample text").foregroundStyle(.secondary)
                    TextField("Write a paragraph", text: $model.sample).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(model.problem ?? (model.validationIssue ?? (model.dirty ? "Changes to apply to the document" : "Composer up to date")))
                        .font(.caption).foregroundStyle(Color(nsColor: model.problem == nil ? Theme.secondary : Theme.warn))
                    Spacer()
                    Button("Reload from Document") { model.discard() }
                        .help("Replaces the drafts with the document's current definitions")
                    Button("Apply to Document") { model.apply() }
                        .buttonStyle(ComposerButtonStyle(prominent: true))
                        .disabled(!model.dirty || !model.valid)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }.padding(16).background(Color(nsColor: Theme.bar))
    }

    private func sourceTitle(_ source: WordSelection.Source) -> String {
        switch source {
        case .words: "All words"
        case .capitals: "Capitalized abbreviations"
        case .numbers: "Numbers"
        }
    }

    private func reusableCard(_ formula: ReusableFormula) -> some View {
        ReusableDefinitionEditor(definition: Binding(get: { model.sheet.reusableFormulas.first { $0.id == formula.id } ?? formula }, set: { updated in
            if let i = model.sheet.reusableFormulas.firstIndex(where: { $0.id == formula.id }) { model.sheet.reusableFormulas[i] = updated }
        }), definitions: model.sheet.reusableFormulas, remove: { model.removeReusableFormula(formula.id) })
    }

    private func selectionBinding<T>(_ id: UUID, _ path: WritableKeyPath<WordSelection, T>, fallback: T) -> Binding<T> {
        Binding(get: { model.sheet.selections.first { $0.id == id }?[keyPath: path] ?? fallback },
                set: { value in
                    guard let i = model.sheet.selections.firstIndex(where: { $0.id == id }) else { return }
                    model.sheet.selections[i][keyPath: path] = value
                })
    }

    private func card(_ item: WordSelection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Formula name", text: selectionBinding(item.id, \.name, fallback: item.name))
                    .font(.headline).textFieldStyle(.plain).frame(width: 300)
                Spacer()
                Button { model.removeSelection(item.id) } label: { Image(systemName: "trash") }
                    .help("Remove the selection from the draft")
            }
            HStack(spacing: 10) {
                Menu {
                    Text("Starting object")
                    Button("This paragraph") {}
                } label: { ComposerPill(title: "This paragraph") }
                arrow
                Menu {
                    ForEach(WordSelection.Source.allCases, id: \.self) { source in
                        Button("Collect · " + sourceTitle(source)) {
                            selectionBinding(item.id, \.source, fallback: source).wrappedValue = source
                            model.incomplete.remove(item.id)
                        }
                    }
                } label: {
                    ComposerPill(title: model.incomplete.contains(item.id) ? "＋ Predicate" : "Collect · " + sourceTitle(item.source),
                                 placeholder: model.incomplete.contains(item.id))
                }
                if !model.incomplete.contains(item.id) {
                    arrow
                    ComposerPositionPill(index: selectionBinding(item.id, \.index, fallback: item.index))
                    arrow
                    Text("Word?").font(.caption).foregroundStyle(.secondary)
                }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: true, vertical: false)
            if !model.incomplete.contains(item.id) {
                Text(item.preview(in: model.sample).map { "Result on the sample   “\($0)”" } ?? "No word at this position · effects suspended")
                    .foregroundStyle(Color(nsColor: Theme.glyph))
                Text("A style formula can act on this selection: choose “\(item.name)” in the formula's “On” menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(width: 820, alignment: .leading)
        .background(Color(nsColor: Theme.side))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: Theme.line)))
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.secondary))
    }

}

private struct ComposerPositionPill: View {
    @Binding var index: Int
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        Menu {
            ForEach(1...10, id: \.self) { n in
                Button("At position \(n)") { index = n }
            }
            Divider()
            Button("Other Position…") { text = String(index); editing = true }
        } label: { ComposerPill(title: "Choose · \(index)") }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Word position").font(.headline)
                TextField("Starting from 1", text: $text).frame(width: 180)
                Button("Use This Position") {
                    if let value = Int(text), value > 0 { index = value; editing = false }
                }
                .disabled(Int(text).map { $0 > 0 } != true)
            }.padding(16).buttonStyle(ComposerButtonStyle())
        }
    }
}

extension StylePredicate {
    var title: String {
        switch self {
        case .set: "Set"
        case .add: "Add"
        case .subtract: "Subtract"
        }
    }
}

extension StyleProperty {
    var title: String {
        switch self {
        case .pageStartSpacing: "Page-start distance"
        case .openingDistance: "Opening distance"
        case .opensSection: "Opens section"
        case .nextStyle: "Style after Return"
        case .outlineLevel: "Heading level"
        case .applyStyle: "Target style"
        case .keepWithNext: "Keep with next"
        case .keepTogether: "Keep lines together"
        case .orphanLines: "Lines at the bottom"
        case .widowLines: "Lines at the top"
        case .nextLines: "Lines of the next kept"
        case .previousLines: "Keep with previous lines"
        case .font: "Font"
        case .family: "Family"
        case .face: "Exact face"
        case .size: "Size"
        case .color: "Color"
        case .smallCaps: "Small caps"
        case .hyphenates: "Hyphenation"
        case .language: "Language"
        case .alignment: "Alignment"
        case .spaceBefore: "Space before"
        case .spaceAfter: "Space after"
        case .firstLineIndent: "First-line indent"
        case .leftIndent: "Left indent"
        case .rightIndent: "Right indent"
        case .lineSpacing: "Line spacing"
        }
    }
    var initialArgument: StyleArgument {
        switch self {
        case .pageStartSpacing: .pageStart(.distance(72))
        case .openingDistance: .length(0, .points)
        case .opensSection: .text(Section.Role.chapter)
        case .nextStyle: .styleName(nil)
        case .applyStyle: .styleName("Strong")
        case .outlineLevel: .integer(1)
        case .keepWithNext, .keepTogether: .boolean(true)
        case .orphanLines, .widowLines, .nextLines: .integer(2)
        case .previousLines: .integer(1)
        case .font: .font(.bold)
        case .family: .family("Hoefler Text")
        case .face: .face("HoeflerText-Regular")
        case .color: .color(nil)
        case .smallCaps: .smallCaps(.lowercase)
        case .hyphenates: .hyphenates(true)
        case .language: .language("it")
        case .alignment: .alignment(.natural)
        case .size: .length(12, .points)
        default: .length(0, .points)
        }
    }
}

func roleTitle(_ role: FontRole) -> String {
    switch role {
    case .regular: "Roman"
    case .italic: "Italic"
    case .bold: "Bold"
    case .boldItalic: "Bold italic"
    }
}

extension ComposerBoard {
    func summary(_ state: StylePredicateState, property: StyleProperty) -> String {
        let c = state.character, p = state.paragraph
        switch property {
        case .pageStartSpacing:
            if case .distance(let points) = state.directives.pageStartSpacing { return points.formatted() + " pt" }
            return "No distance"
        case .openingDistance: return (state.directives.openingDistance ?? 0).formatted() + " pt"
        case .opensSection: return state.directives.opensSection.flatMap { $0.isEmpty ? nil : $0 } ?? "No section"
        case .nextStyle: return state.directives.nextStyle.flatMap { $0.isEmpty ? nil : $0 } ?? "Same style"
        case .applyStyle: return state.directives.applyingStyle ?? "No treatment"
        case .outlineLevel: return String(p.outlineLevel ?? 0)
        case .keepWithNext: return state.directives.keeping.withNext == true ? "Yes" : "No"
        case .keepTogether: return state.directives.keeping.together == true ? "Yes" : "No"
        case .orphanLines: return String(state.directives.keeping.linesAtEnd ?? 1)
        case .widowLines: return String(state.directives.keeping.linesAtStart ?? 1)
        case .nextLines: return String(state.directives.keeping.nextLines ?? 1)
        case .previousLines: return String(state.directives.keeping.previousLines ?? 0)
        case .face: return c.fontName
        case .font: return model.resolver.role(of: c).map(roleTitle) ?? c.fontName
        case .family: return NSFont(name: c.fontName, size: CGFloat(c.size))?.familyName ?? c.fontName
        case .size: return c.size.formatted() + " pt"
        case .color: return c.color ?? "Automatic"
        case .smallCaps: return c.smallCaps.rawValue
        case .hyphenates: return c.hyphenates ? "On" : "Off"
        case .language: return c.language ?? "Document language"
        case .alignment: return p.alignment.title
        case .spaceBefore: return p.spaceBefore.formatted() + " pt"
        case .spaceAfter: return p.spaceAfter.formatted() + " pt"
        case .firstLineIndent: return p.firstLineIndent.formatted() + " pt"
        case .leftIndent: return p.leftIndent.formatted() + " pt"
        case .rightIndent: return p.rightIndent.formatted() + " pt"
        case .lineSpacing: return p.lineSpacing.formatted() + " pt"
        }
    }

    func phaseTitle(_ phase: StyleFormulaPhase) -> String {
        switch phase {
        case .base: "Base formatting"
        case .placement: "During placement"
        case .textContext: "After the base · text context"
        case .composition: "After the context · natural composition"
        case .assignment: "When the style is assigned"
        case .paragraphCreation: "When you press Return"
        }
    }

    func setParent(_ name: String, _ parent: String?) {
        guard let i = model.sheet.styles.firstIndex(where: { $0.name == name }) else { return }
        model.sheet.styles[i].basedOn = parent
    }

    @ViewBuilder func compatibleProperties(_ style: NamedStyle) -> some View {
        let v = style.values
        if v != StyleValues() {
            VStack(alignment: .leading, spacing: 5) {
                Text("Other preserved properties").font(.caption.weight(.semibold))
                if let role = v.opensSection { Text("Opens section · " + role) }
                if let level = v.outlineLevel { Text("Level · \(level)") }
                if let list = v.listName { Text("List · " + list) }
                if let distance = v.openingDistance { Text("Sequence opening · \(distance.formatted()) pt") }
                if v.pageStartSpacing != nil { Text("Page-start variant · set in the Styles tab") }
                if !v.keeping.isEmpty { Text("Line keeping · " + v.keeping.encoded) }
                if v.family != nil || v.italic != nil || v.bold != nil || v.features != nil || v.variations != nil || v.fontName != nil || v.opticalSize != nil {
                    Text("Advanced font choices · editable in the Styles tab")
                }
                if v.italic == false || v.bold == false { Text("Explicit exclusions of font traits · Styles tab") }
                if v.verticalPosition != nil || v.decorations != nil || v.graphite != nil || v.lineHeightMultiple != nil {
                    Text("Other typographic values · editable in the Styles tab")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FormulaArgumentPill: View {
    let operation: StylePropertyOperation
    let target: StyleTarget
    var styleNames: [String] = []
    let commit: (StyleArgument) -> Void
    @State private var editing = false
    @State private var text = ""

    private var title: String {
        switch operation.argument {
        case .boolean(let enabled): enabled ? "Yes" : "No"
        case .integer(let number): String(number)
        case .text(let value): value.isEmpty ? "None" : value
        case .styleName(let name): name ?? "Same style"
        case .pageStart(let spacing):
            switch spacing { case .disabled: "Off"; case .distance(let points): points.formatted() + " pt" }
        case .font(let role): roleTitle(role)
        case .length(let value, let unit): value.formatted() + " " + unit.rawValue
        case .family(let name), .face(let name): name
        case .language(let language): language ?? "Document language"
        case .color(let color): color ?? "Automatic"
        case .alignment(let alignment): alignment.title
        case .smallCaps(let mode): mode.rawValue
        case .hyphenates(let enabled): enabled ? "On" : "Off"
        }
    }
    /// Il valore come lo mostra la pastiglia (il compositore lo usa nel riassunto di un'azione richiusa).
    var titleText: String { title }

    private var editedArgument: StyleArgument? {
        switch operation.argument {
        case .length:
            return Length.points(from: text, defaultUnit: .points).map { .length(Double($0), .points) }
        case .pageStart: return Length.points(from: text, defaultUnit: .points).map { .pageStart(.distance(Double($0))) }
        case .integer: return Int(text).map(StyleArgument.integer)
        case .text: return .text(text)
        case .language: return .language(text.isEmpty ? nil : text)
        case .color: return .color(text.isEmpty ? nil : text)
        default: return nil
        }
    }
    private var validEdit: Bool {
        guard let value = editedArgument else { return false }
        let candidate = StyleFormula(operation: StylePropertyOperation(operation.predicate, operation.property, value))
        return (try? candidate.validate(for: target)) != nil
    }

    var body: some View {
        Menu {
            switch operation.argument {
            case .boolean:
                Button("Yes") { commit(.boolean(true)) }
                Button("No") { commit(.boolean(false)) }
            case .integer:
                ForEach((operation.property == .outlineLevel ? 0 : 1)...9, id: \.self) { n in Button(String(n)) { commit(.integer(n)) } }
            case .text:
                ForEach(["", Section.Role.part, Section.Role.chapter, Section.Role.section, Section.Role.appendix], id: \.self) { value in
                    Button(value.isEmpty ? "No section" : value) { commit(.text(value)) }
                }
                Button("Other Role…") { if case .text(let value) = operation.argument { text = value }; editing = true }
            case .styleName:
                // I nomi vengono forniti dalla bacheca per evitare riferimenti liberi.
                ForEach(styleNames, id: \.self) { name in Button(name) { commit(.styleName(name)) } }
                if operation.property == .nextStyle { Button("Same style") { commit(.styleName(nil)) } }
            case .pageStart:
                Button("Off") { commit(.pageStart(.disabled)) }
                ForEach([0, 36, 72, 108], id: \.self) { n in Button("\(n) pt") { commit(.pageStart(.distance(Double(n)))) } }
                Button("Other Distance…") { text = title; editing = true }
            case .font:
                ForEach(FontRole.allCases, id: \.self) { role in Button(roleTitle(role)) { commit(.font(role)) } }
            case .alignment:
                ForEach(ParagraphStyle.Alignment.allCases, id: \.self) { alignment in
                    Button(alignment.title) { commit(.alignment(alignment)) }
                }
            case .smallCaps:
                ForEach(SmallCaps.allCases, id: \.self) { mode in Button(mode.rawValue) { commit(.smallCaps(mode)) } }
            case .hyphenates:
                Button("On") { commit(.hyphenates(true)) }
                Button("Off") { commit(.hyphenates(false)) }
            case .face:
                ForEach(NSFontManager.shared.availableFonts.sorted(), id: \.self) { name in
                    Button(name) { commit(.face(name)) }
                }
            case .family:
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { name in
                    Button(name) { commit(.family(name)) }
                }
            case .length:
                Button("Edit Measure…") { text = title; editing = true }
                ForEach([0, 6, 12, 18, 24], id: \.self) { n in
                    if operation.property != .size || n > 0 {
                        Button("\(n) pt") { commit(.length(Double(n), .points)) }
                    }
                }
            case .language, .color:
                Button("Edit Value…") {
                    switch operation.argument {
                    case .language(let value), .color(let value): text = value ?? ""
                    default: break
                    }
                    editing = true
                }
                Button("Automatic / document") {
                    if operation.property == .color { commit(.color(nil)) } else { commit(.language(nil)) }
                }
            }
        } label: { ComposerPill(title: title) }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(operation.property.title).font(.headline)
                TextField("Value", text: $text).frame(width: 220)
                if case .length = operation.argument { Text("Accepted units · pt, mm, cm, in, pc").font(.caption) }
                Button("Use This Value") {
                    if validEdit, let value = editedArgument { commit(value); editing = false }
                }.disabled(!validEdit)
            }.padding(16).buttonStyle(ComposerButtonStyle())
        }
    }
}

struct FormulaNumberPill: View {
    let value: Double
    let commit: (Double) -> Void
    @State private var editing = false
    @State private var text = ""
    private var parsed: Double? {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite, number >= 0, number <= 1_000_000 else { return nil }
        return number
    }
    var body: some View {
        Menu {
            ForEach([0, 1, 2, 3, 5, 10, 50, 100], id: \.self) { n in Button(String(n)) { commit(Double(n)) } }
            Button("Other Value…") { text = String(value); editing = true }
        } label: { ComposerPill(title: value.formatted()) }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Value", text: $text).frame(width: 180)
                Button("Use This Value") { if let parsed { commit(parsed); editing = false } }.disabled(parsed == nil)
            }.padding(16).buttonStyle(ComposerButtonStyle())
        }
    }
}

struct FormulaQualifiers: View {
    @Binding var condition: StyleCondition
    @Binding var target: TextRule.Target
    let operation: StylePropertyOperation
    let styleNames: [String]
    let selections: [WordSelection]

    private func valid(_ condition: StyleCondition, _ target: TextRule.Target) -> Bool {
        (try? StyleFormula(operation: operation, when: condition, target: target).validate(for: .paragraph)) != nil
    }
    private var targetTitle: String { Self.title(of: target, selections: selections) }

    static func title(of target: TextRule.Target, selections: [WordSelection]) -> String {
        switch target {
        case .paragraph: "This paragraph"
        case .firstLetter: "First letter"
        case .firstWords(let count): "First \(count) words"
        case .firstSentence: "First sentence"
        case .firstLines(let count): "First \(count) lines"
        case .lastLine: "Last line"
        case .words(.capitals): "Capitalized abbreviations"
        case .words(.romanNumerals): "Roman numerals"
        case .words(.numbers): "Numbers"
        case .words(.listed): "Given words"
        case .selection(let id): selections.first { $0.id == id }?.name ?? "Shared selection"
        }
    }
    private func choose(_ position: TextRule.Position) {
        var candidate = condition; candidate.position = position
        if valid(candidate, target) { condition = candidate }
    }
    private func choose(_ measurement: TextRule.Condition?) {
        var candidate = condition; candidate.measurement = measurement
        if valid(candidate, target) { condition = candidate }
    }
    private func metricTitle(_ metric: TextRule.Condition.Property) -> String {
        switch metric {
        case .words: "Words"
        case .lines: "Lines"
        case .lastLineFill: "Last line %"
        case .hyphens: "Hyphenated lines"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("When").font(.caption).foregroundStyle(.secondary)
                Menu {
                    if valid(StyleCondition(position: .any, measurement: condition.measurement), target) {
                        Button("Always") { choose(TextRule.Position.any) }
                    }
                    if valid(StyleCondition(position: .firstOnPage, measurement: condition.measurement), target) {
                        Button("First on page") { choose(TextRule.Position.firstOnPage) }
                    }
                    if valid(StyleCondition(position: .sequenceStart, measurement: condition.measurement), target) {
                        Button("Sequence start") { choose(TextRule.Position.sequenceStart) }
                    }
                    if !operation.property.isDirective {
                        Menu("After style") {
                            ForEach(styleNames, id: \.self) { name in Button(name) { choose(TextRule.Position.firstAfter(name)) } }
                        }
                    }
                } label: { ComposerPill(title: StyleCondition(position: condition.position).summary) }.fixedSize()
                if !operation.property.isDirective {
                    Menu {
                        Button("No numeric condition") { choose(Optional<TextRule.Condition>.none) }
                        ForEach(TextRule.Condition.Property.allCases, id: \.self) { metric in
                            Button(metricTitle(metric)) { choose(TextRule.Condition(metric, .greaterOrEqual, metric == .lastLineFill ? 50 : 2)) }
                        }
                    } label: { ComposerPill(title: condition.measurement.map { metricTitle($0.property) } ?? "＋ Condition") }.fixedSize()
                    if let metric = condition.measurement {
                        Menu {
                            ForEach(TextRule.Condition.Comparison.allCases, id: \.self) { comparison in
                                Button(comparison.symbol) { choose(TextRule.Condition(metric.property, comparison, metric.value)) }
                            }
                        } label: { ComposerPill(title: metric.comparison.symbol) }.fixedSize()
                        FormulaNumberPill(value: metric.value) { choose(TextRule.Condition(metric.property, metric.comparison, $0)) }
                    }
                }
            }
            if !operation.property.isDirective {
                HStack(spacing: 8) {
                    Text("On").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        ForEach(Array([TextRule.Target.paragraph, .firstLetter, .firstWords(2), .firstSentence, .firstLines(1), .lastLine,
                                       .words(.capitals), .words(.romanNumerals), .words(.numbers)].enumerated()), id: \.offset) { _, candidate in
                            if valid(condition, candidate) {
                                Button(targetName(candidate)) { target = candidate }
                            }
                        }
                        ForEach(selections) { selection in
                            if valid(condition, .selection(selection.id)) { Button(selection.name) { target = .selection(selection.id) } }
                        }
                    } label: { ComposerPill(title: targetTitle) }.fixedSize()
                    if case .firstWords(let count) = target {
                        FormulaNumberPill(value: Double(count)) { if $0 >= 1, $0.rounded() == $0 { target = .firstWords(Int($0)) } }
                    }
                    if case .firstLines(let count) = target {
                        FormulaNumberPill(value: Double(count)) { if $0 >= 1, $0.rounded() == $0 { target = .firstLines(Int($0)) } }
                    }
                }
            }
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
    }
    private func targetName(_ target: TextRule.Target) -> String {
        switch target {
        case .paragraph: "This paragraph"
        case .firstLetter: "First letter"
        case .firstWords: "First words"
        case .firstSentence: "First sentence"
        case .firstLines: "First lines"
        case .lastLine: "Last line"
        case .words(.capitals): "Capitalized abbreviations"
        case .words(.romanNumerals): "Roman numerals"
        case .words(.numbers): "Numbers"
        default: "Selection"
        }
    }
}

extension ParagraphStyle.Alignment {
    /// Il nome dell'allineamento nel compositore.
    var title: String {
        switch self {
        case .natural: "Natural"
        case .left: "Left"
        case .right: "Right"
        case .center: "Center"
        case .justified: "Justified"
        case .decimal: "Decimal"
        }
    }
}
