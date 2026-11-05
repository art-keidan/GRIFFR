import AppKit
import SwiftUI
import Typesetting

extension EditorWindowController {
    func applyStyleBoard(base: StyleSheet, rules: [TextRule], updated: StyleSheet, updatedRules: [TextRule]) -> String? {
        self.definitionsPanel.flushPending()
        self.flushStyleChanges()
        guard self.settings.styles == base, self.settings.rules == rules else {
            return "Gli stili del documento sono cambiati. Ricarica la bacheca prima di applicare."
        }
        self.endUndoStep(next: .none)
        let undo = (self.document as? NSDocument)?.undoManager
        undo?.beginUndoGrouping()
        self.changeStyles(to: updated, restyle: true, actionName: "Formule degli stili")
        if updatedRules != self.settings.rules { self.changeRules(updatedRules, styles: updated) }
        undo?.endUndoGrouping()
        undo?.setActionName("Formule degli stili")
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
        let model = ComposerBoardModel(sheet: settings.styles, rules: settings.rules,
                                       owner: owner, sample: sample.string, resolver: fontRoleResolver,
                                       documentBase: settings.formulaBase ?? TextStyling.styleBase,
                                       wordOwner: range.length > 0 ? sample.attribute(.wordStyleName, at: 0, effectiveRange: nil) as? String : nil)
        composerModel = model
        if let name { model.selectStyle(name) }
        model.commit = { [weak self] base, rules, updated, updatedRules in
            guard let self else { return "Il documento è stato chiuso." }
            return self.applyStyleBoard(base: base, rules: rules, updated: updated, updatedRules: updatedRules)
        }
        model.reload = { [weak self] in
            guard let self else { return nil }
            self.definitionsPanel.flushPending()
            self.flushStyleChanges()
            return (self.settings.styles, self.settings.rules)
        }
        let board = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        board.title = "Bacheca degli stili · " + ((document as? NSDocument)?.displayName ?? "Documento")
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
    enum Section: String { case styles, selections, rules, reusable }
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
    @Published var rules: [TextRule]
    @Published var sample: String
    @Published var problem: String?
    @Published var incomplete: Set<UUID> = []
    private var cleanDraft: StyleSheet
    private var isApplying = false
    private(set) var baseSheet: StyleSheet
    private(set) var baseRules: [TextRule]
    let owner: String?
    let resolver: FontRoleResolver
    let documentBase: CharacterStyle
    let wordOwner: String?
    var commit: ((StyleSheet, [TextRule], StyleSheet, [TextRule]) -> String?)?
    var reload: (() -> (StyleSheet, [TextRule])?)?

    init(sheet: StyleSheet, rules: [TextRule], owner: String?, sample: String, resolver: FontRoleResolver = FontRoleResolver(),
         documentBase: CharacterStyle = TextStyling.styleBase, wordOwner: String? = nil) {
        self.sheet = sheet
        self.cleanDraft = sheet
        self.selectedStyle = owner ?? sheet.styles.first?.name
        self.rules = rules
        baseSheet = sheet
        baseRules = rules
        self.owner = owner
        self.resolver = resolver
        self.documentBase = documentBase
        self.wordOwner = wordOwner
        self.sample = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.sample.isEmpty { self.sample = "Ogni parola trova il proprio posto." }
    }

    var dirty: Bool { sheet != baseSheet || rules != baseRules }
    var appearances: [NamedStyle] {
        sheet.styles.filter { $0.target != .paragraph } +
        StyleSheet.ruleStyles.filter { $0.target != .paragraph && sheet.style(named: $0.name) == nil }
    }
    var validationIssue: String? {
        let formulaNames = sheet.reusableFormulas.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if formulaNames.contains("") || Set(formulaNames).count != formulaNames.count {
            return "Assegna un nome diverso a ogni formula riutilizzabile."
        }
        if (try? ReusableFormulaLibrary(definitions: sheet.reusableFormulas).validate()) == nil {
            do { try ReusableFormulaLibrary(definitions: sheet.reusableFormulas).validate() } catch { return sheet.reusableProblem(error) }
        }
        let names = sheet.selections.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !incomplete.isEmpty || names.contains("") || Set(names).count != names.count {
            return "Completa le operazioni e assegna nomi diversi alle selezioni condivise."
        }
        for style in sheet.styles {
            guard style.formulas.allSatisfy({ (try? $0.validate(for: style.target)) != nil }) else {
                return "Controlla proprietà e argomenti delle formule di «" + style.name + "»."
            }
            if dirty || (showingStyles && style.name == selectedStyle) {
                if (try? preview(style)) == nil {
                    return "Lo stile «" + style.name + "» non produce un risultato valido sul campione. Controlla font e misure."
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
    func documentChanged(sheet updated: StyleSheet, rules updatedRules: [TextRule]) {
        guard !isApplying, updated != baseSheet || updatedRules != baseRules else { return }
        guard sheet == cleanDraft, rules == baseRules else {
            problem = "Gli stili del documento sono cambiati. La bozza è conservata; ricarica prima di applicare."
            return
        }
        install(sheet: updated, rules: updatedRules)
    }

    private func install(sheet updated: StyleSheet, rules updatedRules: [TextRule]) {
        sheet = updated; rules = updatedRules
        cleanDraft = updated; baseSheet = updated; baseRules = updatedRules
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
            problem = "La formula è usata da un'altra definizione: rimuovi prima il collegamento."
            return
        }
        sheet.reusableFormulas = remaining
        problem = nil
    }
    func addEffect(_ id: UUID) {
        guard let appearance = appearances.first else { return }
        rules.append(TextRule(target: .selection(id), paragraphStyle: owner.flatMap { sheet.style(named: $0) == nil ? nil : $0 },
                              styleName: appearance.name))
    }
    func removeSelection(_ id: UUID) {
        sheet.selections.removeAll { $0.id == id }
        rules.removeAll { $0.target == .selection(id) }
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
        for rule in rules where updated.style(named: rule.styleName) == nil {
            if let style = StyleSheet.ruleStyles.first(where: { $0.name == rule.styleName }) {
                updated.styles.append(style)
            }
        }
        guard let commit else { return }
        isApplying = true
        defer { isApplying = false }
        problem = commit(baseSheet, baseRules, updated, rules)
        if problem == nil { sheet = updated; cleanDraft = updated; baseSheet = updated; baseRules = rules }
    }
    func discard() {
        guard let current = reload?() else { return }
        install(sheet: current.0, rules: current.1)
    }
}

private struct ComposerPill: View {
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

private struct ComposerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(Color(nsColor: Theme.glyph))
            .background(Color(nsColor: configuration.isPressed ? Theme.pressedBottom : Theme.controlBottom))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(nsColor: Theme.controlLine)))
    }
}

private struct ComposerBoard: View {
    @ObservedObject var model: ComposerBoardModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bacheca degli stili").font(.title2.weight(.semibold))
                    Text("Costruisci la formula scegliendo ogni pill. Riutilizza il risultato in più regole.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Vista", selection: $model.section) {
                    Text("Stili").tag(ComposerBoardModel.Section.styles)
                    Text("Selezioni").tag(ComposerBoardModel.Section.selections)
                    Text("Regole").tag(ComposerBoardModel.Section.rules)
                    Text("Formule").tag(ComposerBoardModel.Section.reusable)
                }.pickerStyle(.segmented).frame(width: 400)
                if model.section == .selections {
                    Button { model.addSelection() } label: { Label("Formula", systemImage: "plus") }
                }
                if model.section == .reusable {
                    Button { model.addReusableFormula() } label: { Label("Formula", systemImage: "plus") }
                }
            }.padding(20).background(Color(nsColor: Theme.bar))
            if model.showingStyles {
                HSplitView {
                    List(selection: Binding(get: { model.selectedStyle }, set: { name in
                        if let name { model.selectStyle(name) }
                    })) {
                        ForEach(model.sheet.styles, id: \.name) { style in
                            VStack(alignment: .leading) {
                                Text(style.name)
                                Text(style.target.rawValue).font(.caption).foregroundStyle(.secondary)
                            }.tag(Optional(style.name))
                        }
                    }.frame(minWidth: 170, idealWidth: 190, maxWidth: 230)
                    ScrollView([.horizontal, .vertical]) {
                        if let style = model.sheet.styles.first(where: { $0.name == model.selectedStyle }) {
                            realStyleCard(style).padding(24)
                        }
                    }.background(Color(nsColor: Theme.desk))
                }.onAppear { if let name = model.selectedStyle { model.selectStyle(name) } }
            } else if model.section == .selections {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.sheet.selections.isEmpty {
                            Button("Aggiungi una selezione") { model.addSelection() }.padding(30)
                        }
                        ForEach(model.sheet.selections) { selection in card(selection) }
                    }.padding(24).frame(minWidth: 710, alignment: .leading)
                }.background(Color(nsColor: Theme.desk))
            }
            if model.section == .rules {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.rules.isEmpty { Text("Le regole del documento compariranno qui.").padding(24) }
                        ForEach(model.rules.indices, id: \.self) { i in historicalRuleCard(i) }
                    }.padding(24)
                }.background(Color(nsColor: Theme.desk))
            }
            if model.section == .reusable {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.sheet.reusableFormulas.isEmpty { Text("Aggiungi una formula riutilizzabile.").foregroundStyle(.secondary) }
                        ForEach(model.sheet.reusableFormulas) { formula in reusableCard(formula) }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.background(Color(nsColor: Theme.desk))
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Testo di prova").foregroundStyle(.secondary)
                    TextField("Scrivi un capoverso", text: $model.sample).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text(model.problem ?? (model.validationIssue ?? (model.dirty ? "Modifiche da applicare al documento" : "Bacheca aggiornata")))
                        .font(.caption).foregroundStyle(Color(nsColor: model.problem == nil ? Theme.secondary : Theme.warn))
                    Spacer()
                    Button("Ricarica dal documento") { model.discard() }
                        .help("Sostituisce le bozze con le definizioni attuali del documento")
                    Button("Applica al documento") { model.apply() }
                        .disabled(!model.dirty || !model.valid)
                }
            }.padding(16).background(Color(nsColor: Theme.bar))
        }
        .buttonStyle(ComposerButtonStyle())
    }

    private func sourceTitle(_ source: WordSelection.Source) -> String {
        switch source {
        case .words: "Tutte le parole"
        case .capitals: "Sigle maiuscole"
        case .numbers: "Numeri"
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
                TextField("Nome della formula", text: selectionBinding(item.id, \.name, fallback: item.name))
                    .font(.headline).textFieldStyle(.plain).frame(width: 300)
                Spacer()
                Button { model.removeSelection(item.id) } label: { Image(systemName: "trash") }
                    .help("Togli la formula e le sue regole dalla bozza")
            }
            HStack(spacing: 10) {
                Menu {
                    Text("Oggetto di partenza")
                    Button("Questo paragrafo") {}
                } label: { ComposerPill(title: "Questo paragrafo") }
                arrow
                Menu {
                    ForEach(WordSelection.Source.allCases, id: \.self) { source in
                        Button("Raccogli · " + sourceTitle(source)) {
                            selectionBinding(item.id, \.source, fallback: source).wrappedValue = source
                            model.incomplete.remove(item.id)
                        }
                    }
                } label: {
                    ComposerPill(title: model.incomplete.contains(item.id) ? "＋ Predicato" : "Raccogli · " + sourceTitle(item.source),
                                 placeholder: model.incomplete.contains(item.id))
                }
                if !model.incomplete.contains(item.id) {
                    arrow
                    ComposerPositionPill(index: selectionBinding(item.id, \.index, fallback: item.index))
                    arrow
                    Text("Parola?").font(.caption).foregroundStyle(.secondary)
                }
            }.menuStyle(.borderlessButton).fixedSize(horizontal: true, vertical: false)
            if !model.incomplete.contains(item.id) {
                Text(item.preview(in: model.sample).map { "Risultato sul campione   «\($0)»" } ?? "Nessuna parola in questa posizione · effetti sospesi")
                    .foregroundStyle(Color(nsColor: Theme.glyph))
                ForEach(model.rules.indices.filter { model.rules[$0].target == .selection(item.id) }, id: \.self) { i in
                    effectRow(i)
                }
                Button { model.addEffect(item.id) } label: { Label("Collega un trattamento", systemImage: "plus") }
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

    private func effectRow(_ i: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(Color(nsColor: Theme.secondary))
            Menu {
                Button("Qualsiasi stile di paragrafo") { model.rules[i].paragraphStyle = nil }
                ForEach(model.sheet.styles.filter { $0.target == .paragraph }, id: \.name) { style in
                    Button(style.name) { model.rules[i].paragraphStyle = style.name }
                }
            } label: { ComposerPill(title: model.rules[i].paragraphStyle.map { "Nei paragrafi · " + $0 } ?? "In tutti i paragrafi") }
            arrow
            Menu {
                ForEach(model.appearances, id: \.name) { style in
                    Button("Applica " + style.name) { model.rules[i].styleName = style.name }
                }
            } label: { ComposerPill(title: "Tratta con · " + model.rules[i].styleName) }
            Menu {
                Button(model.rules[i].isEnabled ? "Sospendi il trattamento" : "Attiva il trattamento") { model.rules[i].isEnabled.toggle() }
                Button("Togli il trattamento") { model.rules.remove(at: i) }
            } label: { ComposerPill(title: model.rules[i].isEnabled ? "Attivo" : "Sospeso") }
        }.menuStyle(.borderlessButton).fixedSize(horizontal: true, vertical: false)
    }
}

