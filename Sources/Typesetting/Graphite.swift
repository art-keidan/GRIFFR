import CoreText
import Darwin
import Foundation

// MARK: - Graphite: il ponte verso graphite2, se è installata

/// La libreria `graphite2` di SIL, caricata al volo dal sistema (Homebrew o MacPorts). Il suo codice non sta nel
/// programma (scelta di Artemij Keidan, 19 ottobre 2026): se la libreria non c'è, Graphite non è disponibile e il testo
/// che lo chiede si compone con Core Text, con un avviso.
public enum Graphite {
    /// Dove si cerca la libreria, nell'ordine.
    static let searchPaths = [
        "/opt/homebrew/lib/libgraphite2.3.dylib",
        "/opt/homebrew/opt/graphite2/lib/libgraphite2.3.dylib",
        "/usr/local/lib/libgraphite2.3.dylib",
        "/usr/local/opt/graphite2/lib/libgraphite2.3.dylib",
        "/opt/local/lib/libgraphite2.3.dylib",
    ]

    /// Vero se la libreria si è caricata.
    public static var isAvailable: Bool { api != nil }

    /// Il file da cui si è caricata, per l'interfaccia e per le prove.
    public static var libraryPath: String? { api?.path }

    /// Vero se il font ha le tabelle Graphite (basta `Silf`, che le regola tutte).
    public static func hasTables(_ font: CTFont) -> Bool {
        CTFontCopyTable(font, CTFontTableTag(fourCC("Silf")), []) != nil
    }

    /// La scelta della composizione come si scrive negli stili e nel file: `off` per Core Text, `on` per Graphite senza
    /// funzioni, altrimenti le funzioni (`cv01=1 lldt=1`), che dicono anch'esse Graphite.
    public static func encodedChoice(_ graphite: String?) -> String {
        guard let graphite else { return "off" }
        return graphite.isEmpty ? "on" : graphite
    }

    /// La scelta letta da `encodedChoice`: `.some(nil)` per Core Text, `.some(funzioni)` per Graphite; `nil` se il testo
    /// non è valido.
    public static func choice(fromEncoded text: String) -> String?? {
        switch text {
        case "off": return .some(nil)
        case "on": return .some("")
        default:
            let tokens = text.split(separator: " ")
            guard !tokens.isEmpty, GraphiteLayout.settings(from: text).count == tokens.count else { return nil }
            return .some(text)
        }
    }

    static let api: API? = API.load(from: searchPaths)

    static func fourCC(_ tag: String) -> UInt32 {
        tag.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}

// MARK: Le funzioni della libreria

extension Graphite {
    typealias GetTable = @convention(c) (UnsafeRawPointer?, UInt32, UnsafeMutablePointer<Int>?) -> UnsafeRawPointer?
    typealias ReleaseTable = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void

