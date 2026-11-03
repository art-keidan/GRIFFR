// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WordProcessor",
    platforms: [.macOS(.v14)],
    targets: [
        // Motore: font, funzioni tipografiche, composizione e PDF. Nessuna interfaccia.
        // Le risorse sono i modelli di sillabazione di TeX per le lingue che il sistema non sillaba.
        .target(name: "Typesetting", resources: [.copy("Resources/Hyphenation")]),
        .executableTarget(name: "WordProcessor", dependencies: ["Typesetting"]),
        .testTarget(name: "TypesettingTests", dependencies: ["Typesetting"]),
        // L'editor guidato dalle prove: tasti, comandi e annullamento come li riceve la finestra.
        .testTarget(name: "WordProcessorTests", dependencies: ["WordProcessor", "Typesetting"]),
    ]
)
