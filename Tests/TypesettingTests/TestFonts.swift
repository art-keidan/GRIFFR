import CoreText
import Foundation
import Typesetting

/// I due font di prova. Vengono solo letti dalle loro posizioni originali.
enum TestFonts {
    static let hoeflerURL = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Hoefler Text.ttc")
    static let vulcaniusURL = URL(fileURLWithPath: "/Users/artemio/Library/Fonts/Gotico/Vulcanius.ttf")

    static func hoefler(size: CGFloat = 24) throws -> CTFont { try FontLoader.font(at: hoeflerURL, face: 0, size: size) }
    static func vulcanius(size: CGFloat = 24) throws -> CTFont { try FontLoader.font(at: vulcaniusURL, size: size) }

    /// 𐌹𐍃 𐌲𐍂
    static let gothicSample = "\u{10339}\u{10343} \u{10332}\u{10342}"
    static let latinSample = "ct st ffi 1234"
}