    /// Le funzioni di `graphite2` che usiamo, prese con `dlsym`. I tipi della libreria sono puntatori opachi.
    final class API: @unchecked Sendable {
        let path: String
        let makeFaceWithOps: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UInt32) -> OpaquePointer?
        let faceDestroy: @convention(c) (OpaquePointer?) -> Void
        let makeFont: @convention(c) (Float, OpaquePointer?) -> OpaquePointer?
        let fontDestroy: @convention(c) (OpaquePointer?) -> Void
        let featureValForLang: @convention(c) (OpaquePointer?, UInt32) -> OpaquePointer?
        let featureValDestroy: @convention(c) (OpaquePointer?) -> Void
        let findFref: @convention(c) (OpaquePointer?, UInt32) -> OpaquePointer?
        let frefSetValue: @convention(c) (OpaquePointer?, UInt16, OpaquePointer?) -> Int32
        let frefValueOf: @convention(c) (OpaquePointer?, OpaquePointer?) -> UInt16
        let faceFrefCount: @convention(c) (OpaquePointer?) -> UInt16
        let faceFref: @convention(c) (OpaquePointer?, UInt16) -> OpaquePointer?
        let frefID: @convention(c) (OpaquePointer?) -> UInt32
        let frefValueCount: @convention(c) (OpaquePointer?) -> UInt16
        let frefValue: @convention(c) (OpaquePointer?, UInt16) -> Int16
        let frefLabel: @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt16>?, UInt32, UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer?
        let frefValueLabel: @convention(c) (OpaquePointer?, UInt16, UnsafeMutablePointer<UInt16>?, UInt32, UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer?
        let labelDestroy: @convention(c) (UnsafeMutableRawPointer?) -> Void
        let makeSeg: @convention(c) (OpaquePointer?, OpaquePointer?, UInt32, OpaquePointer?, UInt32, UnsafeRawPointer?, Int, Int32) -> OpaquePointer?
        let segDestroy: @convention(c) (OpaquePointer?) -> Void
        let segAdvanceX: @convention(c) (OpaquePointer?) -> Float
        let segCharInfo: @convention(c) (OpaquePointer?, UInt32) -> OpaquePointer?
        let charInfoBase: @convention(c) (OpaquePointer?) -> Int
        let segFirstSlot: @convention(c) (OpaquePointer?) -> OpaquePointer?
        let slotNext: @convention(c) (OpaquePointer?) -> OpaquePointer?
        let slotGlyph: @convention(c) (OpaquePointer?) -> UInt16
        let slotOriginX: @convention(c) (OpaquePointer?) -> Float
        let slotOriginY: @convention(c) (OpaquePointer?) -> Float
        let slotBefore: @convention(c) (OpaquePointer?) -> Int32
        let slotAfter: @convention(c) (OpaquePointer?) -> Int32
        let slotCanInsertBefore: @convention(c) (OpaquePointer?) -> Int32

        private init?(handle: UnsafeMutableRawPointer, path: String) {
            func symbol<T>(_ name: String, as type: T.Type) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: type) }
            }
            guard let makeFaceWithOps = symbol("gr_make_face_with_ops", as: (@convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UInt32) -> OpaquePointer?).self),
                  let faceDestroy = symbol("gr_face_destroy", as: (@convention(c) (OpaquePointer?) -> Void).self),
                  let makeFont = symbol("gr_make_font", as: (@convention(c) (Float, OpaquePointer?) -> OpaquePointer?).self),
                  let fontDestroy = symbol("gr_font_destroy", as: (@convention(c) (OpaquePointer?) -> Void).self),
                  let featureValForLang = symbol("gr_face_featureval_for_lang", as: (@convention(c) (OpaquePointer?, UInt32) -> OpaquePointer?).self),
                  let featureValDestroy = symbol("gr_featureval_destroy", as: (@convention(c) (OpaquePointer?) -> Void).self),
                  let findFref = symbol("gr_face_find_fref", as: (@convention(c) (OpaquePointer?, UInt32) -> OpaquePointer?).self),
                  let frefSetValue = symbol("gr_fref_set_feature_value", as: (@convention(c) (OpaquePointer?, UInt16, OpaquePointer?) -> Int32).self),
                  let frefValueOf = symbol("gr_fref_feature_value", as: (@convention(c) (OpaquePointer?, OpaquePointer?) -> UInt16).self),
                  let faceFrefCount = symbol("gr_face_n_fref", as: (@convention(c) (OpaquePointer?) -> UInt16).self),
                  let faceFref = symbol("gr_face_fref", as: (@convention(c) (OpaquePointer?, UInt16) -> OpaquePointer?).self),
                  let frefID = symbol("gr_fref_id", as: (@convention(c) (OpaquePointer?) -> UInt32).self),
                  let frefValueCount = symbol("gr_fref_n_values", as: (@convention(c) (OpaquePointer?) -> UInt16).self),
                  let frefValue = symbol("gr_fref_value", as: (@convention(c) (OpaquePointer?, UInt16) -> Int16).self),
                  let frefLabel = symbol("gr_fref_label", as: (@convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt16>?, UInt32, UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer?).self),
                  let frefValueLabel = symbol("gr_fref_value_label", as: (@convention(c) (OpaquePointer?, UInt16, UnsafeMutablePointer<UInt16>?, UInt32, UnsafeMutablePointer<UInt32>?) -> UnsafeMutableRawPointer?).self),
                  let labelDestroy = symbol("gr_label_destroy", as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self),
                  let makeSeg = symbol("gr_make_seg", as: (@convention(c) (OpaquePointer?, OpaquePointer?, UInt32, OpaquePointer?, UInt32, UnsafeRawPointer?, Int, Int32) -> OpaquePointer?).self),
                  let segDestroy = symbol("gr_seg_destroy", as: (@convention(c) (OpaquePointer?) -> Void).self),
                  let segAdvanceX = symbol("gr_seg_advance_X", as: (@convention(c) (OpaquePointer?) -> Float).self),
                  let segCharInfo = symbol("gr_seg_cinfo", as: (@convention(c) (OpaquePointer?, UInt32) -> OpaquePointer?).self),
                  let charInfoBase = symbol("gr_cinfo_base", as: (@convention(c) (OpaquePointer?) -> Int).self),
                  let segFirstSlot = symbol("gr_seg_first_slot", as: (@convention(c) (OpaquePointer?) -> OpaquePointer?).self),
                  let slotNext = symbol("gr_slot_next_in_segment", as: (@convention(c) (OpaquePointer?) -> OpaquePointer?).self),
                  let slotGlyph = symbol("gr_slot_gid", as: (@convention(c) (OpaquePointer?) -> UInt16).self),
                  let slotOriginX = symbol("gr_slot_origin_X", as: (@convention(c) (OpaquePointer?) -> Float).self),
                  let slotOriginY = symbol("gr_slot_origin_Y", as: (@convention(c) (OpaquePointer?) -> Float).self),
                  let slotBefore = symbol("gr_slot_before", as: (@convention(c) (OpaquePointer?) -> Int32).self),
                  let slotAfter = symbol("gr_slot_after", as: (@convention(c) (OpaquePointer?) -> Int32).self),
                  let slotCanInsertBefore = symbol("gr_slot_can_insert_before", as: (@convention(c) (OpaquePointer?) -> Int32).self)
            else { return nil }
            self.path = path
            self.makeFaceWithOps = makeFaceWithOps
            self.faceDestroy = faceDestroy
            self.makeFont = makeFont
            self.fontDestroy = fontDestroy
            self.featureValForLang = featureValForLang
            self.featureValDestroy = featureValDestroy
            self.findFref = findFref
            self.frefSetValue = frefSetValue
            self.frefValueOf = frefValueOf
            self.faceFrefCount = faceFrefCount
            self.faceFref = faceFref
            self.frefID = frefID
            self.frefValueCount = frefValueCount
            self.frefValue = frefValue
            self.frefLabel = frefLabel
            self.frefValueLabel = frefValueLabel
            self.labelDestroy = labelDestroy
            self.makeSeg = makeSeg
            self.segDestroy = segDestroy
            self.segAdvanceX = segAdvanceX
            self.segCharInfo = segCharInfo
            self.charInfoBase = charInfoBase
            self.segFirstSlot = segFirstSlot
            self.slotNext = slotNext
            self.slotGlyph = slotGlyph
            self.slotOriginX = slotOriginX
            self.slotOriginY = slotOriginY
            self.slotBefore = slotBefore
            self.slotAfter = slotAfter
            self.slotCanInsertBefore = slotCanInsertBefore
        }

        /// La prima libreria che si apre e ha tutte le funzioni; `nil` se nessuna.
        static func load(from paths: [String]) -> API? {
            for path in paths where FileManager.default.fileExists(atPath: path) {
                guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { continue }
                if let api = API(handle: handle, path: path) { return api }
                dlclose(handle)
            }
            return nil
        }
    }
}

