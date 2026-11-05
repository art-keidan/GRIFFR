import CoreText
import Foundation

public enum FontLoadingError: Error, CustomStringConvertible {
    case unreadable(URL)
    case noSuchFace(URL, Int)

    public var description: String {
        switch self {
        case .unreadable(let url): "No readable font in \(url.path)"
        case .noSuchFace(let url, let face): "\(url.path) does not contain the face \(face)"
        }
    }
}

public enum FontLoader {
    /// I font sincronizzati da Creative Cloud hanno spesso nomi numerici e nessuna estensione.
    public static var adobeFontsDirectory: URL {
        URL(fileURLWithPath: ("~/Library/Application Support/Adobe/CoreSync/plugins/livetype/.r" as NSString).expandingTildeInPath,
            isDirectory: true)
    }

    /// Rende disponibili i font Adobe soltanto a questo processo, senza installarli né modificarli.
    @discardableResult
    public static func registerAdobeFonts() -> Int {
        registerFonts(in: adobeFontsDirectory)
    }

    @discardableResult
    static func registerFonts(in directory: URL) -> Int {
        var registered = 0
        for url in fontFiles(in: directory) {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  !descriptors.isEmpty else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { registered += 1 }
        }
        OpticalFonts.refresh()
        return registered
    }

    /// Non filtra per estensione: Creative Cloud usa anche file nascosti con nomi numerici.
    static func fontFiles(in directory: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []
        ) else { return [] }
        return urls.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Carica una faccia da un file. Il file viene solo letto: non è registrato nel sistema né modificato.
    public static func font(at url: URL, face: Int = 0, size: CGFloat) throws -> CTFont {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              !descriptors.isEmpty else { throw FontLoadingError.unreadable(url) }
        guard descriptors.indices.contains(face) else { throw FontLoadingError.noSuchFace(url, face) }
        return CTFontCreateWithFontDescriptor(descriptors[face], size, nil)
    }

    /// Cerca un font installato per nome PostScript. Restituisce `nil` se Core Text ne sostituirebbe un altro.
    public static func font(postScriptName: String, size: CGFloat) -> CTFont? {
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName ? font : nil
    }
}

extension CTFont {
    public var postScriptName: String { CTFontCopyPostScriptName(self) as String }
    public var displayName: String { CTFontCopyDisplayName(self) as String }
    public var pointSize: CGFloat { CTFontGetSize(self) }

    /// Tag delle tabelle sfnt presenti nel font, per esempio "morx", "GSUB", "feat".
    public var tableTags: Set<String> {
        // L'array contiene i tag come interi camuffati da puntatori, non oggetti.
        guard let array = CTFontCopyAvailableTables(self, []) else { return [] }
        var tags: Set<String> = []
        for index in 0..<CFArrayGetCount(array) {
            let tag = UInt32(UInt(bitPattern: CFArrayGetValueAtIndex(array, index)))
            let bytes = [UInt8(tag >> 24 & 0xff), UInt8(tag >> 16 & 0xff), UInt8(tag >> 8 & 0xff), UInt8(tag & 0xff)]
            tags.insert(String(bytes: bytes, encoding: .isoLatin1) ?? "????")
        }
        return tags
    }

    func tableBytes(_ tag: String) -> [UInt8] {
        let code = tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return CTFontCopyTable(self, CTFontTableTag(code), []).map { [UInt8]($0 as Data) } ?? []
    }
}
