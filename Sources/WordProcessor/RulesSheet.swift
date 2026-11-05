import AppKit
import SwiftUI
import Typesetting

/// Una regola come la si modifica nella finestra delle regole: i campi separati, più comodi da legare ai controlli.
struct RuleDraft: Identifiable, Equatable {
    enum Find: String, CaseIterable {
        case selection, paragraph, firstLetter, firstWords, firstSentence, firstLines, lastLine, capitals, roman, numbers, listed

        var title: String {
            switch self {
            case .selection: "a composed selection"
            case .paragraph: "the whole paragraph"
            case .firstLetter: "the first letter"
            case .firstWords: "the first words"
            case .firstSentence: "the first sentence"
            case .firstLines: "the first lines"
            case .lastLine: "the last line"
            case .capitals: "all-capital words (abbreviations)"
            case .roman: "Roman numerals"
            case .numbers: "numbers"
            case .listed: "the words written below"
            }
        }
    }

    enum Place: String, CaseIterable {
        case any, firstAfter, sequenceStart, firstOnPage
    }

    let id = UUID()
    var find: Find = .firstWords
    var selectionID = UUID()
    var count = 1
    var words = ""
    /// Lo stile dei paragrafi; la stringa vuota per tutti.
    var paragraphStyle = ""
    var place: Place = .any
    var afterStyle = ""
    var styleName = ""
    var isEnabled = true
    var hasCondition = false
    var conditionProperty: TextRule.Condition.Property = .lines
    var comparison: TextRule.Condition.Comparison = .equal
    var conditionValue: Double = 1

    init(styleName: String, afterStyle: String) {
        self.styleName = styleName
        self.afterStyle = afterStyle
    }

    init(_ rule: TextRule, defaultAfter: String) {
        switch rule.target {
        case .selection(let id): find = .selection; selectionID = id
        case .firstLetter: find = .firstLetter
        case .firstWords(let n): find = .firstWords; count = n
        case .firstSentence: find = .firstSentence
        case .firstLines(let n): find = .firstLines; count = n
        case .lastLine: find = .lastLine
        case .paragraph: find = .paragraph
        case .words(.capitals): find = .capitals
        case .words(.romanNumerals): find = .roman
        case .words(.numbers): find = .numbers
        case .words(.listed(let list)): find = .listed; words = list.joined(separator: " ")
        }
        paragraphStyle = rule.paragraphStyle ?? ""
        afterStyle = defaultAfter
        switch rule.position {
        case .any: place = .any
        case .firstAfter(let style): place = .firstAfter; afterStyle = style
        case .sequenceStart: place = .sequenceStart
        case .firstOnPage: place = .firstOnPage
        }
        if let condition = rule.condition {
            hasCondition = true
            conditionProperty = condition.property
            comparison = condition.comparison
            conditionValue = condition.value
        }
        styleName = rule.styleName
        isEnabled = rule.isEnabled
    }

    var rule: TextRule {
        let target: TextRule.Target = switch find {
        case .selection: .selection(selectionID)
        case .firstLetter: .firstLetter
        case .firstWords: .firstWords(max(count, 1))
        case .firstSentence: .firstSentence
        case .firstLines: .firstLines(max(count, 1))
        case .lastLine: .lastLine
        case .paragraph: .paragraph
        case .capitals: .words(.capitals)
        case .roman: .words(.romanNumerals)
        case .numbers: .words(.numbers)
        case .listed: .words(.listed(words.split(whereSeparator: \.isWhitespace).map(String.init)))
        }
        let position: TextRule.Position = switch place {
        case .any: .any
        case .firstAfter: .firstAfter(afterStyle)
        case .sequenceStart: .sequenceStart
        case .firstOnPage: .firstOnPage
        }
        return TextRule(target: target, paragraphStyle: paragraphStyle.isEmpty ? nil : paragraphStyle, position: position,
                        condition: hasCondition ? TextRule.Condition(conditionProperty, comparison, conditionValue) : nil,
                        styleName: styleName, isEnabled: isEnabled)
    }
}

/// Lo stato della finestra delle regole.
@MainActor
final class RulesSheetModel: ObservableObject {
    @Published var rows: [RuleDraft]
    @Published var selection: RuleDraft.ID?
    let selections: [WordSelection]
    let paragraphStyles: [String]
    /// Gli stili di carattere e di parola che una regola può applicare, e quelli di paragrafo (solo per il paragrafo
    /// intero), compresi gli stili predefiniti per le regole che il documento non ha ancora: si aggiungono agli stili
    /// se una regola li usa.
    let characterStyles: [String]
    let paragraphTargetStyles: [String]
    let missingStyles: [NamedStyle]