// MARK: Il volto di un font

extension Graphite {
    /// Le tabelle di un font per `graphite2`, che le chiede una per una; restano vive quanto il volto.
    final class Face: @unchecked Sendable {
        let font: CTFont
        private var tables: [UInt32: CFData] = [:]
        private let lock = NSLock()
        fileprivate(set) var face: OpaquePointer?

        init(font: CTFont) {
            self.font = font
        }

        func table(_ tag: UInt32) -> CFData? {
            lock.lock()
            defer { lock.unlock() }
            if let table = tables[tag] { return table }
            let table = CTFontCopyTable(font, CTFontTableTag(tag), [])
            if let table { tables[tag] = table }
            return table
        }

        deinit {
            if let face { Graphite.api?.faceDestroy(face) }
        }
    }

    /// La funzione con cui `graphite2` chiede una tabella: il primo argomento è il nostro `Face`.
    private static let getTable: GetTable = { handle, tag, length in
        guard let handle else { return nil }
        let face = Unmanaged<Face>.fromOpaque(handle).takeUnretainedValue()
        guard let table = face.table(tag) else {
            length?.pointee = 0
            return nil
        }
        length?.pointee = CFDataGetLength(table)
        return UnsafeRawPointer(CFDataGetBytePtr(table))
    }

    /// La struttura `gr_face_ops`: la misura, la funzione delle tabelle, nessuna funzione di rilascio.
    private struct FaceOps {
        var size: Int
        var getTable: GetTable
        var releaseTable: ReleaseTable?
    }

