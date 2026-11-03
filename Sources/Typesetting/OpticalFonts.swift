import AppKit
import CoreText

/// Un corpo ottico realizzato con file statici distinti, non con un asse `opsz`.
public enum StaticOpticalSize: String, Codable, Hashable, Sendable, CaseIterable {
    case caption, text, subhead, display

    public var title: String {
        switch self {
        case .caption: "Caption"
        case .text: "Testo"
        case .subhead: "Sottotitolo"
        case .display: "Display"
        }
    }
}

/// Ciò che un font dichiara sul proprio corpo ottico. La funzione OpenType `size` dà il corpo di progetto, la
/// sottofamiglia (i font che la condividono differiscono solo nel corpo) e la fascia d'uso consigliata; i nomi 16
/// (famiglia tipografica) e 21 (famiglia WWS) della tabella `name` dicono a quale famiglia completa appartiene.
struct OpticalDeclaration: Hashable, Sendable {
    /// Corpo di progetto in punti; `nil` senza la funzione `size`.
    var designSize: Double?
    /// Sottofamiglia della funzione `size`; 0 se non dichiarata.
    var subfamily = 0
    /// Fascia d'uso: dal limite inferiore escluso a quello superiore compreso, come vuole la specifica.
    var lower: Double?
    var upper: Double?
    /// Nome 16, la famiglia tipografica che riunisce anche facce che macOS mostra in famiglie separate.
    var typographicFamily: String?
    /// Nome 21: diverso dal 16 quando la faccia si distingue per qualcosa che non è peso, larghezza o inclinazione,
    /// per esempio il corpo ottico.
    var wwsFamily: String?

    /// La fascia d'uso, se il font ne dichiara una utilizzabile.
    var range: ClosedRange<Double>? {
        guard let lower, let upper, upper > lower, upper > 0 else { return nil }
        return lower...upper
    }

    /// Vero se il font si dichiara un corpo ottico: con una fascia d'uso, o con una famiglia WWS distinta da quella
    /// tipografica. Il solo nome 16 non basta: spesso separa soltanto i pesi (Minion Std Black).
    var isOptical: Bool {
        if range != nil { return true }
        if let wwsFamily, let typographicFamily, wwsFamily != typographicFamily { return true }
        return false
    }

    /// Legge le dichiarazioni dalle tabelle `GPOS` e `name` del font.
    init(font: CTFont) {
        if let size = Self.sizeFeature(font.tableBytes("GPOS")) {
            designSize = size.design
            subfamily = size.subfamily
            lower = size.lower
            upper = size.upper
        }
        let names = Self.names([16, 21], in: font.tableBytes("name"))
        typographicFamily = names[16]
        wwsFamily = names[21]
    }

    init(designSize: Double? = nil, subfamily: Int = 0, lower: Double? = nil, upper: Double? = nil,
         typographicFamily: String? = nil, wwsFamily: String? = nil) {
        self.designSize = designSize
        self.subfamily = subfamily
        self.lower = lower
        self.upper = upper
        self.typographicFamily = typographicFamily
        self.wwsFamily = wwsFamily
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int? {
        offset >= 0 && offset + 1 < bytes.count ? Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) : nil
    }

    /// I parametri della funzione `size` di `GPOS`, in decimi di punto nel font. La specifica misura lo scostamento
    /// dei parametri dall'inizio della funzione; alcuni font vecchi lo misurano dall'inizio dell'elenco delle funzioni:
    /// si prova la lettura corretta, poi quella storica, e si accetta solo un corpo coerente con la sua fascia.
    static func sizeFeature(_ gpos: [UInt8]) -> (design: Double, subfamily: Int, lower: Double?, upper: Double?)? {
        guard let listOffset = u16(gpos, 6), let count = u16(gpos, listOffset) else { return nil }
        for index in 0..<count {
            let record = listOffset + 2 + 6 * index
            guard record + 6 <= gpos.count, String(bytes: gpos[record..<record + 4], encoding: .isoLatin1) == "size",
                  let featureOffset = u16(gpos, record + 4), let paramsOffset = u16(gpos, listOffset + featureOffset),
                  paramsOffset > 0 else { continue }
            for base in [listOffset + featureOffset + paramsOffset, listOffset + paramsOffset] {
                guard let design = u16(gpos, base), design > 0, let subfamily = u16(gpos, base + 2),
                      let start = u16(gpos, base + 6), let end = u16(gpos, base + 8) else { continue }
                let declaresRange = !(start == 0 && end == 0)
                guard !declaresRange || (start < design && design <= end) else { continue }
                return (Double(design) / 10, subfamily, declaresRange ? Double(start) / 10 : nil, declaresRange ? Double(end) / 10 : nil)
            }
        }
        return nil
    }