private struct ComposerPositionPill: View {
    @Binding var index: Int
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        Menu {
            ForEach(1...10, id: \.self) { n in
                Button("In posizione \(n)") { index = n }
            }
            Divider()
            Button("Altra posizione…") { text = String(index); editing = true }
        } label: { ComposerPill(title: "Scegli · \(index)") }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Posizione della parola").font(.headline)
                TextField("A partire da 1", text: $text).frame(width: 180)
                Button("Usa questa posizione") {
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
        case .set: "Imposta"
        case .add: "Aggiungi"
        case .subtract: "Sottrai"
        }
    }
}

extension StyleProperty {
    var title: String {
        switch self {
        case .pageStartSpacing: "Distanza a inizio pagina"
        case .openingDistance: "Distanza di apertura"
        case .opensSection: "Apre sezione"
        case .nextStyle: "Stile dopo Invio"
        case .outlineLevel: "Livello del titolo"
        case .applyStyle: "Stile dei destinatari"
        case .keepWithNext: "Tieni con il prossimo"
        case .keepTogether: "Paragrafo indivisibile"
        case .orphanLines: "Righe in fondo"
        case .widowLines: "Righe in cima"
        case .font: "Font"
        case .family: "Famiglia"
        case .face: "Faccia precisa"
        case .size: "Corpo"
        case .color: "Colore"
        case .smallCaps: "Maiuscoletto"
        case .hyphenates: "Sillabazione"
        case .language: "Lingua"
        case .alignment: "Allineamento"
        case .spaceBefore: "Spazio prima"
        case .spaceAfter: "Spazio dopo"
        case .firstLineIndent: "Rientro prima riga"
        case .leftIndent: "Rientro sinistro"
        case .rightIndent: "Rientro destro"
        case .lineSpacing: "Spazio fra righe"
        }
    }
    var initialArgument: StyleArgument {
        switch self {
        case .pageStartSpacing: .pageStart(.distance(72))
        case .openingDistance: .length(0, .points)
        case .opensSection: .text(Section.Role.chapter)
        case .nextStyle: .styleName(nil)
        case .applyStyle: .styleName("Forte")
        case .outlineLevel: .integer(1)
        case .keepWithNext, .keepTogether: .boolean(true)
        case .orphanLines, .widowLines: .integer(2)
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
    case .regular: "Tondo"
    case .italic: "Corsivo"
    case .bold: "Grassetto"
    case .boldItalic: "Grassetto corsivo"
    }
}

private extension ComposerBoard {
    func realStyleCard(_ style: NamedStyle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(style.name).font(.title2.weight(.semibold))
            HStack {
                Text("Eredita da").foregroundStyle(.secondary)
                Menu {
                    Button("Nessuno") { setParent(style.name, nil) }
                    ForEach(model.sheet.possibleParents(of: style.name), id: \.self) { name in
                        Button(name) { setParent(style.name, name) }
                    }
                } label: { ComposerPill(title: style.basedOn ?? "Documento") }
            }.menuStyle(.borderlessButton)
            Text(style.target == .paragraph ? "Questo paragrafo" : style.target == .word ? "Questa parola" : "Caratteri destinatari")
                .font(.headline).foregroundStyle(Color(nsColor: Theme.glyph))
            let states = (try? model.formulaStates(style)) ?? []
            ForEach(Array(style.formulas.enumerated()).sorted { $0.element.phase == $1.element.phase ? $0.offset < $1.offset : $0.element.phase < $1.element.phase }, id: \.element.id) { i, formula in
                VStack(alignment: .leading, spacing: 4) {
                    let peers = style.formulas.indices.filter { style.formulas[$0].phase == formula.phase }
                    Text(phaseTitle(formula.phase)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    formulaRow((try? formula.resolved(in: ReusableFormulaLibrary(definitions: model.sheet.reusableFormulas))) ?? formula, target: style.target, index: peers.firstIndex(of: i) ?? 0, count: peers.count)
                        .disabled(formula.binding != nil)
                    if let type = formula.bindingType {
                        Toggle("Calcola con una formula", isOn: Binding(get: { formula.binding != nil }, set: { enabled in
                            guard let si = model.sheet.styles.firstIndex(where: { $0.name == style.name }), let fi = model.sheet.styles[si].formulas.firstIndex(where: { $0.id == formula.id }) else { return }
                            if !enabled, let resolved = try? formula.resolved(in: ReusableFormulaLibrary(definitions: model.sheet.reusableFormulas)) { model.sheet.styles[si].formulas[fi].operation = resolved.operation }
                            model.sheet.styles[si].formulas[fi].binding = enabled ? .constant(formula.bindingSeed) : nil
                        }))
                        if let binding = formula.binding {
                            FormulaExpressionEditor(expression: Binding(get: { binding }, set: { value in
                                guard let si = model.sheet.styles.firstIndex(where: { $0.name == style.name }), let fi = model.sheet.styles[si].formulas.firstIndex(where: { $0.id == formula.id }) else { return }
                                model.sheet.styles[si].formulas[fi].binding = value
                            }), type: type, parameters: [], definitions: model.sheet.reusableFormulas)
                        }
                    }
                    if style.target == .paragraph {
                        FormulaQualifiers(condition: Binding(get: { formula.when }, set: { model.updateQualifiers(formula.id, when: $0) }),
                            target: Binding(get: { formula.target }, set: { model.updateQualifiers(formula.id, target: $0) }),
                            operation: formula.operation, styleNames: model.sheet.styles.filter { $0.target == .paragraph }.map(\.name), selections: model.sheet.selections)
                    }
                    if !formula.when.isAlways {
                        Text(formula.when.holds(in: model.previewContext, facts: model.previewFacts) ? "Condizione soddisfatta nel campione" : "Condizione non soddisfatta nel campione")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if formula.target != .paragraph {
                        Text("Il trattamento segue il destinatario durante la composizione.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let state = states.last(where: { $0.id == formula.id }) {
                        Text("Ingresso: " + summary(state.input, property: formula.operation.property) + " → Risultato: " + summary(state.output, property: formula.operation.property))
                            .font(.caption).foregroundStyle(.secondary).padding(.leading, 24)
                    }
                }
            }
            Button { model.addStyleFormula() } label: { Label("Predicato", systemImage: "plus") }
            compatibleProperties(style)
            Divider()
            HStack {
                Text("Carattere di partenza")
                Menu {
                    Button("Dal documento") { model.previewRole = nil }
                    ForEach(FontRole.allCases, id: \.self) { role in
                        Button(roleTitle(role)) { model.previewRole = role }
                    }
                } label: { ComposerPill(title: model.previewRole.map(roleTitle) ?? "Dal documento") }
            }.menuStyle(.borderlessButton)
            if style.target == .paragraph {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contesto del campione").font(.caption.weight(.semibold))
                    HStack {
                        Toggle("Primo della pagina", isOn: $model.previewFirstOnPage)
                        Toggle("Inizio sequenza", isOn: $model.previewSequenceStart)
                        Menu {
                            Button("Nessun precedente") { model.previewPreviousStyle = nil }
                            ForEach(model.sheet.styles.filter { $0.target == .paragraph }, id: \.name) { previous in
                                Button(previous.name) { model.previewPreviousStyle = previous.name }
                            }
                        } label: { ComposerPill(title: model.previewPreviousStyle.map { "Dopo · " + $0 } ?? "Paragrafo precedente") }
                    }.toggleStyle(.checkbox).menuStyle(.borderlessButton)
                    if style.formulas.contains(where: { $0.when.measurement != nil }) {
                        HStack {
                            Text("Righe di prova")
                            FormulaNumberPill(value: Double(model.previewLineCount)) { model.previewLineCount = max(1, Int($0)) }
                            Text("Ultima riga %")
                            FormulaNumberPill(value: model.previewLastLineFill) { model.previewLastLineFill = min(100, $0) }
                            Text("Trattini")
                            FormulaNumberPill(value: Double(model.previewHyphens)) { model.previewHyphens = Int($0) }
                        }.font(.caption)
                    }
                }
            }
            if let result = try? model.preview(style) {
                Text(AttributedString(NSAttributedString(string: model.sample,
                    attributes: TextStyling.characterAttributes(for: result.character).attributes)))
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: Theme.control))
                Text("Corpo \(result.character.size.formatted()) pt · rientro sinistro \(result.paragraph.leftIndent.formatted()) pt · spazio prima \(result.paragraph.spaceBefore.formatted()) pt")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("La formula non è applicabile al carattere di partenza. Controlla ruolo del font e misure.")
                    .foregroundStyle(Color(nsColor: Theme.warn))
            }
        }
        .padding(20).frame(width: 670, alignment: .leading)
        .background(Color(nsColor: Theme.side))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: Theme.line)))
    }

    func summary(_ state: StylePredicateState, property: StyleProperty) -> String {
        let c = state.character, p = state.paragraph
        switch property {
        case .pageStartSpacing:
            if case .distance(let points) = state.directives.pageStartSpacing { return points.formatted() + " pt" }
            return "Nessuna distanza"
        case .openingDistance: return (state.directives.openingDistance ?? 0).formatted() + " pt"
        case .opensSection: return state.directives.opensSection.flatMap { $0.isEmpty ? nil : $0 } ?? "Nessuna sezione"
        case .nextStyle: return state.directives.nextStyle.flatMap { $0.isEmpty ? nil : $0 } ?? "Stesso stile"
        case .applyStyle: return state.directives.applyingStyle ?? "Nessun trattamento"
        case .outlineLevel: return String(p.outlineLevel ?? 0)
        case .keepWithNext: return state.directives.keeping.withNext == true ? "Sì" : "No"
        case .keepTogether: return state.directives.keeping.together == true ? "Sì" : "No"
        case .orphanLines: return String(state.directives.keeping.linesAtEnd ?? 1)
        case .widowLines: return String(state.directives.keeping.linesAtStart ?? 1)
        case .face: return c.fontName
        case .font: return model.resolver.role(of: c).map(roleTitle) ?? c.fontName
        case .family: return NSFont(name: c.fontName, size: CGFloat(c.size))?.familyName ?? c.fontName
        case .size: return c.size.formatted() + " pt"
        case .color: return c.color ?? "Automatico"
        case .smallCaps: return c.smallCaps.rawValue
        case .hyphenates: return c.hyphenates ? "Attiva" : "Disattivata"
        case .language: return c.language ?? "Lingua documento"
        case .alignment: return p.alignment.rawValue
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
        case .base: "Formattazione di base"
        case .placement: "Durante la collocazione"
        case .textContext: "Dopo la base · contesto del testo"
        case .composition: "Dopo il contesto · composizione naturale"
        case .assignment: "Quando assegni lo stile"
        case .paragraphCreation: "Quando premi Invio"
        }
    }

    func setParent(_ name: String, _ parent: String?) {
        guard let i = model.sheet.styles.firstIndex(where: { $0.name == name }) else { return }
        model.sheet.styles[i].basedOn = parent
    }

    func formulaRow(_ formula: StyleFormula, target: StyleTarget, index: Int, count: Int) -> some View {
        let op = formula.operation
        return HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(Color(nsColor: Theme.secondary))
            Menu {
                ForEach(op.property.predicates, id: \.self) { predicate in
                    Button(predicate.title) {
                        model.updateFormula(formula.id, operation: StylePropertyOperation(predicate, op.property, op.argument))
                    }
                }
            } label: { ComposerPill(title: op.predicate.title) }
            Menu {
                ForEach(StyleProperty.allCases.filter {
                    (try? StyleFormula(operation: StylePropertyOperation(.set, $0, $0.initialArgument)).validate(for: target)) != nil
                }, id: \.self) { property in
                    Button(property.title) {
                        let predicate = property.predicates.contains(op.predicate) ? op.predicate : .set
                        model.updateFormula(formula.id, operation: StylePropertyOperation(predicate, property, property.initialArgument))
                    }
                }
            } label: { ComposerPill(title: op.property.title) }
            FormulaArgumentPill(operation: op, target: target, styleNames: model.sheet.styles.filter {
                op.property == .nextStyle ? $0.target == .paragraph : (($0.target != .paragraph || formula.target == .paragraph) && !$0.formulas.contains(where: \.isRuntimeRule))
            }.map(\.name)) { value in
                model.updateFormula(formula.id, operation: StylePropertyOperation(op.predicate, op.property, value))
            }
            Spacer(minLength: 4)
            Menu {
                Button("Sposta prima") { model.moveStyleFormula(formula.id, by: -1) }.disabled(index == 0)
                Button("Sposta dopo") { model.moveStyleFormula(formula.id, by: 1) }.disabled(index + 1 == count)
                Button("Togli la formula") { model.removeStyleFormula(formula.id) }
            } label: { ComposerPill(title: "⋯") }
        }.menuStyle(.borderlessButton)
    }

    @ViewBuilder func compatibleProperties(_ style: NamedStyle) -> some View {
        let v = style.values
        if v != StyleValues() {
            VStack(alignment: .leading, spacing: 5) {
                Text("Altre proprietà conservate").font(.caption.weight(.semibold))
                if let role = v.opensSection { Text("Apre sezione · " + role) }
                if let level = v.outlineLevel { Text("Livello · \(level)") }
                if let list = v.listName { Text("Lista · " + list) }
                if let distance = v.openingDistance { Text("Apertura sequenza · \(distance.formatted()) pt") }
                if v.pageStartSpacing != nil { Text("Variante di inizio pagina · configurata nella scheda Stili") }
                if !v.keeping.isEmpty { Text("Tenuta delle righe · " + v.keeping.encoded) }
                if v.family != nil || v.italic != nil || v.bold != nil || v.features != nil || v.variations != nil || v.fontName != nil || v.opticalSize != nil {
                    Text("Scelte avanzate del font · modificabili nella scheda Stili")
                }
                if v.italic == false || v.bold == false { Text("Esclusioni esplicite dei tratti del font · scheda Stili") }
                if v.verticalPosition != nil || v.decorations != nil || v.graphite != nil || v.lineHeightMultiple != nil {
                    Text("Altri valori tipografici · modificabili nella scheda Stili")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FormulaArgumentPill: View {
    let operation: StylePropertyOperation
    let target: StyleTarget
    var styleNames: [String] = []
    let commit: (StyleArgument) -> Void
    @State private var editing = false
    @State private var text = ""

    private var title: String {
        switch operation.argument {
        case .boolean(let enabled): enabled ? "Sì" : "No"
        case .integer(let number): String(number)
        case .text(let value): value.isEmpty ? "Nessuna" : value
        case .styleName(let name): name ?? "Stesso stile"
        case .pageStart(let spacing):
            switch spacing { case .disabled: "Disattivata"; case .distance(let points): points.formatted() + " pt" }
        case .font(let role): roleTitle(role)
        case .length(let value, let unit): value.formatted() + " " + unit.rawValue
        case .family(let name), .face(let name): name
        case .language(let language): language ?? "Lingua documento"
        case .color(let color): color ?? "Automatico"
        case .alignment(let alignment): alignment.rawValue
        case .smallCaps(let mode): mode.rawValue
        case .hyphenates(let enabled): enabled ? "Attiva" : "Disattivata"
        }
    }
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
                Button("Sì") { commit(.boolean(true)) }
                Button("No") { commit(.boolean(false)) }
            case .integer:
                ForEach((operation.property == .outlineLevel ? 0 : 1)...9, id: \.self) { n in Button(String(n)) { commit(.integer(n)) } }
            case .text:
                ForEach(["", Section.Role.part, Section.Role.chapter, Section.Role.section, Section.Role.appendix], id: \.self) { value in
                    Button(value.isEmpty ? "Nessuna sezione" : value) { commit(.text(value)) }
                }
                Button("Altro ruolo…") { if case .text(let value) = operation.argument { text = value }; editing = true }
            case .styleName:
                // I nomi vengono forniti dalla bacheca per evitare riferimenti liberi.
                ForEach(styleNames, id: \.self) { name in Button(name) { commit(.styleName(name)) } }
                if operation.property == .nextStyle { Button("Stesso stile") { commit(.styleName(nil)) } }
            case .pageStart:
                Button("Disattivata") { commit(.pageStart(.disabled)) }
                ForEach([0, 36, 72, 108], id: \.self) { n in Button("\(n) pt") { commit(.pageStart(.distance(Double(n)))) } }
                Button("Altra distanza…") { text = title; editing = true }
            case .font:
                ForEach(FontRole.allCases, id: \.self) { role in Button(roleTitle(role)) { commit(.font(role)) } }
            case .alignment:
                ForEach(ParagraphStyle.Alignment.allCases, id: \.self) { alignment in
                    Button(alignment.rawValue) { commit(.alignment(alignment)) }
                }
            case .smallCaps:
                ForEach(SmallCaps.allCases, id: \.self) { mode in Button(mode.rawValue) { commit(.smallCaps(mode)) } }
            case .hyphenates:
                Button("Attiva") { commit(.hyphenates(true)) }
                Button("Disattivata") { commit(.hyphenates(false)) }
            case .face:
                ForEach(NSFontManager.shared.availableFonts.sorted(), id: \.self) { name in
                    Button(name) { commit(.face(name)) }
                }
            case .family:
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { name in
                    Button(name) { commit(.family(name)) }
                }
            case .length:
                Button("Modifica misura…") { text = title; editing = true }
                ForEach([0, 6, 12, 18, 24], id: \.self) { n in
                    if operation.property != .size || n > 0 {
                        Button("\(n) pt") { commit(.length(Double(n), .points)) }
                    }
                }
            case .language, .color:
                Button("Modifica valore…") {
                    switch operation.argument {
                    case .language(let value), .color(let value): text = value ?? ""
                    default: break
                    }
                    editing = true
                }
                Button("Automatico / documento") {
                    if operation.property == .color { commit(.color(nil)) } else { commit(.language(nil)) }
                }
            }
        } label: { ComposerPill(title: title) }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(operation.property.title).font(.headline)
                TextField("Valore", text: $text).frame(width: 220)
                if case .length = operation.argument { Text("Unità ammesse · pt, mm, cm, in, pc").font(.caption) }
                Button("Usa questo valore") {
                    if validEdit, let value = editedArgument { commit(value); editing = false }
                }.disabled(!validEdit)
            }.padding(16).buttonStyle(ComposerButtonStyle())
        }
    }
}

