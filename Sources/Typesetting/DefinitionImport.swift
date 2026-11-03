import Foundation

/// Le definizioni che un pezzo di testo porta con sé da un altro documento: gli stili, le Liste e gli stili di
/// flottante che usa, con quelli da cui dipendono (lo stile su cui si basa, la Lista di uno stile o di una serie di
/// note, la Lista madre, lo stile del contenuto di una serie). Incollando, quelli che mancano nel documento di
/// destinazione vi si copiano; per quelli che ci sono con un'altra definizione decide chi incolla.
public enum DefinitionImport {
    public enum Kind: Hashable, Sendable {
        case style, list, floatStyle
    }

    /// Un nome che c'è nei due documenti con definizioni diverse.
    public struct Conflict: Hashable, Sendable {
        public var kind: Kind
        public var name: String
    }

    public enum Policy: Sendable {
        /// Il testo prende la definizione del documento di destinazione (salvo ciò che aveva dato a mano).
        case keepDestination
        /// La definizione d'origine entra come copia con un nome nuovo, «Enfasi (2)», e il testo la segue.
        case renameCopies
    }

    /// Le definizioni del documento di destinazione dopo l'importazione, e il testo da inserirvi.
    public struct Result {
        public var text: NSAttributedString
        public var styles: StyleSheet
        public var lists: [ListDefinition]
        public var floatStyles: [FloatStyle]
    }

    /// I nomi definiti nel documento d'origine che il testo usa, direttamente o attraverso un'altra definizione.
    struct Used {
        var styles: [String] = []
        var lists: [String] = []
        var floatStyles: [String] = []
    }