    /// I nomi richiesti della tabella `name`: prima Windows inglese, poi Unicode, poi Macintosh Roman.
    static func names(_ ids: Set<Int>, in table: [UInt8]) -> [Int: String] {
        guard let count = u16(table, 2), let storage = u16(table, 4) else { return [:] }
        var found: [Int: (rank: Int, value: String)] = [:]
        for index in 0..<count {
            let record = 6 + 12 * index
            guard let platform = u16(table, record), let encoding = u16(table, record + 2), let language = u16(table, record + 4),
                  let id = u16(table, record + 6), ids.contains(id), let length = u16(table, record + 8),
                  let offset = u16(table, record + 10), storage + offset + length <= table.count else { continue }
            let bytes = Array(table[(storage + offset)..<(storage + offset + length)])
            let candidate: (rank: Int, value: String?)
            switch (platform, encoding, language) {
            case (3, 1, 0x409): candidate = (0, String(bytes: bytes, encoding: .utf16BigEndian))
            case (0, _, _): candidate = (1, String(bytes: bytes, encoding: .utf16BigEndian))
            case (1, 0, 0): candidate = (2, String(bytes: bytes, encoding: .macOSRoman))
            default: continue
            }
            guard let value = candidate.value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { continue }
            if found[id].map({ candidate.rank < $0.rank }) ?? true { found[id] = (candidate.rank, value) }
        }
        return found.mapValues(\.value)
    }
}

/// Raggruppa le famiglie che macOS presenta separatamente ma che sono corpi ottici dello stesso carattere.
///
/// Come le applicazioni Adobe, si fida prima di ciò che i font dichiarano: la funzione `size` (stessa sottofamiglia,
/// corpi di progetto diversi) e i nomi 16 e 21. Solo per le famiglie che non dichiarano nulla usa le terminazioni del
/// nome (Caption, Text, Subhead, Display). La scelta automatica segue la fascia d'uso di ciascun corpo; le soglie fisse
/// valgono solo per i gruppi riconosciuti dal nome.
public enum OpticalFonts {
    struct FamilyGroup: Equatable {
        var family: String
        var reference: String
        var variants: [StaticOpticalSize: String]
        /// La fascia d'uso dichiarata da ciascuna famiglia del gruppo, quando c'è.
        var ranges: [String: ClosedRange<Double>] = [:]
    }

    /// Una famiglia installata, con ciò che dichiara la sua faccia di riferimento (`nil`: niente da leggere).
    struct FamilyDescription: Equatable {
        var family: String
        var declaration: OpticalDeclaration?
    }

    private static let suffixes: [(String, StaticOpticalSize)] = [
        ("Caption", .caption), ("Capt", .caption), ("Text", .text), ("Subhead", .subhead), ("Subh", .subhead),
        ("Display", .display), ("Disp", .display),
    ]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var groups = makeGroups(installedDescriptions(NSFontManager.shared.availableFontFamilies))

    /// Le dichiarazioni già lette, per famiglia: i popup dei font chiedono i gruppi spesso. Ha un lucchetto suo,
    /// perché i gruppi si costruiscono la prima volta mentre `lock` è già preso.
    private static let declarationLock = NSLock()
    nonisolated(unsafe) private static var declarations: [String: OpticalDeclaration?] = [:]

    /// Rilegge le famiglie dopo la registrazione di nuovi font nel processo.
    static func refresh() {
        declarationLock.lock()
        declarations = [:]
        inFamily = [:]
        opticalInstances = [:]
        declarationLock.unlock()
        let updated = makeGroups(installedDescriptions(NSFontManager.shared.availableFontFamilies))
        lock.lock()
        groups = updated
        lock.unlock()
    }

