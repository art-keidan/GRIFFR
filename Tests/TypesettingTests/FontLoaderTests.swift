import Foundation
import Testing
@testable import Typesetting

extension TypesettingSuite {
    @Suite("Sorgenti dei font")
    struct FontLoaderTests {
        private func temporaryDirectory() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("FontLoaderTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @Test("La cartella Adobe include file nascosti e senza estensione, ma non sottocartelle")
        func discoversAdobeFontFiles() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            for name in ["17382", ".nascosto", "font.otf"] {
                try Data([0]).write(to: directory.appendingPathComponent(name))
            }
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("annidata"), withIntermediateDirectories: false)

            #expect(FontLoader.fontFiles(in: directory).map(\.lastPathComponent) == [".nascosto", "17382", "font.otf"])
        }

        @Test("Una cartella assente è una sorgente vuota, non un errore")
        func missingDirectory() {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FontLoaderTests-inesistente-\(UUID().uuidString)", isDirectory: true)
            #expect(FontLoader.fontFiles(in: directory).isEmpty)
            #expect(FontLoader.registerFonts(in: directory) == 0)
        }

        @Test("I file accessori che non contengono font vengono ignorati")
        func ignoresNonFonts() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data("non è un font".utf8).write(to: directory.appendingPathComponent("17382"))
            #expect(FontLoader.registerFonts(in: directory) == 0)
        }
    }
}