private struct FormulaNumberPill: View {
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
            Button("Altro valore…") { text = String(value); editing = true }
        } label: { ComposerPill(title: value.formatted()) }
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Valore", text: $text).frame(width: 180)
                Button("Usa questo valore") { if let parsed { commit(parsed); editing = false } }.disabled(parsed == nil)
            }.padding(16).buttonStyle(ComposerButtonStyle())
        }
    }
}

private struct FormulaQualifiers: View {
    @Binding var condition: StyleCondition
    @Binding var target: TextRule.Target
    let operation: StylePropertyOperation
    let styleNames: [String]
    let selections: [WordSelection]

    private func valid(_ condition: StyleCondition, _ target: TextRule.Target) -> Bool {
        (try? StyleFormula(operation: operation, when: condition, target: target).validate(for: .paragraph)) != nil
    }
    private var targetTitle: String {
        switch target {
        case .paragraph: "Questo paragrafo"
        case .firstLetter: "Prima lettera"
        case .firstWords(let count): "Prime \(count) parole"
        case .firstSentence: "Prima frase"
        case .firstLines(let count): "Prime \(count) righe"
        case .lastLine: "Ultima riga"
        case .words(.capitals): "Sigle maiuscole"
        case .words(.romanNumerals): "Numeri romani"
        case .words(.numbers): "Numeri"
        case .words(.listed): "Parole date"
        case .selection(let id): selections.first { $0.id == id }?.name ?? "Selezione condivisa"
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
        case .words: "Parole"
        case .lines: "Righe"
        case .lastLineFill: "Ultima riga %"
        case .hyphens: "Righe con trattino"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Quando").font(.caption).foregroundStyle(.secondary)
                Menu {
                    if valid(StyleCondition(position: .any, measurement: condition.measurement), target) {
                        Button("Sempre") { choose(TextRule.Position.any) }
                    }
                    if valid(StyleCondition(position: .firstOnPage, measurement: condition.measurement), target) {
                        Button("Primo della pagina") { choose(TextRule.Position.firstOnPage) }
                    }
                    if valid(StyleCondition(position: .sequenceStart, measurement: condition.measurement), target) {
                        Button("Inizio sequenza") { choose(TextRule.Position.sequenceStart) }
                    }
                    if !operation.property.isDirective {
                        Menu("Dopo lo stile") {
                            ForEach(styleNames, id: \.self) { name in Button(name) { choose(TextRule.Position.firstAfter(name)) } }
                        }
                    }
                } label: { ComposerPill(title: StyleCondition(position: condition.position).summary) }
                if !operation.property.isDirective {
                    Menu {
                        Button("Nessuna condizione numerica") { choose(Optional<TextRule.Condition>.none) }
                        ForEach(TextRule.Condition.Property.allCases, id: \.self) { metric in
                            Button(metricTitle(metric)) { choose(TextRule.Condition(metric, .greaterOrEqual, metric == .lastLineFill ? 50 : 2)) }
                        }
                    } label: { ComposerPill(title: condition.measurement.map { metricTitle($0.property) } ?? "＋ Condizione") }
                    if let metric = condition.measurement {
                        Menu {
                            ForEach(TextRule.Condition.Comparison.allCases, id: \.self) { comparison in
                                Button(comparison.symbol) { choose(TextRule.Condition(metric.property, comparison, metric.value)) }
                            }
                        } label: { ComposerPill(title: metric.comparison.symbol) }
                        FormulaNumberPill(value: metric.value) { choose(TextRule.Condition(metric.property, metric.comparison, $0)) }
                    }
                }
            }
            if !operation.property.isDirective {
                HStack(spacing: 8) {
                    Text("Su").font(.caption).foregroundStyle(.secondary)
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
                    } label: { ComposerPill(title: targetTitle) }
                    if case .firstWords(let count) = target {
                        FormulaNumberPill(value: Double(count)) { if $0 >= 1, $0.rounded() == $0 { target = .firstWords(Int($0)) } }
                    }
                    if case .firstLines(let count) = target {
                        FormulaNumberPill(value: Double(count)) { if $0 >= 1, $0.rounded() == $0 { target = .firstLines(Int($0)) } }
                    }
                }
            }
        }.menuStyle(.borderlessButton)
    }
    private func targetName(_ target: TextRule.Target) -> String {
        switch target {
        case .paragraph: "Questo paragrafo"
        case .firstLetter: "Prima lettera"
        case .firstWords: "Prime parole"
        case .firstSentence: "Prima frase"
        case .firstLines: "Prime righe"
        case .lastLine: "Ultima riga"
        case .words(.capitals): "Sigle maiuscole"
        case .words(.romanNumerals): "Numeri romani"
        case .words(.numbers): "Numeri"
        default: "Selezione"
        }
    }
}