    private static func currentGroups() -> [FamilyGroup] {
        lock.lock()
        defer { lock.unlock() }
        return groups
    }

    /// Le dichiarazioni delle famiglie installate. Si leggono solo quelle che potrebbero stare in un gruppo: le famiglie
    /// che condividono la prima parola del nome con un'altra. Le altre non hanno con chi raggrupparsi.
    static func installedDescriptions(_ available: [String]) -> [FamilyDescription] {
        let firstWords = Dictionary(grouping: available) { $0.split(separator: " ").first.map(String.init) ?? $0 }
        return available.map { family in
            let key = family.split(separator: " ").first.map(String.init) ?? family
            guard (firstWords[key]?.count ?? 0) > 1 else { return FamilyDescription(family: family, declaration: nil) }
            return FamilyDescription(family: family, declaration: declaration(ofFamily: family))
        }
    }

    private static func declaration(ofFamily family: String) -> OpticalDeclaration? {
        declarationLock.lock()
        if let known = declarations[family] {
            declarationLock.unlock()
            return known
        }
        declarationLock.unlock()
        let value = (NSFontManager.shared.availableMembers(ofFontFamily: family)?.first?.first as? String).map {
            OpticalDeclaration(font: CTFontCreateWithName($0 as CFString, 12, nil))
        }
        declarationLock.lock()
        declarations[family] = .some(value)
        declarationLock.unlock()
        return value
    }

    /// Il corpo ottico indicato dalla terminazione del nome, togliendo la famiglia di base.
    private static func suffixSize(of family: String, base: String) -> StaticOpticalSize? {
        guard family != base, family.hasPrefix(base + " ") else { return nil }
        let rest = String(family.dropFirst(base.count + 1))
        return suffixes.first { rest == $0.0 }?.1
    }

    /// Il posto nel menu di un corpo che il nome non indica: dal suo corpo di progetto.
    private static func size(forDesign design: Double) -> StaticOpticalSize {
        if design < 9.5 { return .caption }
        if design <= 14 { return .text }
        if design < 24 { return .subhead }
        return .display
    }

    private static func droppingLastWord(_ name: String) -> String {
        var words = name.split(separator: " ")
        guard words.count > 1 else { return name }
        words.removeLast()
        return words.joined(separator: " ")
    }