    /// La chiave della cache dei volti: il nome PostScript e il file da cui il font è letto.
    static func faceKey(for font: CTFont) -> String {
        let file = (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.path ?? ""
        return (CTFontCopyPostScriptName(font) as String) + "\n" + file
    }

    private static let facesLock = NSLock()
    nonisolated(unsafe) private static var faces: [String: Face] = [:]

    /// Il volto Graphite del font: uno per file e nome PostScript, perché due file diversi (per esempio due versioni
    /// dello stesso font) possono avere lo stesso nome; `nil` se manca la libreria o il font non ha le tabelle.
    static func face(for font: CTFont) -> Face? {
        guard let api, hasTables(font) else { return nil }
        let name = faceKey(for: font)
        facesLock.lock()
        defer { facesLock.unlock() }
        if let face = faces[name] { return face }
        // Il volto non dipende dal corpo: lo si fa una volta per font.
        let face = Face(font: font)
        var ops = FaceOps(size: MemoryLayout<FaceOps>.size, getTable: getTable, releaseTable: nil)
        let made = withUnsafePointer(to: &ops) { pointer in
            api.makeFaceWithOps(Unmanaged.passUnretained(face).toOpaque(), UnsafeRawPointer(pointer), 0)
        }
        guard let made else { return nil }
        face.face = made
        faces[name] = face
        return face
    }
}

// MARK: Comporre un tratto

/// Una funzione Graphite con il suo valore. L'identificativo è quello del font: quattro lettere (come `smcp`) o un
/// numero.
public struct GraphiteSetting: Hashable, Sendable {
    public var id: UInt32
    public var value: UInt16

    public init(id: UInt32, value: UInt16) {
        self.id = id
        self.value = value
    }
}

/// Un tratto composto da Graphite: i glifi con le loro posizioni (in punti, dall'inizio del tratto, y verso l'alto) e i
/// gruppi (cluster): pezzi di testo e di glifi che non si possono separare (una consonante con i suoi segni).
public struct GraphiteRun: Equatable, Sendable {
    public struct Cluster: Equatable, Sendable {
        /// I caratteri, in unità UTF-16 dall'inizio del testo composto.
        public var characters: NSRange
        /// I glifi, come indici in `glyphs`.
        public var glyphs: NSRange
        /// La larghezza: dall'origine del suo primo glifo a quella del gruppo seguente (o alla fine del tratto).
        public var advance: CGFloat
    }