    struct Result {
        var rules: [TextRule]
        /// Gli stili predefiniti da aggiungere al documento, perché una regola li usa.
        var addedStyles: [NamedStyle]
    }


    init(rules: [TextRule], styles: StyleSheet) {
        selections = styles.selections
        paragraphStyles = styles.styles.filter { $0.target == .paragraph }.map(\.name)
        let missing = StyleSheet.ruleStyles.filter { styles.style(named: $0.name) == nil }
        missingStyles = missing
        characterStyles = missing.filter { $0.target != .paragraph }.map(\.name) + styles.styles.filter { $0.target != .paragraph }.map(\.name)
        paragraphTargetStyles = missing.filter { $0.target == .paragraph }.map(\.name) + paragraphStyles + characterStyles
        let after = paragraphStyles.first { $0 == "Heading 1" || $0 == "Titolo 1" } ?? paragraphStyles.first ?? ""
        let rows = rules.map { rule in
            var draft = RuleDraft(rule, defaultAfter: after)
            if draft.find != .selection, let first = styles.selections.first { draft.selectionID = first.id }
            return draft
        }
        self.rows = rows
        selection = rows.first?.id
    }

    static let smallCaps = StyleSheet.smallCapsStyle

    var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    var problem: String? {
        for (index, row) in rows.enumerated() {
            if row.styleName.isEmpty { return "Rule \(index + 1) has no style to apply." }
            if row.find == .listed, row.words.trimmingCharacters(in: .whitespaces).isEmpty { return "Rule \(index + 1) has no words to find." }
            if row.place == .firstAfter, row.afterStyle.isEmpty { return "Rule \(index + 1) does not say after which style." }
            if row.find != .paragraph, missingStyles.contains(where: { $0.name == row.styleName && $0.target == .paragraph }) || paragraphStyles.contains(row.styleName) {
                return "Rule \(index + 1) applies a paragraph style: that only works for the whole paragraph."
            }
        }
        return nil
    }

    func result() -> Result {
        let rules = rows.map(\.rule)
        return Result(rules: rules, addedStyles: missingStyles.filter { style in rules.contains { $0.styleName == style.name } })
    }

    func add() {
        let after = paragraphStyles.first { $0 == "Heading 1" || $0 == "Titolo 1" } ?? paragraphStyles.first ?? ""
        var row = RuleDraft(styleName: characterStyles.first { $0 == Self.smallCaps } ?? characterStyles.first ?? "", afterStyle: after)
        if let body = [StyleSheet.defaultParagraphStyle, StyleSheet.legacyParagraphStyle].first(where: paragraphStyles.contains) { row.paragraphStyle = body }
        if let first = selections.first { row.selectionID = first.id }
        rows.append(row)
        selection = row.id
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        rows.remove(at: index)
        selection = rows.indices.contains(index) ? rows[index].id : rows.last?.id
    }

    func binding<Value>(_ id: RuleDraft.ID, _ path: WritableKeyPath<RuleDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { self.rows.first { $0.id == id }?[keyPath: path] ?? fallback },
            set: { value in
                guard let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
                self.rows[index][keyPath: path] = value
            })
    }
}

struct RulesSheetView: View {
    @ObservedObject var model: RulesSheetModel

    /// Nella scheda del pannello: in colonna, senza OK e Annulla (le modifiche valgono subito).
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach(model.rows) { row in
                    Text(row.rule.summary(selections: model.selections))
                        .foregroundStyle(row.isEnabled ? .primary : .secondary)
                        .lineLimit(2)
                        .tag(row.id)
                }
                .onMove { model.rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 150)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("A new rule")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }.disabled(model.selectedIndex == nil).help("Remove the chosen rule")
                Spacer()
                if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).lineLimit(2) }
            }
            if let id = model.selection, model.rows.contains(where: { $0.id == id }) {
                RuleDetailView(model: model, id: id, embedded: true)
            } else {
                Text("No rules. Add one with +.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
    }

}

/// I campi di una regola.
private struct RuleDetailView: View {
    @ObservedObject var model: RulesSheetModel
    let id: RuleDraft.ID
    var embedded = false

    private func field<Value>(_ path: WritableKeyPath<RuleDraft, Value>, _ fallback: Value) -> Binding<Value> {
        model.binding(id, path, fallback: fallback)
    }