private extension ComposerBoard {
    func historicalRuleCard(_ i: Int) -> some View {
        let rule = model.rules[i]
        return VStack(alignment: .leading, spacing: 14) {
            Text("Regola del documento \(i + 1)").font(.headline)
            HStack {
                Menu {
                    Button("Tutti i paragrafi") { model.rules[i].paragraphStyle = nil }
                    ForEach(model.sheet.styles.filter { $0.target == .paragraph }, id: \.name) { style in
                        Button(style.name) { model.rules[i].paragraphStyle = style.name }
                    }
                } label: { ComposerPill(title: rule.paragraphStyle ?? "Tutti i paragrafi") }
                ComposerPill(title: "Imposta · Stile")
                Menu {
                    ForEach(model.sheet.styles.filter { $0.target != .paragraph || rule.target == .paragraph }, id: \.name) { style in
                        Button(style.name) { model.rules[i].styleName = style.name }
                    }
                } label: { ComposerPill(title: rule.styleName) }
                Menu {
                    Button(rule.isEnabled ? "Sospendi" : "Attiva") { model.rules[i].isEnabled.toggle() }
                    Button("Rimuovi regola") { model.rules.remove(at: i) }
                } label: { ComposerPill(title: rule.isEnabled ? "Attiva" : "Sospesa") }
            }
            FormulaQualifiers(condition: Binding(get: { StyleCondition(position: model.rules[i].position, measurement: model.rules[i].condition) },
                set: { model.rules[i].position = $0.position; model.rules[i].condition = $0.measurement }),
                target: Binding(get: { model.rules[i].target }, set: { model.rules[i].target = $0 }),
                operation: StylePropertyOperation(.set, .applyStyle, .styleName(rule.styleName)),
                styleNames: model.sheet.styles.filter { $0.target == .paragraph }.map(\.name), selections: model.sheet.selections)
            Text("Mantiene ordine e precedenze della regola originale.").font(.caption).foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).padding(20).frame(width: 850, alignment: .leading)
            .background(Color(nsColor: Theme.side)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
