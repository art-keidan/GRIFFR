import AppKit
import Typesetting
@testable import WordProcessor

/// Per le prove: dare e leggere valori della selezione, come faceva l'ispettore tolto.
@MainActor
extension EditorWindowController {
    /// Un valore dato alla selezione (o a ciò che si scriverà), come un passo di Annulla.
    func changeForTests(_ property: InspectorProperty, _ build: (inout StyleValues) -> Void) {
        var values = StyleValues()
        build(&values)
        setSelectionValue(property, values)
    }

    /// Il valore che la selezione ha ora, con la sua provenienza.
    func valueForTests(_ property: InspectorProperty) -> InspectedValue? {
        selectionValues(property.level).first { $0.property == property }
    }
}