    /// I gruppi, prima dalle dichiarazioni dei font, poi dalle terminazioni dei nomi per le famiglie che non ne hanno.
    static func makeGroups(_ descriptions: [FamilyDescription]) -> [FamilyGroup] {
        var result: [FamilyGroup] = []
        var used: Set<String> = []
        let declared = descriptions.filter { $0.declaration?.isOptical == true }

        // Costruisce un gruppo dalle famiglie candidate con la stessa base: corpi di progetto diversi, posti diversi.
        func addGroup(base: String, members: [FamilyDescription]) {
            var variants: [StaticOpticalSize: String] = [:]
            var ranges: [String: ClosedRange<Double>] = [:]
            var designs: Set<Double> = []
            // Prima la famiglia di base, poi le altre in ordine di corpo di progetto.
            let ordered = members.sorted { a, b in
                if (a.family == base) != (b.family == base) { return a.family == base }
                return (a.declaration?.designSize ?? 0) < (b.declaration?.designSize ?? 0)
            }
            for member in ordered {
                // Due famiglie con lo stesso corpo di progetto non sono corpi ottici l'una dell'altra (Minion Pro IE).
                if let design = member.declaration?.designSize, !designs.insert(design).inserted { continue }
                let slot = suffixSize(of: member.family, base: base)
                    ?? (member.family == base ? .text : member.declaration?.designSize.map(size(forDesign:)))
                guard let slot, variants[slot] == nil else { continue }
                variants[slot] = member.family
                if let range = member.declaration?.range { ranges[member.family] = range }
            }
            guard Set(variants.values).count >= 2 else { return }
            let reference = variants[.text] ?? StaticOpticalSize.allCases.compactMap { variants[$0] }.first!
            result.append(FamilyGroup(family: base, reference: reference, variants: variants, ranges: ranges))
            used.formUnion(variants.values)
        }

        // 1. La famiglia tipografica (nome 16), quando i font la dichiarano.
        let byTypographic = Dictionary(grouping: declared.filter { $0.declaration?.typographicFamily != nil }) {
            $0.declaration!.typographicFamily!
        }
        for (base, members) in byTypographic.sorted(by: { $0.key < $1.key }) where members.count > 1 {
            addGroup(base: base, members: members)
        }

        // 2. Senza nome 16: stessa sottofamiglia `size`, e una famiglia di base il cui nome apre quello delle altre
        //    (Minion 3, Minion 3 Caption…), oppure, senza base installata, lo stesso nome tolta l'ultima parola.
        let untyped = declared.filter { $0.declaration?.typographicFamily == nil && !used.contains($0.family) }
        for candidate in untyped.sorted(by: { $0.family.count < $1.family.count }) where !used.contains(candidate.family) {
            let subfamily = candidate.declaration?.subfamily
            let others = untyped.filter {
                !used.contains($0.family) && $0.declaration?.subfamily == subfamily && $0.family.hasPrefix(candidate.family + " ")
            }
            if !others.isEmpty { addGroup(base: candidate.family, members: [candidate] + others) }
        }
        let leftovers = untyped.filter { !used.contains($0.family) }
        let byStem = Dictionary(grouping: leftovers) { "\($0.declaration?.subfamily ?? 0)|" + droppingLastWord($0.family) }
        for (_, members) in byStem.sorted(by: { $0.key < $1.key }) where members.count > 1 {
            addGroup(base: droppingLastWord(members[0].family), members: members)
        }

        // 3. Ripiego per le famiglie che non dichiarano nulla: le terminazioni del nome.
        let silent = descriptions.filter { $0.declaration?.isOptical != true && !used.contains($0.family) }
        let installed = Set(silent.map(\.family))
        var candidates: [String: [StaticOpticalSize: String]] = [:]
        for description in silent {
            for (suffix, size) in suffixes where description.family.hasSuffix(" " + suffix) {
                let base = String(description.family.dropLast(suffix.count + 1))
                if !base.isEmpty, candidates[base, default: [:]][size] == nil { candidates[base, default: [:]][size] = description.family }
                break
            }
        }
        for (base, found) in candidates.sorted(by: { $0.key < $1.key }) {
            var variants = found
            if installed.contains(base), variants[.text] == nil { variants[.text] = base }
            // Un solo «Text» nel nome (per esempio Hoefler Text) non basta a dimostrare un gruppo ottico.
            guard Set(variants.keys).count >= 2, Set(variants.values).count >= 2,
                  let reference = variants[.text] ?? StaticOpticalSize.allCases.compactMap({ variants[$0] }).first
            else { continue }
            result.append(FamilyGroup(family: base, reference: reference, variants: variants))
        }
        return result
    }

    private static func group(forFamily family: String, in groups: [FamilyGroup]) -> FamilyGroup? {
        groups.first { $0.family == family || $0.variants.values.contains(family) }
    }

    private static func group(forFamily family: String) -> FamilyGroup? {
        group(forFamily: family, in: currentGroups())
    }

    /// La famiglia unica da mostrare, oppure `nil` se non appartiene a un gruppo ottico riconosciuto.
    public static func canonicalFamily(_ family: String) -> String? {
        group(forFamily: family)?.family
    }

    /// La famiglia da mostrare per questo font: quella unificata se ha corpi ottici statici.
    public static func family(of font: CTFont) -> String {
        let actual = CTFontCopyFamilyName(font) as String
        return canonicalFamily(actual) ?? actual
    }

    /// Unifica le famiglie ottiche nell'elenco dei popup; tutte le altre restano invariate.
    public static func families(_ available: [String]) -> [String] {
        let groups = makeGroups(installedDescriptions(available))
        var result: [String] = []
        for family in available {
            let shown = group(forFamily: family, in: groups)?.family ?? family
            if !result.contains(shown) { result.append(shown) }
        }
        return result
    }

