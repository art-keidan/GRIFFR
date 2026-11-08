import Foundation

/// Come si stava guardando un documento quando lo si è chiuso: zoom, cursore, scorrimento, finestra. Si conserva in un
/// attributo esteso del file, non nel file: chiudere un documento non lo modifica, e lo stato segue il file anche se lo si
/// sposta o rinomina. Vale su questo Mac; un documento mai salvato non ha un file e non conserva nulla.
struct DocumentViewState: Codable, Equatable {
    /// L'ingrandimento; `nil` per quello automatico.
    var zoom: Double?
    /// La selezione: dove comincia e dove finisce (uguali per il solo cursore).
    var anchor: Int
    var head: Int
    /// L'origine della parte visibile delle pagine, in punti dello schermo.
    var scroll: [Double]
    /// La cornice della finestra: x, y, larghezza, altezza.
    var frame: [Double]

    static let attributeName = "local.griffr.viewstate"

    /// Lo stato conservato nel file, se c'è e si legge.
    static func read(from url: URL) -> DocumentViewState? {
        let path = url.path
        let size = getxattr(path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, attributeName, $0.baseAddress, size, 0, 0) }
        guard read == size else { return nil }
        return try? JSONDecoder().decode(DocumentViewState.self, from: data)
    }

    /// Scrive lo stato nel file; un errore (file sparito, volume in sola lettura) non ferma la chiusura.
    func write(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        _ = data.withUnsafeBytes { setxattr(url.path, Self.attributeName, $0.baseAddress, data.count, 0, 0) }
    }
}
