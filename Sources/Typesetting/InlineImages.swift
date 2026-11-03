import AppKit
import CoreText

/// Le immagini nella riga: lo spazio che occupano per Core Text e il loro disegno, a schermo e nel PDF.
enum InlineImages {
    /// Le misure che Core Text chiede al carattere di un'immagine: larga quanto l'immagine, alta quanto lei sopra la
    /// linea di base, niente sotto.
    private final class Metrics {
        let width: CGFloat
        let ascent: CGFloat
        init(width: CGFloat, ascent: CGFloat) {
            self.width = width
            self.ascent = ascent
        }
    }

    private static let lock = NSLock()
    /// Un delegato per misura, sempre lo stesso: così il testo di un paragrafo con un'immagine resta uguale da una
    /// composizione all'altra, e la memoria delle righe lo ritrova. Il delegato porta solo le misure: tenerlo per
    /// immagine tratterrebbe i suoi byte per tutta la vita del programma.
    private struct Size: Hashable {
        let width: Double
        let height: Double
    }
    nonisolated(unsafe) private static var delegates: [Size: CTRunDelegate] = [:]

    static func runDelegate(for image: ImageObject) -> CTRunDelegate {
        lock.lock()
        defer { lock.unlock() }
        let size = Size(width: image.width, height: image.height)
        if let delegate = delegates[size] { return delegate }
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).release() },
            getAscent: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().ascent },
            getDescent: { _ in 0 },
            getWidth: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().width })
        let metrics = Unmanaged.passRetained(Metrics(width: CGFloat(image.width), ascent: CGFloat(image.height))).toOpaque()
        let delegate = CTRunDelegateCreate(&callbacks, metrics)!
        delegates[size] = delegate
        return delegate
    }

    /// Gli attributi che fanno del carattere di un'immagine uno spazio delle sue misure, senza disegnare nulla al suo posto.
    static func layoutAttributes(for image: ImageObject) -> [NSAttributedString.Key: Any] {
        [NSAttributedString.Key(kCTRunDelegateAttributeName as String): runDelegate(for: image),
         NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor.clear]
    }

    /// Ciò che si disegna: un'immagine a punti, o la prima pagina di un PDF (che resta vettoriale).
    enum Drawable {
        case bitmap(CGImage)
        case pdf(CGPDFPage)
    }

    /// La chiave della memoria delle immagini decodificate: il contenuto, non le misure a cui lo si mostra (cambiarle
    /// non decodifica di nuovo). Per un file collegato, il percorso con la data di modifica e la lunghezza: quando il
    /// file cambia, cambia la chiave e l'immagine si rilegge.
    final class ContentKey: NSObject {
        let embedded: Data?
        let path: String?
        let modified: Date?
        let length: Int

        init(embedded: Data) {
            self.embedded = embedded
            path = nil
            modified = nil
            length = embedded.count
        }

        init(path: String, modified: Date?, length: Int) {
            embedded = nil
            self.path = path
            self.modified = modified
            self.length = length
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(path)
            hasher.combine(modified)
            hasher.combine(length)
            if let embedded { hasher.combine(embedded.prefix(256)) }
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ContentKey else { return false }
            return path == other.path && modified == other.modified && length == other.length && embedded == other.embedded
        }
    }

    private final class Decoded {
        let drawable: Drawable
        init(_ drawable: Drawable) { self.drawable = drawable }
    }

    /// Le immagini decodificate, fino a circa 256 MB (quattro byte per punto dell'immagine): oltre, il sistema toglie
    /// le meno usate, che si rileggeranno se servono. Così la memoria non cresce aprendo e chiudendo documenti.
    nonisolated(unsafe) private static let decoded: NSCache<ContentKey, Decoded> = {
        let cache = NSCache<ContentKey, Decoded>()
        cache.totalCostLimit = 256 << 20
        return cache
    }()

    /// La chiave del contenuto attuale dell'immagine; `nil` per un file collegato che non c'è più.
    static func contentKey(for image: ImageObject) -> ContentKey? {
        switch image.source {
        case .embedded(let data):
            return ContentKey(embedded: data)
        case .linked(let path):
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
            return ContentKey(path: path, modified: attributes[.modificationDate] as? Date, length: (attributes[.size] as? Int) ?? 0)
        }
    }

    static func drawable(for image: ImageObject) -> Drawable? {
        guard let key = contentKey(for: image) else { return nil }
        if let found = decoded.object(forKey: key) { return found.drawable }
        guard let data = image.data else { return nil }
        let result: Drawable
        let cost: Int
        if data.starts(with: Array("%PDF".utf8)), let provider = CGDataProvider(data: data as CFData),
           let document = CGPDFDocument(provider), let page = document.page(at: 1) {
            result = .pdf(page)
            cost = data.count
        } else if let source = CGImageSourceCreateWithData(data as CFData, nil), let bitmap = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            result = .bitmap(bitmap)
            cost = bitmap.width * bitmap.height * 4
        } else {
            return nil
        }
        decoded.setObject(Decoded(result), forKey: key, cost: cost)
        return result
    }

    /// Disegna le immagini di una riga già collocata, dove Core Text ha lasciato il loro spazio.
    static func drawImages(of line: CTLine, at origin: CGPoint, in context: CGContext) {
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let attachment = attributes[NSAttributedString.Key.inlineImage] as? ImageAttachment else { continue }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            let image = attachment.image
            let rect = CGRect(x: origin.x + position.x, y: origin.y, width: CGFloat(image.width), height: CGFloat(image.height))
            draw(image, in: rect, context: context)
        }
    }

    static func draw(_ image: ImageObject, in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        switch drawable(for: image) {
        case .bitmap(let bitmap)?:
            context.interpolationQuality = .high
            context.draw(bitmap, in: rect)
        case .pdf(let page)?:
            let box = page.getBoxRect(.cropBox)
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / max(box.width, 1), y: rect.height / max(box.height, 1))
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
        case nil:
            // Un'immagine collegata che non si trova più: un riquadro grigio con una croce.
            context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
            context.setLineWidth(0.5)
            context.stroke(rect)
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.strokePath()
        }
    }
}
