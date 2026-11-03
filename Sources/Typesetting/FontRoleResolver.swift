import AppKit
import CoreText

/// Quale installazione di una famiglia si vuole usare.
public enum FontInstallation: String, Codable, Hashable, Sendable {
    /// Conserva, se possibile, la forma del font corrente; altrimenti usa quella disponibile.
    case automatic
    case staticFiles
    case variableFont
}

/// Il risultato della risoluzione di un ruolo, pronto per essere applicato a uno stile di carattere.
public enum FontFaceResolution: Hashable, Sendable {
    case staticFace(String)
    case variableInstance(VariableFontInstance)

    public var installation: FontInstallation {
        switch self {
        case .staticFace: .staticFiles
        case .variableInstance: .variableFont
        }
    }

    public var fontName: String {
        switch self {
        case .staticFace(let name): name
        case .variableInstance(let instance): instance.fontName
        }
    }

    public var variations: [AxisValue] {
        switch self {
        case .staticFace: []
        case .variableInstance(let instance): instance.variations
        }
    }

    public var prefersVariableFont: Bool {
        switch self {
        case .staticFace: false
        case .variableInstance(let instance): instance.prefersVariableFont
        }
    }
}

/// Trasforma una richiesta semantica nella faccia indicata dalle equivalenze. È l'unico punto che sceglie fra
/// faccia statica e istanza variabile; i comandi dell'interfaccia vi arriveranno nelle tappe successive.
public struct FontRoleResolver: Hashable, Sendable {
    public var table: FontRoleTable

    public init(table: FontRoleTable = FontRoleTable()) {
        self.table = table
    }

    /// Risolve `role` nella famiglia. In automatico segue l'installazione di `current`; con
    /// `preservingAxes` conserva gli assi del corrente che l'equivalenza del ruolo non sostituisce, eliminando
    /// quelli assenti dal font e riportando i valori ai limiti dichiarati.
    public func resolve(family: String, role: FontRole, installation: FontInstallation = .automatic,
                        current: CharacterStyle? = nil, preservingAxes: Bool = false) -> FontFaceResolution? {
        let equivalence = table.equivalence(family: family, role: role)
        func staticFace() -> FontFaceResolution? { resolvedStatic(equivalence.staticFace) }
        func variable() -> FontFaceResolution? {
            resolvedVariable(equivalence.variableInstance, current: preservingAxes ? current : nil)
        }
        switch installation {
        case .staticFiles: return staticFace()
        case .variableFont: return variable()
        case .automatic:
            let currentIsVariable = current.map { $0.prefersVariableFont || !$0.variations.isEmpty } ?? false
            if currentIsVariable { return variable() ?? staticFace() }
            return staticFace() ?? variable()
        }
    }

    /// La famiglia del font corrente, anche quando il nome PostScript non è elencato fra le facce statiche.
    public func family(of current: CharacterStyle) -> String? {
        FontVariations.font(named: current.fontName, size: current.size,
                            preferringVariable: current.prefersVariableFont || !current.variations.isEmpty).map {
            OpticalFonts.family(of: $0)
        }
    }

    /// L'intenzione conservata nello stile; nei documenti precedenti, il ruolo la cui equivalenza produce la faccia
    /// corrente. Restituisce `nil` per una faccia libera o un'istanza con assi scelti fuori dai ruoli noti.
    public func role(of current: CharacterStyle) -> FontRole? {
        if let role = current.fontRole { return role }
        guard let family = family(of: current) else { return nil }
        let wantsVariable = current.prefersVariableFont || !current.variations.isEmpty
        // Gli assi estranei ai ruoli (larghezza, dimensione ottica…) non impediscono il riconoscimento.
        let governedTags = Set(FontRole.allCases.flatMap {
            table.equivalence(family: family, role: $0).variableInstance?.variations.map(\.tag) ?? []
        })
        let currentRoleAxes = current.variations.filter { governedTags.contains($0.tag) }
        return FontRole.allCases.first { role in
            guard let resolved = resolve(family: family, role: role, current: current) else { return false }
            return resolved.fontName == current.fontName && resolved.variations == currentRoleAxes
                && (resolved.installation == .variableFont) == wantsVariable
        }
    }

    /// Applica l'intenzione a uno stile completo, conservando gli assi non governati dal ruolo e le altre proprietà.
    public func applying(role: FontRole, to current: CharacterStyle) -> CharacterStyle? {
        guard let family = family(of: current),
              let face = resolve(family: family, role: role, current: current, preservingAxes: true) else { return nil }
        var result = current
        if result.fontName != face.fontName { result.features = [] }
        result.fontName = face.fontName
        result.variations = face.variations
        result.prefersVariableFont = face.prefersVariableFont
        result.fontRole = role
        return result
    }

