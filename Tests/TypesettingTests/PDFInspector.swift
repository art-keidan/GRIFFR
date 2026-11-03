import CoreGraphics
import Foundation

/// Lettura del contenuto di un PDF con Core Graphics, per verificare ciò che abbiamo scritto senza strumenti esterni.
enum PDFInspector {
    struct Unreadable: Error {}

    private final class Collector { var texts: [String] = [] }

    /// I valori di `ActualText` dei contenuti marcati della prima pagina, nell'ordine in cui compaiono.
    static func actualTexts(inFirstPageOf data: Data) throws -> [String] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1), let table = CGPDFOperatorTableCreate() else { throw Unreadable() }
        CGPDFOperatorTableSetCallback(table, "BDC") { scanner, info in
            var properties: CGPDFDictionaryRef?
            var text: CGPDFStringRef?
            guard CGPDFScannerPopDictionary(scanner, &properties), let properties,
                  CGPDFDictionaryGetString(properties, "ActualText", &text), let text,
                  let string = CGPDFStringCopyTextString(text), let info else { return }
            Unmanaged<Collector>.fromOpaque(info).takeUnretainedValue().texts.append(string as String)
        }
        let collector = Collector()
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(collector).toOpaque())
        guard CGPDFScannerScan(scanner) else { throw Unreadable() }
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        return collector.texts
    }
}
