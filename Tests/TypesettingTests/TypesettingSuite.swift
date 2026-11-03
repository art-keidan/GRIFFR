import Testing

/// Contenitore di tutte le suite, eseguite una alla volta.
///
/// In parallelo i test creano font contemporaneamente da più thread e, a intermittenza, una richiesta di
/// Core Text al servizio dei font di sistema resta senza risposta, bloccando l'esecuzione (osservato più volte,
/// in `CTFontCreateWithName` e in `CTFontCreateWithFontDescriptor`).
@Suite("Typesetting", .serialized)
struct TypesettingSuite {}