    public var glyphs: [CGGlyph]
    public var positions: [CGPoint]
    public var advance: CGFloat
    public var clusters: [Cluster]
}

extension Graphite {
    /// Compone un testo da sinistra a destra con le regole Graphite del font, al suo corpo. `nil` se manca la libreria,
    /// se il font non ha le tabelle o se `graphite2` rifiuta il testo.
    public static func shape(_ text: String, font: CTFont, settings: [GraphiteSetting] = [], language: String? = nil) -> GraphiteRun? {
        guard let api, let face = face(for: font), let grFace = face.face, !text.isEmpty else { return nil }
        // Si passano i caratteri interi (UTF-32), poi si riportano alle unità UTF-16 del testo.
        let scalars = Array(text.unicodeScalars)
        var utf16Offsets: [Int] = []
        utf16Offsets.reserveCapacity(scalars.count + 1)
        var offset = 0
        for scalar in scalars {
            utf16Offsets.append(offset)
            offset += scalar.utf16.count
        }
        utf16Offsets.append(offset)
        let codes = scalars.map(\.value)

        guard let grFont = api.makeFont(Float(CTFontGetSize(font)), grFace) else { return nil }
        defer { api.fontDestroy(grFont) }
        let features = api.featureValForLang(grFace, language.map(languageTag) ?? 0)
        defer { api.featureValDestroy(features) }
        for setting in settings {
            if let fref = api.findFref(grFace, setting.id) { _ = api.frefSetValue(fref, setting.value, features) }
        }
        let segment = codes.withUnsafeBufferPointer { buffer in
            api.makeSeg(grFont, grFace, 0, features, 4, UnsafeRawPointer(buffer.baseAddress), codes.count, 0)
        }
        guard let segment else { return nil }
        defer { api.segDestroy(segment) }

        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
        // I gruppi, in caratteri interi, come li ricava HarfBuzz dalle informazioni di graphite2: ogni glifo dice il
        // primo e l'ultimo carattere a cui appartiene; i gruppi si fondono finché nessun glifo li attraversa.
        struct Group { var baseChar: Int; var charCount: Int; var baseGlyph: Int; var glyphCount: Int }
        var groups = [Group(baseChar: 0, charCount: 0, baseGlyph: 0, glyphCount: 0)]
        var slot = api.segFirstSlot(segment)
        var index = 0
        while let current = slot {
            glyphs.append(CGGlyph(api.slotGlyph(current)))
            positions.append(CGPoint(x: CGFloat(api.slotOriginX(current)), y: CGFloat(api.slotOriginY(current))))
            let before = Int(api.slotBefore(current)), after = Int(api.slotAfter(current))
            let beforeChar = api.charInfoBase(api.segCharInfo(segment, UInt32(max(before, 0))))
            let afterChar = api.charInfoBase(api.segCharInfo(segment, UInt32(max(after, 0))))
            while groups.count > 1, groups[groups.count - 1].baseChar > beforeChar {
                let last = groups.removeLast()
                groups[groups.count - 1].charCount += last.charCount
                groups[groups.count - 1].glyphCount += last.glyphCount
            }
            let last = groups[groups.count - 1]
            if api.slotCanInsertBefore(current) != 0, last.charCount > 0, beforeChar >= last.baseChar + last.charCount {
                let base = last.baseChar + last.charCount
                groups.append(Group(baseChar: base, charCount: beforeChar - base, baseGlyph: index, glyphCount: 0))
            }
            groups[groups.count - 1].glyphCount += 1
            if groups[groups.count - 1].baseChar + groups[groups.count - 1].charCount < afterChar + 1 {
                groups[groups.count - 1].charCount = afterChar + 1 - groups[groups.count - 1].baseChar
            }
            slot = api.slotNext(current)
            index += 1
        }
        // L'ultimo gruppo arriva fino in fondo al testo (caratteri senza glifo, come uno spazio di larghezza nulla).
        let covered = groups[groups.count - 1].baseChar + groups[groups.count - 1].charCount
        if covered < codes.count { groups[groups.count - 1].charCount += codes.count - covered }

        let advance = CGFloat(api.segAdvanceX(segment))
        var clusters: [GraphiteRun.Cluster] = []
        for (position, group) in groups.enumerated() where group.charCount > 0 || group.glyphCount > 0 {
            let start = utf16Offsets[min(group.baseChar, codes.count)]
            let end = utf16Offsets[min(group.baseChar + group.charCount, codes.count)]
            let originX = group.baseGlyph < positions.count ? positions[group.baseGlyph].x : advance
            let next = position + 1 < groups.count && groups[position + 1].baseGlyph < positions.count ? positions[groups[position + 1].baseGlyph].x : advance
            clusters.append(GraphiteRun.Cluster(characters: NSRange(location: start, length: end - start),
                                                glyphs: NSRange(location: group.baseGlyph, length: group.glyphCount),
                                                advance: next - originX))
        }
        return GraphiteRun(glyphs: glyphs, positions: positions, advance: advance, clusters: graphemeAligned(clusters, in: text as NSString))
    }

