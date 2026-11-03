import CoreGraphics
import CoreText
import Foundation

/// Disegna le pagine composte in un PDF con Core Graphics. I font vengono incorporati da Core Graphics come sottoinsiemi.
public enum PDFRenderer {
    public static func pdfData(for layout: DocumentLayout, title: String? = nil) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: layout.setup.paperSize)
        var info: [CFString: Any] = [kCGPDFContextCreator: "GRIFFR"]
        if let title { info[kCGPDFContextTitle] = title }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return Data() }
        for (index, page) in layout.pages.enumerated() {
            // L'ultima pagina, se contiene solo la riga vuota del cursore, non va stampata.
            if index > 0, index == layout.pages.count - 1, isOnlyCaretLine(page) { continue }
            // Ogni pagina con il suo formato: le sezioni possono avere tipi di pagina diversi.
            var box = CGRect(origin: .zero, size: page.setup.paperSize)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            draw(page, in: context, tagged: true, text: layout.text.string as NSString)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Vero per una pagina con la sola riga vuota del cursore: nessun carattere, nessuna figura, segno o filetto.
    static func isOnlyCaretLine(_ page: LaidOutPage) -> Bool {
        page.lines.allSatisfy { $0.range.length == 0 } && page.images.isEmpty && page.markers.isEmpty && page.rules.isEmpty && page.fills.isEmpty
    }

    /// Disegna una pagina. Il contesto deve avere l'origine in basso a sinistra.
    ///
    /// Con `tagged` ogni paragrafo è racchiuso in un tag `P`. Serve a rendere il testo ricercabile: quando il
    /// contesto PDF è marcato, Core Text aggiunge da sé un `ActualText` ai glifi che non corrispondono a un
    /// carattere della `cmap` (alternative, legature), che altrimenti verrebbero estratti come caratteri sbagliati.
    /// Le righe vanno disegnate intere con `CTLineDraw`: disegnando porzioni di un tratto con `CTRunDraw`
    /// il testo associato ai glifi risulta sfasato.
    public static func draw(_ page: LaidOutPage, in context: CGContext, tagged: Bool = false, text: NSString? = nil) {
        context.textMatrix = .identity
        for fill in page.fills {
            context.setFillColor(fill.color)
            context.fill(fill.rect)
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for rule in page.rules { context.fill(rule) }
        for figure in page.images { InlineImages.draw(figure.image, in: figure.rect, context: context) }
        var currentParagraph: Int?
        for placed in page.lines {
            if currentParagraph != placed.paragraphLocation {
                if tagged {
                    if currentParagraph != nil { CGPDFContextEndTag(context) }
                    CGPDFContextBeginTag(context, .paragraph, [:] as CFDictionary)
                }
                currentParagraph = placed.paragraphLocation
                // Il segno di elenco precede il testo della voce, dentro lo stesso paragrafo.
                for marker in page.markers where marker.paragraphLocation == placed.paragraphLocation {
                    context.textPosition = marker.origin
                    CTLineDraw(marker.line, context)
                }
            }
            context.textPosition = placed.origin
            if tagged, GraphiteLayout.needsPDFText(placed, text: text) {
                // Nel PDF le righe con testo Graphite o in una scrittura che riordina i segni le scrive `GraphiteLayout`,
                // perché il testo si estragga nell'ordine in cui si legge.
                GraphiteLayout.drawLineForPDF(placed, text: text, in: context)
            } else {
                CTLineDraw(placed.line, context)
                GraphiteLayout.draw(line: placed.line, at: placed.origin, in: context)
            }
            InlineImages.drawImages(of: placed.line, at: placed.origin, in: context)
            LineDecorations.draw(line: placed.line, at: placed.origin, in: context)
        }
        if tagged, currentParagraph != nil { CGPDFContextEndTag(context) }
    }
}
