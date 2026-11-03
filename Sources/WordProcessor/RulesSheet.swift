import AppKit
import SwiftUI
import Typesetting

/// Una regola come la si modifica nella finestra delle regole: i campi separati, più comodi da legare ai controlli.
struct RuleDraft: Identifiable, Equatable {
    enum Find: String, CaseIterable {
        case paragraph, firstLetter, firstWords, firstSentence, firstLines, lastLine, capitals, roman, numbers, listed

        var title: String {
            switch self {
            case .paragraph: "il paragrafo intero"
            case .firstLetter: "la prima lettera"
            case .firstWords: "le prime parole"
            case .firstSentence: "la prima frase"
            case .firstLines: "le prime righe"
            case .lastLine: "l'ultima riga"
            case .capitals: "le parole tutte maiuscole (sigle)"
            case .roman: "i numeri romani"
            case .numbers: "i numeri"
            case .listed: "le parole scritte qui sotto"
            }
        }
    }

    enum Place: String, CaseIterable {
        case any, firstAfter, sequenceStart, firstOnPage
    }

    let id = UUID()
    var find: Find = .firstWords
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
        paragraphStyles = styles.styles.filter { $0.target == .paragraph }.map(\.name)
        let missing = StyleSheet.ruleStyles.filter { styles.style(named: $0.name) == nil }
        missingStyles = missing
        characterStyles = missing.filter { $0.target != .paragraph }.map(\.name) + styles.styles.filter { $0.target != .paragraph }.map(\.name)
        paragraphTargetStyles = missing.filter { $0.target == .paragraph }.map(\.name) + paragraphStyles + characterStyles
        let after = paragraphStyles.first { $0 == "Titolo 1" } ?? paragraphStyles.first ?? ""
        let rows = rules.map { RuleDraft($0, defaultAfter: after) }
        self.rows = rows
        selection = rows.first?.id
    }

    static let smallCaps = "Maiuscoletto"

    var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    var problem: String? {
        for (index, row) in rows.enumerated() {
            if row.styleName.isEmpty { return "La regola \(index + 1) non ha uno stile da applicare." }
            if row.find == .listed, row.words.trimmingCharacters(in: .whitespaces).isEmpty { return "La regola \(index + 1) non ha parole da cercare." }
            if row.place == .firstAfter, row.afterStyle.isEmpty { return "La regola \(index + 1) non dice dopo quale stile." }
            if row.find != .paragraph, missingStyles.contains(where: { $0.name == row.styleName && $0.target == .paragraph }) || paragraphStyles.contains(row.styleName) {
                return "La regola \(index + 1) applica uno stile di paragrafo: va bene solo per il paragrafo intero."
            }
        }
        return nil
    }

    func result() -> Result {
        let rules = rows.map(\.rule)
        return Result(rules: rules, addedStyles: missingStyles.filter { style in rules.contains { $0.styleName == style.name } })
    }

    func add() {
        let after = paragraphStyles.first { $0 == "Titolo 1" } ?? paragraphStyles.first ?? ""
        var row = RuleDraft(styleName: characterStyles.first { $0 == Self.smallCaps } ?? characterStyles.first ?? "", afterStyle: after)
        if paragraphStyles.contains("Testo") { row.paragraphStyle = "Testo" }
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
                    Text(row.rule.summary)
                        .foregroundStyle(row.isEnabled ? .primary : .secondary)
                        .lineLimit(2)
                        .tag(row.id)
                }
                .onMove { model.rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 150)
            HStack(spacing: 4) {
                Button { model.add() } label: { Image(systemName: "plus") }.help("Una regola nuova")
                Button { model.removeSelected() } label: { Image(systemName: "minus") }.disabled(model.selectedIndex == nil).help("Togli la regola scelta")
                Spacer()
                if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.red).lineLimit(2) }
            }
            if let id = model.selection, model.rows.contains(where: { $0.id == id }) {
                RuleDetailView(model: model, id: id, embedded: true)
            } else {
                Text("Nessuna regola. Con + se ne aggiunge una.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Picker("Cerca:", selection: field(\.find, .firstWords)) {
                ForEach(RuleDraft.Find.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if row.find == .firstWords {
                Stepper("Quante parole: \(row.count)", value: field(\.count, 1), in: 1...99)
            }
            if row.find == .firstLines {
                Stepper("Quante righe: \(row.count)", value: field(\.count, 1), in: 1...99)
            }
            if row.find == .firstLines || row.find == .lastLine {
                Text("Le righe si decidono insieme allo stile: il testo nello stile occupa esattamente quelle righe, anche se lo stile ne cambia la larghezza. Se più regole di questo tipo toccano lo stesso paragrafo, vale quella più in basso.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.find == .listed {
                TextField("Parole:", text: field(\.words, ""), prompt: Text("separate da spazi, scritte come nel testo"))
            }
            Picker("Nei paragrafi:", selection: field(\.paragraphStyle, "")) {
                Text("di qualunque stile").tag("")
                ForEach(model.paragraphStyles, id: \.self) { Text($0).tag($0) }
            }
            Picker("Quali:", selection: field(\.place, .any)) {
                Text("tutti").tag(RuleDraft.Place.any)
                Text("solo il primo dopo un paragrafo di stile…").tag(RuleDraft.Place.firstAfter)
                Text("solo il primo del documento").tag(RuleDraft.Place.sequenceStart)
                Text("solo il primo di una pagina").tag(RuleDraft.Place.firstOnPage)
            }
            if row.place == .firstAfter {
                Picker("Dopo lo stile:", selection: field(\.afterStyle, "")) {
                    ForEach(model.paragraphStyles, id: \.self) { Text($0).tag($0) }
                }
            }
            Toggle("Solo se…", isOn: field(\.hasCondition, false))
            if row.hasCondition {
                // Con un'etichetta la riga sta nella colonna dei valori: senza, il modulo la metteva in quella delle
                // etichette, che si allargava fino a schiacciare tutto il resto.
                LabeledContent("Condizione:") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: field(\.conditionProperty, .lines)) {
                            Text("il numero di righe").tag(TextRule.Condition.Property.lines)
                            Text("il numero di parole").tag(TextRule.Condition.Property.words)
                            Text("l'ultima riga riempie (%)").tag(TextRule.Condition.Property.lastLineFill)
                            Text("le righe con trattino").tag(TextRule.Condition.Property.hyphens)
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
                Text("La condizione si controlla sul paragrafo composto senza le regole che dipendono dalla composizione: il risultato è stabile, ma dopo l'applicazione il paragrafo può non soddisfarla più (un paragrafo di una riga, ingrandito, può diventare di due).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Applica lo stile:", selection: field(\.styleName, "")) {
                ForEach(row.find == .paragraph ? model.paragraphTargetStyles : model.characterStyles, id: \.self) { name in
                    Text(model.missingStyles.contains { $0.name == name } ? "\(name) (nuovo)" : name).tag(name)
                }
            }
            if row.styleName == "Maiuscoletto", [.capitals, .roman].contains(row.find) {
                Text("«Maiuscoletto» trasforma le minuscole: le sigle e i numeri romani, tutti maiuscoli, non cambiano. Per loro c'è «Maiuscoletto delle sigle», se il font ha la funzione (Hoefler Text non l'ha).")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Regola accesa", isOn: field(\.isEnabled, true))
            Text(row.rule.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if row.find == .firstSentence {
                Text("La frase finisce al primo punto fermo, esclamativo o interrogativo seguito da uno spazio, come la riconosce il sistema.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.find == .paragraph {
                Text("Con uno stile di paragrafo cambiano anche allineamento, rientri e spazi; uno stile che fissa solo l'allineamento, come «Centrato», cambia solo quello.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.place == .firstOnPage {
                Text("Il paragrafo con cui comincia una pagina nella composizione naturale, cioè prima di applicare le regole che dipendono dalla composizione.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if row.place == .sequenceStart {
                Text("Quando ci saranno le sezioni (capitoli, parti), sarà il primo paragrafo di ogni sezione.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .definitionForm(embedded: embedded, width: 480)
    }
}
