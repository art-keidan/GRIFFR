import AppKit
import Typesetting
@testable import WordProcessor

/// Per le prove: le regole del motore nascono dalle formule contestuali degli stili. Una prova scrive la regola che vuole
/// e la mette, come formula, nello stile dei paragrafi che riguarda («Body», da cui derivano tutti, se non ne ha uno).
enum RuleFormulas {
    /// Lo stile «Centered»: fissa solo l'allineamento.
    static var centered: NamedStyle {
        var values = StyleValues()
        values.alignment = .center
        return NamedStyle(name: "Centered", target: .paragraph, values: values)
    }

    static func formula(_ rule: TextRule) -> StyleFormula {
        StyleFormula(operation: StylePropertyOperation(.set, .applyStyle, .styleName(rule.styleName)),
                     when: StyleCondition(position: rule.position, measurement: rule.condition), target: rule.target)
    }

    /// Il foglio `base` con le regole messe come formule; una regola spenta non c'è.
    static func sheet(_ base: StyleSheet, with rules: [TextRule]) -> StyleSheet {
        var sheet = base
        for rule in rules where rule.isEnabled {
            let owner = rule.paragraphStyle ?? StyleSheet.defaultParagraphStyle
            guard let index = sheet.styles.firstIndex(where: { $0.name == owner }) else { continue }
            sheet.styles[index].formulas.append(formula(rule))
        }
        return sheet
    }
}

@MainActor
extension EditorWindowController {
    /// Il foglio `base` con le regole come formule, in un passo di Annulla.
    func setRuleFormulasForTests(_ rules: [TextRule], over base: StyleSheet) {
        endUndoStep(next: .none)
        changeStyles(to: RuleFormulas.sheet(base, with: rules), restyle: false, actionName: "Rules")
    }
}
