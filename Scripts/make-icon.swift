// Rifà le icone da Branding_GRIFFR/icona_trasparente.png:
// - Resources/GRIFFR.icns, l'icona dell'app, con il margine della griglia delle icone del Mac (il riquadro occupa
//   824 punti su 1024, centrato, come le altre icone nel Dock);
// - Resources/GRIFFR-documento.icns, l'icona dei documenti: un foglio con l'angolo piegato e l'icona dell'app al centro.
// Uso: swift Scripts/make-icon.swift  (dalla radice del progetto)
import AppKit

let source = "Branding_GRIFFR/icona_trasparente.png"
let gridFraction = 824.0 / 1024.0

guard let data = FileManager.default.contents(atPath: source),
      let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("Non riesco a leggere \(source)")
}

func context(_ side: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

/// Il rettangolo dei pixel non trasparenti, in coordinate dell'immagine con l'origine in basso.
func opaqueBounds(_ image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    let ctx = context(max(w, h))
    ctx.draw(image, in: CGRect(x: 0, y: max(w, h) - h, width: w, height: h))
    let side = max(w, h)
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for row in 0..<h {
        for x in 0..<w where p[(row * side + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, row); maxY = max(maxY, row)
        }
    }
    // Le righe del contesto partono dall'alto: si capovolge per avere l'origine in basso.
    return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = opaqueBounds(image)

/// Disegna il riquadro visibile dell'icona, centrato, con il lato maggiore lungo `size`.
func drawIcon(in ctx: CGContext, center: CGPoint, size: Double) {
    let k = size / max(bounds.width, bounds.height)
    ctx.draw(image, in: CGRect(x: center.x - bounds.midX * k, y: center.y - bounds.midY * k,
                               width: Double(image.width) * k, height: Double(image.height) * k))
}

func appIcon(_ side: Int) -> CGImage {
    let ctx = context(side)
    let s = Double(side)
    drawIcon(in: ctx, center: CGPoint(x: s / 2, y: s / 2), size: s * gridFraction)
    return ctx.makeImage()!
}

func documentIcon(_ side: Int) -> CGImage {
    let ctx = context(side)
    let u = Double(side) / 1024
    // Il foglio, nelle proporzioni dei documenti del Mac, con l'angolo in alto a destra piegato.
    let page = CGRect(x: 182 * u, y: 70 * u, width: 660 * u, height: 860 * u)
    let fold = 190 * u
    let outline = CGMutablePath()
    outline.move(to: CGPoint(x: page.minX, y: page.minY))
    outline.addLine(to: CGPoint(x: page.minX, y: page.maxY))
    outline.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    outline.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    outline.addLine(to: CGPoint(x: page.maxX, y: page.minY))
    outline.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * u), blur: 20 * u, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(outline)
    ctx.setFillColor(CGColor(red: 1, green: 0.995, blue: 0.985, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(outline)
    ctx.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
    ctx.setLineWidth(max(1, 4 * u))
    ctx.setLineJoin(.round)
    ctx.strokePath()
    // La piega.
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    flap.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
    flap.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    flap.closeSubpath()
    ctx.addPath(flap)
    ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
    ctx.fillPath()
    ctx.addPath(flap)
    ctx.strokePath()
    drawIcon(in: ctx, center: CGPoint(x: page.midX, y: page.minY + page.height * 0.44), size: 470 * u)
    return ctx.makeImage()!
}

func writeIcns(_ output: String, _ render: (Int) -> CGImage) throws {
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GRIFFR-\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            let rep = NSBitmapImageRep(cgImage: render(points * scale))
            try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }
    try FileManager.default.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    guard iconutil.terminationStatus == 0 else { fatalError("iconutil non è riuscito per \(output)") }
    print("Creata \(output)")
}

try writeIcns("Resources/GRIFFR.icns", appIcon)
try writeIcns("Resources/GRIFFR-documento.icns", documentIcon)
