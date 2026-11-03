import Foundation

/// Il menu delle famiglie, raggruppato: le famiglie che cominciano con la stessa parola («Noto Sans», «Noto Serif»…)
/// stanno in un sottomenu che porta quella parola («Noto»), così le serie numerose non riempiono il menu. Le famiglie
/// senza compagne restano dove sono.
public enum FontFamilyMenu {
    public enum Entry: Hashable, Sendable {
        case family(String)
        /// Un sottomenu: la parola comune e le famiglie che contiene, nell'ordine dato.
        case group(String, [String])
    }

    /// La prima parola del nome di una famiglia: quella che decide il gruppo.
    public static func groupWord(of family: String) -> String {
        family.split(separator: " ").first.map(String.init) ?? family
    }

    /// Le voci del menu per famiglie già ordinate. Un gruppo nasce dove le famiglie con la stessa prima parola sono
    /// almeno `minimum`, e sta al posto della prima di esse.
    public static func entries(_ families: [String], minimum: Int = 2) -> [Entry] {
        var members: [String: [String]] = [:]
        for family in families { members[groupWord(of: family), default: []].append(family) }
        var result: [Entry] = []
        var placed: Set<String> = []
        for family in families {
            let word = groupWord(of: family)
            guard let group = members[word], group.count >= max(minimum, 2) else {
                result.append(.family(family))
                continue
            }
            if placed.insert(word).inserted { result.append(.group(word, group)) }
        }
        return result
    }
}