    // MARK: Corpi ottici dentro una sola famiglia

    /// Una famiglia in cui i corpi ottici sono facce, non famiglie a sé (Warnock Pro: Light, Light Caption, Light
    /// Display…). Il corpo si riconosce dall'ultima parola del nome dello stile; la fascia d'uso, quando c'è, dalla
    /// funzione `size` di ciascun corpo.
    struct InFamilyGroup: Equatable {
        var family: String
        /// La parola che il nome dello stile aggiunge per ciascun corpo; per il corpo del testo è vuota.
        var suffixes: [StaticOpticalSize: String]
        var ranges: [StaticOpticalSize: ClosedRange<Double>] = [:]
    }

    nonisolated(unsafe) private static var inFamily: [String: InFamilyGroup?] = [:]

    /// Stile di base, corpo e parola del corpo di un nome di stile: «Light Italic Caption» → («Light Italic», caption,
    /// «Caption»); «Caption» → («Regular», caption, «Caption»). `nil` se lo stile non nomina un corpo ottico.
    static func splitStyle(_ style: String) -> (base: String, size: StaticOpticalSize, word: String)? {
        var words = style.split(separator: " ").map(String.init)
        guard let last = words.last, let size = suffixes.first(where: { $0.0 == last })?.1, size != .text else { return nil }
        words.removeLast()
        return (words.isEmpty ? "Regular" : words.joined(separator: " "), size, last)
    }

    /// Vero se il nome dello stile nomina un corpo ottico in qualsiasi posizione: «Light Caption» (Warnock Pro) come
    /// «Caption Bold» o «Display Semibold Italic» (le istanze di Adobe Kis VF).
    static func namesOpticalSize(style: String) -> Bool {
        style.split(separator: " ").contains { word in suffixes.contains { $0.0 == word && $0.1 != .text } }
    }

    /// Lo stile del corpo `word` a partire da quello di base: «Regular» + «Caption» → «Caption».
    static func joinStyle(_ base: String, _ word: String) -> String {
        word.isEmpty ? base : (base == "Regular" ? word : base + " " + word)
    }

    /// Il gruppo ottico interno alla famiglia, se ne ha uno: almeno una faccia di corpo ottico e almeno una normale.
    static func inFamilyGroup(for family: String) -> InFamilyGroup? {
        declarationLock.lock()
        if let known = inFamily[family] {
            declarationLock.unlock()
            return known
        }
        declarationLock.unlock()
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        var suffixes: [StaticOpticalSize: String] = [:]
        var representative: [StaticOpticalSize: String] = [:]
        var hasPlain = false
        for member in members {
            guard member.count > 1, let name = member[0] as? String, let style = member[1] as? String else { continue }
            if let split = splitStyle(style) {
                if suffixes[split.size] == nil { suffixes[split.size] = split.word; representative[split.size] = name }
            } else {
                hasPlain = true
                if representative[.text] == nil { representative[.text] = name }
            }
        }
        var group: InFamilyGroup?
        let namesOpticalSizes = hasPlain && !suffixes.isEmpty
        // Un font variabile con l'asse `opsz` (Adobe Kis VF) ha istanze con un nome per i corpi ottici (Caption,
        // Display…), ma il corpo ottico lo regola l'asse, che segue il corpo da sé: non è un gruppo di facce statiche.
        let opticalAxis = namesOpticalSizes && representative[.text].map {
            FontVariations.axes(of: CTFontCreateWithName($0 as CFString, 12, nil)).contains { $0.tag == "opsz" }
        } == true
        if namesOpticalSizes, !opticalAxis {
            suffixes[.text] = ""
            var ranges: [StaticOpticalSize: ClosedRange<Double>] = [:]
            for (size, name) in representative {
                if let range = OpticalDeclaration(font: CTFontCreateWithName(name as CFString, 12, nil)).range { ranges[size] = range }
            }
            group = InFamilyGroup(family: family, suffixes: suffixes, ranges: ranges)
        }
        declarationLock.lock()
        inFamily[family] = .some(group)
        opticalInstances[family] = namesOpticalSizes
        declarationLock.unlock()
        return group
    }