    /// Applica il ruolo conservando il peso esatto del testo: serve al corsivo, che non deve toccare il peso di una faccia
    /// libera (un testo che realizza un ruolo segue invece le equivalenze). Una faccia
    /// statica diventa quella con il corsivo chiesto e il peso più vicino (Semibold → Semibold Italic, non Bold Italic);
    /// un'istanza variabile conserva il valore di `wght`. Il ruolo resta registrato solo se la faccia ottenuta lo
    /// realizza davvero secondo le equivalenze; altrimenti è una faccia libera.
    public func applying(role: FontRole, to current: CharacterStyle, keepingWeight: Bool) -> CharacterStyle? {
        guard keepingWeight else { return applying(role: role, to: current) }
        // Un testo che realizza un ruolo delle equivalenze va alla faccia del ruolo chiesto, come per il nero: il peso
        // da conservare conta solo per le facce libere (un Semibold fuori dai ruoli, un `wght` regolato a mano).
        if let currentRole = self.role(of: current), realizes(currentRole, current) {
            return applying(role: role, to: current)
        }
        var result = current
        let wantsVariable = current.prefersVariableFont || !current.variations.isEmpty
        if wantsVariable, let family = family(of: current),
           case .variableInstance(let instance)? = resolve(family: family, role: role, installation: .variableFont,
                                                         current: current, preservingAxes: true),
           let font = FontVariations.font(named: instance.fontName, size: 12, preferringVariable: true) {
            var variations = instance.variations.filter { $0.tag != "wght" }
            // Un peso fissato resta, entro i limiti del font di arrivo; senza peso fissato resta quello naturale.
            if let weight = current.variations.first(where: { $0.tag == "wght" }),
               let axis = FontVariations.axes(of: font).first(where: { $0.tag == "wght" }) {
                variations.append(AxisValue(tag: "wght", value: min(max(weight.value, axis.minimum), axis.maximum)))
            }
            let order = FontVariations.axes(of: font).map(\.tag)
            variations.sort { (order.firstIndex(of: $0.tag) ?? .max) < (order.firstIndex(of: $1.tag) ?? .max) }
            if instance.fontName != current.fontName { result.features = [] }
            result.fontName = instance.fontName
            result.variations = variations
            result.prefersVariableFont = instance.prefersVariableFont
        } else {
            guard let description = FontFaces.description(of: current.fontName),
                  let face = FontFaces.face(family: description.family, italic: role.isItalic, bold: description.bold,
                                            weightNear: description.weight) else { return nil }
            if face != current.fontName { result.features = [] }
            result.fontName = face
            result.variations = []
            result.prefersVariableFont = false
        }
        result.fontRole = realizes(role, result) ? role : nil
        return result
    }

    /// Vero se lo stile è esattamente la faccia che le equivalenze danno per `role`: stesso font, stessi assi governati
    /// dal ruolo, stessa installazione (statica o variabile).
    func realizes(_ role: FontRole, _ style: CharacterStyle) -> Bool {
        guard let family = family(of: style), let resolved = resolve(family: family, role: role, current: style) else { return false }
        let governed = Set(resolved.variations.map(\.tag))
        let wantsVariable = style.prefersVariableFont || !style.variations.isEmpty
        return resolved.fontName == style.fontName && resolved.variations == style.variations.filter { governed.contains($0.tag) }
            && (resolved.installation == .variableFont) == wantsVariable
    }

    private func resolvedStatic(_ name: String?) -> FontFaceResolution? {
        guard let name, let font = NSFont(name: name, size: 12) as CTFont?, !FontVariations.isVariable(font) else { return nil }
        return .staticFace(name)
    }

    private func resolvedVariable(_ instance: VariableFontInstance?, current: CharacterStyle?) -> FontFaceResolution? {
        guard let instance,
              let font = FontVariations.font(named: instance.fontName, size: 12, preferringVariable: true),
              FontVariations.isVariable(font) else { return nil }
        var requested = current?.variations ?? []
        for value in instance.variations {
            requested.removeAll { $0.tag == value.tag }
            requested.append(value)
        }
        // L'ordine è quello della tabella fvar, così la stessa istanza ha sempre la stessa rappresentazione.
        let normalized = FontVariations.axes(of: font).compactMap { axis in
            requested.last(where: { $0.tag == axis.tag }).map {
                let clamped = min(max($0.value, axis.minimum), axis.maximum)
                return AxisValue(tag: axis.tag, value: (clamped * 10_000).rounded() / 10_000)
            }
        }
        return .variableInstance(VariableFontInstance(fontName: instance.fontName, variations: normalized,
                                                      prefersVariableFont: instance.prefersVariableFont))
    }
}