    static func used(in text: NSAttributedString, source: Document) -> Used {
        var used = Used()
        func addList(_ name: String?) {
            guard let name, !used.lists.contains(name), let list = source.lists.first(where: { $0.name == name }) else { return }
            used.lists.append(name)
            if case .list(let parent) = list.parent { addList(parent) }
        }
        func addStyle(_ name: String?) {
            guard let name, !used.styles.contains(name), let style = source.styles.style(named: name) else { return }
            used.styles.append(name)
            addStyle(style.basedOn)
            addList(style.values.listName)
        }
        // La serie delle note a piè di pagina c'è in ogni documento e non si copia: nemmeno ciò da cui dipende.
        func addFloatStyle(_ name: String?) {
            guard let name, name != FloatStyle.footnoteName, !used.floatStyles.contains(name), let style = source.floatStyles.first(where: { $0.name == name }) else { return }
            used.floatStyles.append(name)
            addList(style.listName)
            addStyle(style.contentStyle)
        }
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
            addStyle(attributes[.paragraphStyleName] as? String)
            addStyle(attributes[.wordStyleName] as? String)
            addStyle(attributes[.characterStyleName] as? String)
            for key in [NSAttributedString.Key.listItem, .finalParagraphList] {
                addList((attributes[key] as? String).flatMap(ListItem.init(encoded:))?.listName)
            }
            addFloatStyle(attributes[.footnote] as? String)
        }
        return used
    }

    /// I nomi usati dal testo che il documento di destinazione definisce in un altro modo. La serie delle note a piè
    /// di pagina non è mai in conflitto: c'è in ogni documento, e le note incollate entrano in quella della destinazione.
    public static func conflicts(of text: NSAttributedString, from source: Document, into destination: Document) -> [Conflict] {
        let used = used(in: text, source: source)
        var result: [Conflict] = []
        for name in used.styles {
            guard let theirs = destination.styles.style(named: name) else { continue }
            if theirs != source.styles.style(named: name) { result.append(Conflict(kind: .style, name: name)) }
        }
        for name in used.lists {
            guard let theirs = destination.lists.first(where: { $0.name == name }) else { continue }
            if theirs != source.lists.first(where: { $0.name == name }) { result.append(Conflict(kind: .list, name: name)) }
        }
        for name in used.floatStyles {
            guard let theirs = destination.floatStyles.first(where: { $0.name == name }) else { continue }
            if theirs != source.floatStyles.first(where: { $0.name == name }) { result.append(Conflict(kind: .floatStyle, name: name)) }
        }
        // Una definizione uguale che rimanda a una in conflitto (uno stile alla sua Lista, a quello su cui si basa)
        // in realtà vuol dire un'altra cosa: è in conflitto anche lei.
        var changed = true
        while changed {
            changed = false
            func depends(_ kind: Kind, _ name: String?) -> Bool { name.map { result.contains(Conflict(kind: kind, name: $0)) } ?? false }
            func add(_ conflict: Conflict) {
                guard !result.contains(conflict) else { return }
                result.append(conflict)
                changed = true
            }
            for name in used.styles where destination.styles.style(named: name) != nil {
                guard let style = source.styles.style(named: name) else { continue }
                if depends(.style, style.basedOn) || depends(.list, style.values.listName) { add(Conflict(kind: .style, name: name)) }
            }
            for name in used.lists where destination.lists.contains(where: { $0.name == name }) {
                guard case .list(let parent) = source.lists.first(where: { $0.name == name })?.parent else { continue }
                if depends(.list, parent) { add(Conflict(kind: .list, name: name)) }
            }
            for name in used.floatStyles where destination.floatStyles.contains(where: { $0.name == name }) {
                guard let style = source.floatStyles.first(where: { $0.name == name }) else { continue }
                if depends(.list, style.listName) || depends(.style, style.contentStyle) { add(Conflict(kind: .floatStyle, name: name)) }
            }
        }
        return result
    }

    /// Copia nel documento di destinazione le definizioni che il testo usa e riscrive il testo di conseguenza.
    /// Uno stile che nella destinazione è di un'altra specie (di paragrafo invece che di carattere) entra sempre
    /// come copia rinominata: il testo non potrebbe usare quello della destinazione.
    public static func merge(_ text: NSAttributedString, from source: Document, into destination: Document, policy: Policy) -> Result {
        let used = used(in: text, source: source)
        let conflicts = Set(conflicts(of: text, from: source, into: destination))
        var styleRenames: [String: String] = [:]
        var listRenames: [String: String] = [:]
        var floatRenames: [String: String] = [:]
        var takenStyles = Set(destination.styles.styles.map(\.name))
        var takenLists = Set(destination.lists.map(\.name))
        var takenFloats = Set(destination.floatStyles.map(\.name))
        func copyName(_ name: String, taken: inout Set<String>) -> String {
            var number = 2
            while taken.contains("\(name) (\(number))") { number += 1 }
            taken.insert("\(name) (\(number))")
            return "\(name) (\(number))"
        }
        var importedStyles: [String] = []
        var importedLists: [String] = []
        var importedFloats: [String] = []
        for name in used.styles {
            guard let theirs = destination.styles.style(named: name) else {
                importedStyles.append(name)
                continue
            }
            let otherTarget = theirs.target != source.styles.style(named: name)?.target
            if conflicts.contains(Conflict(kind: .style, name: name)), policy == .renameCopies || otherTarget {
                styleRenames[name] = copyName(name, taken: &takenStyles)
                importedStyles.append(name)
            }
        }
        for name in used.lists {
            if !destination.lists.contains(where: { $0.name == name }) {
                importedLists.append(name)
            } else if policy == .renameCopies, conflicts.contains(Conflict(kind: .list, name: name)) {
                listRenames[name] = copyName(name, taken: &takenLists)
                importedLists.append(name)
            }
        }
        for name in used.floatStyles {
            if !destination.floatStyles.contains(where: { $0.name == name }) {
                importedFloats.append(name)
            } else if policy == .renameCopies, conflicts.contains(Conflict(kind: .floatStyle, name: name)) {
                floatRenames[name] = copyName(name, taken: &takenFloats)
                importedFloats.append(name)
            }
        }

        // Le definizioni copiate, con i rimandi fra loro portati ai nomi nuovi.
        func renamedStyle(_ name: String?) -> String? { name.map { styleRenames[$0] ?? $0 } }
        func renamedList(_ name: String?) -> String? { name.map { listRenames[$0] ?? $0 } }
        var styles = destination.styles
        for name in importedStyles {
            guard var style = source.styles.style(named: name) else { continue }
            style.name = styleRenames[name] ?? name
            style.basedOn = renamedStyle(style.basedOn)
            style.values.listName = renamedList(style.values.listName)
            styles.styles.append(style)
        }
        var lists = destination.lists
        for name in importedLists {
            guard var list = source.lists.first(where: { $0.name == name }) else { continue }
            list.name = listRenames[name] ?? name
            if case .list(let parent) = list.parent { list.parent = .list(listRenames[parent] ?? parent) }
            lists.append(list)
        }
        var floatStyles = destination.floatStyles
        for name in importedFloats {
            guard var style = source.floatStyles.first(where: { $0.name == name }) else { continue }
            style.name = floatRenames[name] ?? name
            style.listName = renamedList(style.listName)
            style.contentStyle = renamedStyle(style.contentStyle)
            floatStyles.append(style)
        }

        // Il testo: prima le Liste e le serie di note, poi gli stili, che portano l'aspetto del testo da quello che
        // gli davano gli stili d'origine a quello che gli danno gli stili del documento di destinazione.
        let result = NSMutableAttributedString(attributedString: text)
        let all = NSRange(location: 0, length: result.length)
        if !listRenames.isEmpty {
            for key in [NSAttributedString.Key.listItem, .finalParagraphList] {
                result.enumerateAttribute(key, in: all) { value, range, _ in
                    guard let encoded = value as? String, var item = ListItem(encoded: encoded), let name = item.listName,
                          let new = listRenames[name] else { return }
                    item.listName = new
                    result.addAttribute(key, value: item.encoded, range: range)
                }
            }
        }
        if !floatRenames.isEmpty {
            result.enumerateAttribute(.footnote, in: all) { value, range, _ in
                guard let name = value as? String, let new = floatRenames[name] else { return }
                result.addAttribute(.footnote, value: new, range: range)
            }
        }
        TextStyling.restyle(result, range: all, from: source.styles.renamingLists(listRenames), to: styles) { names in
            names.paragraph = renamedStyle(names.paragraph)
            names.word = renamedStyle(names.word)
            names.character = renamedStyle(names.character)
        }
        return Result(text: result, styles: styles, lists: lists, floatStyles: floatStyles)
    }
}