    var body: some View {
        let row = model.rows.first { $0.id == id } ?? RuleDraft(styleName: "", afterStyle: "")
        Form {
            Picker("Find:", selection: field(\.find, .firstWords)) {
                ForEach(RuleDraft.Find.allCases.filter { $0 != .selection || !model.selections.isEmpty }, id: \.self) { Text($0.title).tag($0) }
            }
            if row.find == .selection {
                Picker("Selection:", selection: field(\.selectionID, row.selectionID)) {
                    ForEach(model.selections) { Text($0.name).tag($0.id) }
                }
            }
            if row.find == .firstWords {
                Stepper("Words: \(row.count)", value: field(\.count, 1), in: 1...99)
            }
            if row.find == .firstLines {
                Stepper("Lines: \(row.count)", value: field(\.count, 1), in: 1...99)
            }
            if row.find == .firstLines || row.find == .lastLine {
                Text("The lines are decided together with the style: the text in the style takes exactly those lines, even if the style changes their width. If several rules of this kind touch the same paragraph, the lowest one wins.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.find == .listed {
                TextField("Words:", text: field(\.words, ""), prompt: Text("separated by spaces, written as in the text"))
            }
            Picker("In paragraphs:", selection: field(\.paragraphStyle, "")) {
                Text("of any style").tag("")
                ForEach(model.paragraphStyles, id: \.self) { Text($0).tag($0) }
            }
            Picker("Which:", selection: field(\.place, .any)) {
                Text("tutti").tag(RuleDraft.Place.any)
                Text("only the first after a paragraph of style…").tag(RuleDraft.Place.firstAfter)
                Text("only the first of the document").tag(RuleDraft.Place.sequenceStart)
                Text("only the first of a page").tag(RuleDraft.Place.firstOnPage)
            }
            if row.place == .firstAfter {
                Picker("After the style:", selection: field(\.afterStyle, "")) {
                    ForEach(model.paragraphStyles, id: \.self) { Text($0).tag($0) }
                }
            }
            Toggle("Only if…", isOn: field(\.hasCondition, false))
            if row.hasCondition {
                // Con un'etichetta la riga sta nella colonna dei valori: senza, il modulo la metteva in quella delle
                // etichette, che si allargava fino a schiacciare tutto il resto.
                LabeledContent("Condition:") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: field(\.conditionProperty, .lines)) {
                            Text("the number of lines").tag(TextRule.Condition.Property.lines)
                            Text("the number of words").tag(TextRule.Condition.Property.words)
                            Text("the last line fills (%)").tag(TextRule.Condition.Property.lastLineFill)
                            Text("the hyphenated lines").tag(TextRule.Condition.Property.hyphens)
                        }
                        .labelsHidden()
                        // Il confronto e il valore sotto: su una riga sola la condizione usciva dalla colonna dei valori.
                        HStack {
                            Picker("", selection: field(\.comparison, .equal)) {
                                ForEach(TextRule.Condition.Comparison.allCases, id: \.self) { Text($0.symbol).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            TextField("", value: field(\.conditionValue, 1), format: .number).fieldWidth(60, embedded: embedded)
                        }
                    }
                }
                Text("The condition is checked on the paragraph composed without the rules that depend on composition: the result is stable, but after applying it the paragraph may no longer meet it (a one-line paragraph, enlarged, can become two).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Apply the style:", selection: field(\.styleName, "")) {
                ForEach(row.find == .paragraph ? model.paragraphTargetStyles : model.characterStyles, id: \.self) { name in
                    Text(model.missingStyles.contains { $0.name == name } ? "\(name) (new)" : name).tag(name)
                }
            }
            if [StyleSheet.smallCapsStyle, "Maiuscoletto"].contains(row.styleName), [.capitals, .roman].contains(row.find) {
                Text("“Small Caps” changes lowercase letters: abbreviations and Roman numerals, all capitals, do not change. For them there is “All Small Caps”, if the font has the feature (Hoefler Text does not).")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Rule on", isOn: field(\.isEnabled, true))
            Text(row.rule.summary(selections: model.selections)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if row.find == .firstSentence {
                Text("The sentence ends at the first full stop, exclamation or question mark followed by a space, as the system recognizes it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.find == .paragraph {
                Text("With a paragraph style, alignment, indents and spacing change too; a style that sets only the alignment, such as “Centered”, changes only that.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.place == .firstOnPage {
                Text("The paragraph a page begins with in natural composition, that is, before applying the rules that depend on composition.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.place == .sequenceStart {
                Text("Once there are sections (chapters, parts), it will be the first paragraph of each section.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .definitionForm(embedded: embedded, width: 480)
    }
}