    nonisolated(unsafe) private static var opticalInstances: [String: Bool] = [:]

    /// Vero se fra le facce della famiglia ce ne sono che nominano un corpo ottico (Caption, Subhead, Display) accanto
    /// a quelle normali: un gruppo ottico statico, oppure le istanze con un nome di un font variabile con l'asse `opsz`.
    /// Nei menu delle facce e nella scelta del tondo e del nero restano solo quelle normali.
    static func namesOpticalSizes(family: String) -> Bool {
        _ = inFamilyGroup(for: family)
        declarationLock.lock()
        defer { declarationLock.unlock() }
        return opticalInstances[family] ?? false
    }

    /// Il corpo adatto alla dimensione: quello la cui fascia dichiarata la contiene; fuori da tutte, il più piccolo o il
    /// più grande; senza fasce, le soglie di ripiego e, se quel corpo manca, il più vicino fra quelli presenti.
    static func automaticSize(available: Set<StaticOpticalSize>, ranges: [StaticOpticalSize: ClosedRange<Double>],
                              pointSize: CGFloat) -> StaticOpticalSize? {
        let size = Double(pointSize)
        let ranged = ranges.filter { available.contains($0.key) }.sorted { $0.value.lowerBound < $1.value.lowerBound }
        if !ranged.isEmpty {
            if let hit = ranged.first(where: { size > $0.value.lowerBound && size <= $0.value.upperBound }) { return hit.key }
            return size <= ranged[0].value.lowerBound ? ranged[0].key : ranged.max { $0.value.upperBound < $1.value.upperBound }?.key
        }
        let all = StaticOpticalSize.allCases
        let index = all.firstIndex(of: automaticSize(forPointSize: pointSize))!
        return all.indices.filter { available.contains(all[$0]) }.min { abs($0 - index) < abs($1 - index) }.map { all[$0] }
    }

    // MARK: Interrogazioni

    /// Le facce della famiglia ottica di riferimento: sono le stesse in ciascuna variante, quando disponibili. In una
    /// famiglia con i corpi ottici fra le facce, restano solo quelle del corpo del testo.
    public static func members(ofFamily family: String) -> [[Any]] {
        if namesOpticalSizes(family: family) {
            return (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).filter {
                $0.count > 1 && ($0[1] as? String).map { !namesOpticalSize(style: $0) } == true
            }
        }
        let reference = group(forFamily: family)?.reference ?? family
        return NSFontManager.shared.availableMembers(ofFontFamily: reference) ?? []
    }

    /// Il corpo ottico statico del font; `nil` per i font fuori dai gruppi riconosciuti.
    public static func opticalSize(of font: CTFont) -> StaticOpticalSize? {
        let family = CTFontCopyFamilyName(font) as String
        if inFamilyGroup(for: family) != nil { return style(of: font).flatMap { splitStyle($0)?.size } ?? .text }
        guard let group = group(forFamily: family) else { return nil }
        return group.variants.first { $0.value == family }?.key ?? (family == group.family ? .text : nil)
    }

    /// I soli corpi ottici che questa famiglia possiede davvero, nell'ordine del menu.
    public static func availableSizes(of font: CTFont) -> [StaticOpticalSize] {
        let family = CTFontCopyFamilyName(font) as String
        if let inside = inFamilyGroup(for: family) { return StaticOpticalSize.allCases.filter { inside.suffixes[$0] != nil } }
        guard let group = group(forFamily: family) else { return [] }
        return StaticOpticalSize.allCases.filter { group.variants[$0] != nil }
    }

    /// Fasce di ripiego, per i gruppi riconosciuti dal nome: Caption fino a 8,4; Text 8,5–13; Subhead 13,1–19,9;
    /// Display da 20. I gruppi che dichiarano le proprie fasce usano quelle.
    public static func automaticSize(forPointSize pointSize: CGFloat) -> StaticOpticalSize {
        if pointSize < 8.5 { return .caption }
        if pointSize <= 13 { return .text }
        if pointSize < 20 { return .subhead }
        return .display
    }

