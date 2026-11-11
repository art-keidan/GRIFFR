import Foundation

/// Le letture testuali ammesse nelle presentazioni del formato 18.
/// I numeri sono già formattati dalla lista che li produce.
enum PresentationRead: Equatable {
    case pageNumber
    case pageCount
    case sectionTitle(role: String)
    case sectionNumber(role: String)
    case openedSectionNumber

    func value(in context: FieldContext, openedNumber: String?) -> String? {
        switch self {
        case .pageNumber: context.pageNumber
        case .pageCount: context.pageCount
        case .sectionTitle(let role): context.sections.last { $0.role == role }?.title
        case .sectionNumber(let role): context.sections.last { $0.role == role }?.number
        case .openedSectionNumber: openedNumber
        }
    }
}

/// Un testo da presentare. Un risultato assente o vuoto omette anche gli affissi.
/// Un'etichetta letterale può invece essere vuota e occupare comunque una fascia.
struct PresentationWrite {
    enum Expression {
        case literal(String)
        case read(PresentationRead)
    }

    let expression: Expression
    var prefix = ""
    var suffix = ""

    func text(in context: FieldContext, openedNumber: String? = nil) -> String? {
        switch expression {
        case .literal(let text): text
        case .read(let reading): Self.decorate(reading.value(in: context, openedNumber: openedNumber), prefix: prefix, suffix: suffix)
        }
    }

    static func decorate(_ value: String?, prefix: String, suffix: String) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return prefix + value + suffix
    }
}
