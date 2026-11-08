// Ritaglia le foto intere della guida (docs/guide/images/full, fatte da GuideScreenshotTests) nelle immagini della pagina.
// Le misure sono in punti della finestra (1180 × 900); le foto sono a densità doppia.
//
//     swift Scripts/guide-crops.swift docs/guide/images/full docs/guide/images

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else { print("uso: guide-crops.swift <foto intere> <cartella delle immagini>"); exit(1) }
let source = URL(fileURLWithPath: arguments[1]), destination = URL(fileURLWithPath: arguments[2])

/// Nome dell'immagine, foto da cui viene, rettangolo in punti dall'alto a sinistra (nil: tutta la foto).
let crops: [(name: String, from: String, rect: CGRect?)] = [
    ("simple-window", "simple", nil),
    ("simple-bands", "simple", CGRect(x: 0, y: 0, width: 700, height: 112)),
    ("detailed-window", "detailed", nil),
    ("detailed-bands", "detailed", CGRect(x: 0, y: 0, width: 1180, height: 146)),
    ("ruler", "detailed", CGRect(x: 200, y: 148, width: 600, height: 28)),
    ("object-tree", "detailed", CGRect(x: 0, y: 176, width: 232, height: 440)),
    ("side-panel", "detailed", CGRect(x: 818, y: 176, width: 362, height: 120)),
    ("status-bar", "detailed", CGRect(x: 0, y: 872, width: 1180, height: 28)),
    ("design-paragraph", "design", CGRect(x: 0, y: 176, width: 1180, height: 480)),
    ("style-composer", "composer", nil),
]

for crop in crops {
    guard let image = NSImage(contentsOf: source.appendingPathComponent(crop.from + ".png")),
          let full = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("manca \(crop.from).png"); continue }
    let scale = CGFloat(full.width) / image.size.width
    let piece = crop.rect.flatMap { full.cropping(to: CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale)) } ?? full
    let rep = NSBitmapImageRep(cgImage: piece)
    rep.size = NSSize(width: CGFloat(piece.width) / scale, height: CGFloat(piece.height) / scale)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: destination.appendingPathComponent(crop.name + ".png"))
    print("\(crop.name).png  \(piece.width)×\(piece.height)  \(data.count / 1024) KB")
}