    /// La famiglia del gruppo adatta al corpo: quella la cui fascia dichiarata lo contiene (estremo inferiore escluso,
    /// superiore compreso); fuori da tutte le fasce, la più piccola o la più grande. Senza fasce, le soglie di ripiego
    /// e, se quel corpo manca, il più vicino fra quelli presenti.
    static func automaticFamily(in group: FamilyGroup, pointSize: CGFloat) -> String? {
        let size = Double(pointSize)
        let ranged = group.variants.values.compactMap { family in group.ranges[family].map { (family, $0) } }
            .sorted { $0.1.lowerBound < $1.1.lowerBound }
        if !ranged.isEmpty {
            if let hit = ranged.first(where: { size > $0.1.lowerBound && size <= $0.1.upperBound }) { return hit.0 }
            return size <= ranged[0].1.lowerBound ? ranged[0].0 : ranged.max { $0.1.upperBound < $1.1.upperBound }?.0
        }
        let wanted = automaticSize(forPointSize: pointSize)
        let all = StaticOpticalSize.allCases
        let index = all.firstIndex(of: wanted)!
        let nearest = all.indices.filter { group.variants[all[$0]] != nil }.min { abs($0 - index) < abs($1 - index) }
        return nearest.flatMap { group.variants[all[$0]] }
    }

    /// Il nome della stessa faccia nella famiglia di riferimento, per selezionarla nel popup.
    public static func baseFaceName(of font: CTFont) -> String {
        let family = CTFontCopyFamilyName(font) as String
        if inFamilyGroup(for: family) != nil, let style = style(of: font), let split = splitStyle(style) {
            return face(in: family, style: split.base) ?? font.postScriptName
        }
        guard let group = group(forFamily: CTFontCopyFamilyName(font) as String),
              let style = style(of: font) else { return font.postScriptName }
        return face(in: group.reference, style: style) ?? font.postScriptName
    }

    /// La stessa faccia nel corpo ottico chiesto; `nil` sceglie quello adatto al corpo del font.
    /// Per un font fuori dai gruppi riconosciuti restituisce il font invariato.
    public static func font(_ font: CTFont, opticalSize requested: StaticOpticalSize?) -> CTFont {
        let actualFamily = CTFontCopyFamilyName(font) as String
        if let inside = inFamilyGroup(for: actualFamily) {
            guard let style = style(of: font) else { return font }
            let base = splitStyle(style)?.base ?? style
            let target = requested ?? automaticSize(available: Set(inside.suffixes.keys), ranges: inside.ranges, pointSize: font.pointSize)
            guard let target, let word = inside.suffixes[target], let name = face(in: actualFamily, style: joinStyle(base, word)),
                  name != font.postScriptName, let changed = NSFont(name: name, size: font.pointSize) as CTFont? else { return font }
            return FontFeatures.font(changed, with: FontFeatures.settings(of: font))
        }
        guard let group = group(forFamily: actualFamily) else { return font }
        let targetFamily = requested.map { group.variants[$0] } ?? automaticFamily(in: group, pointSize: font.pointSize)
        guard let targetFamily, let style = style(of: font), let name = face(in: targetFamily, style: style),
              name != font.postScriptName, let changed = NSFont(name: name, size: font.pointSize) as CTFont?
        else { return font }
        return FontFeatures.font(changed, with: FontFeatures.settings(of: font))
    }

    /// Cambia corpo e, se appartiene a un gruppo ottico, anche la variante richiesta o quella automatica.
    public static func resized(_ font: CTFont, to size: CGFloat, opticalSize: StaticOpticalSize?) -> CTFont {
        self.font(TextStyling.resizedWithoutOpticalSize(font, to: size), opticalSize: opticalSize)
    }

    private static func style(of font: CTFont) -> String? {
        let family = CTFontCopyFamilyName(font) as String
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        return members.first { $0.first as? String == font.postScriptName }?[1] as? String
            ?? CTFontCopyAttribute(font, kCTFontStyleNameAttribute) as? String
    }

    private static func face(in family: String, style: String) -> String? {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).first {
            $0.count > 1 && $0[1] as? String == style
        }?.first as? String
    }
}