    /// I gruppi riuniti perché nessuno cominci in mezzo a un grafemo e nessuno abbia larghezza negativa. Graphite fa
    /// un gruppo a sé, per esempio, del segno vocalico «े» sopra la consonante (larghezza −0,4 punti): per Core Text uno
    /// spazio negativo dimezzava il gruppo seguente, e cursore, selezione e caratteri nascosti finivano fuori posto.
    static func graphemeAligned(_ clusters: [GraphiteRun.Cluster], in text: NSString) -> [GraphiteRun.Cluster] {
        var result: [GraphiteRun.Cluster] = []
        for cluster in clusters {
            let location = cluster.characters.location
            let startsGrapheme = location >= text.length || text.rangeOfComposedCharacterSequence(at: location).location == location
            if var last = result.last, !startsGrapheme || cluster.advance < 0 {
                last.characters = NSUnionRange(last.characters, cluster.characters)
                last.glyphs = NSUnionRange(last.glyphs, cluster.glyphs)
                last.advance += cluster.advance
                result[result.count - 1] = last
            } else {
                result.append(cluster)
            }
        }
        return result
    }

    /// La lingua come la vuole Graphite: fino a quattro lettere ASCII in un intero (`"my"` diventa `0x6D790000`).
    static func languageTag(_ language: String) -> UInt32 {
        let letters = Array(language.prefix { $0 != "-" && $0 != "_" }.utf8.prefix(4))
        return letters.enumerated().reduce(0) { $0 | UInt32($1.element) << (24 - 8 * UInt32($1.offset)) }
    }
}

// MARK: Le funzioni Graphite di un font

/// Una funzione Graphite di un font, per il pannello delle funzioni.
public struct GraphiteFeature: Equatable, Sendable {
    public struct Value: Equatable, Sendable {
        public var value: UInt16
        public var name: String
    }

    public var id: UInt32
    public var name: String
    public var values: [Value]
    public var defaultValue: UInt16

    /// L'identificativo da leggere: quattro lettere se lo sono (`smcp`), altrimenti il numero.
    public var tag: String {
        let bytes = (0..<4).map { UInt8((id >> (24 - 8 * UInt32($0))) & 0xFF) }
        if bytes.allSatisfy({ (0x20...0x7E).contains($0) }), let text = String(bytes: bytes, encoding: .ascii) {
            return text.trimmingCharacters(in: .whitespaces)
        }
        return String(id)
    }
}

extension Graphite {
    /// Le funzioni Graphite del font, con i nomi nella lingua chiesta se il font li ha (altrimenti in inglese).
    public static func features(of font: CTFont, language: UInt16 = 0x0410) -> [GraphiteFeature] {
        guard let api, let face = face(for: font), let grFace = face.face else { return [] }
        let defaults = api.featureValForLang(grFace, 0)
        defer { api.featureValDestroy(defaults) }
        func label(_ make: (UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> UnsafeMutableRawPointer?) -> String {
            for wanted in [language, 0x0409] {
                var lang = wanted
                var length: UInt32 = 0
                guard let pointer = make(&lang, &length) else { continue }
                defer { api.labelDestroy(pointer) }
                let text = String(bytes: UnsafeRawBufferPointer(start: pointer, count: Int(length)), encoding: .utf8) ?? ""
                if !text.isEmpty { return text }
            }
            return ""
        }
        return (0..<api.faceFrefCount(grFace)).compactMap { index in
            guard let fref = api.faceFref(grFace, index) else { return nil }
            let id = api.frefID(fref)
            // La funzione della lingua (1) non è una scelta di stile.
            guard id != 1 else { return nil }
            let values = (0..<api.frefValueCount(fref)).map { setting in
                GraphiteFeature.Value(value: UInt16(bitPattern: api.frefValue(fref, setting)),
                                      name: label { api.frefValueLabel(fref, setting, $0, 1, $1) })
            }
            return GraphiteFeature(id: id, name: label { api.frefLabel(fref, $0, 1, $1) }, values: values,
                                   defaultValue: api.frefValueOf(fref, defaults))
        }
    }
}
