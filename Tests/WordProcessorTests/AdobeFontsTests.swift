import AppKit
import CoreText
import Testing
@testable import Typesetting
@testable import WordProcessor

@Suite("Font Adobe nell'interfaccia", .serialized) @MainActor
struct AdobeFontsTests {
    nonisolated private static func adobeFamilies() -> Set<String> {
        let files = FontLoader.fontFiles(in: FontLoader.adobeFontsDirectory)
        return Set(files.flatMap { url -> [String] in
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
            else { return [] }
            return descriptors.compactMap {
                CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
            }
        })
    }

    nonisolated private static var hasAdobeFonts: Bool { !adobeFamilies().isEmpty }

    @Test("Tutte le famiglie Adobe compaiono nel popup, riunendo i corpi ottici", .enabled(if: hasAdobeFonts))
    func adobeFamiliesAppearInEditorPopup() throws {
        let expected = Set(Self.adobeFamilies().map { OpticalFonts.canonicalFamily($0) ?? $0 })
        FontLoader.registerAdobeFonts()
        let h = EditorHarness()
        defer { h.close() }
        let popup = try #require(h.editor.bandControls["famiglia"] as? NSPopUpButton)
        let missing = expected.subtracting(popup.itemTitles)
        #expect(missing.isEmpty, "famiglie assenti dal popup: \(missing.sorted().joined(separator: ", "))")
    }
}
