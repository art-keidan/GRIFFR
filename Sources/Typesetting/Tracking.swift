import CoreText
import Foundation

/// Lettura della tabella AAT `trak`: spaziatura tra i glifi che dipende dal corpo.
///
/// Core Text non la applica ai font ordinari (misurato su Hoefler Text, Skia, Apple Chancery: la larghezza
/// normalizzata non cambia con il corpo), quindi lo facciamo noi. La applica invece da sé ai font di sistema
/// nascosti, quelli il cui nome PostScript comincia con un punto: per quelli non aggiungiamo nulla.
public enum Tracking {
    struct Table: Equatable {
        /// Corpi, in ordine crescente, a cui la tabella dà un valore.
        var sizes: [Double]
        /// Per ogni traccia (−1 stretta, 0 normale, 1 larga…) i valori in unità del font, uno per corpo.
        var tracks: [(track: Double, values: [Int])]

        static func == (lhs: Table, rhs: Table) -> Bool {
            lhs.sizes == rhs.sizes && lhs.tracks.map(\.track) == rhs.tracks.map(\.track) && lhs.tracks.map(\.values) == rhs.tracks.map(\.values)
        }
    }

    /// Spaziatura della traccia normale al corpo del font, in punti, da aggiungere dopo ogni glifo.
    /// `nil` se il font non ha `trak`, se è un font di sistema nascosto, o se il valore è zero.
    public static func normalTracking(for font: CTFont) -> CGFloat? {
        guard !font.postScriptName.hasPrefix("."), let table = parse(font.tableBytes("trak")),
              let units = table.normalValue(atSize: Double(font.pointSize)), units != 0 else { return nil }
        return CGFloat(units) / CGFloat(CTFontGetUnitsPerEm(font)) * font.pointSize
    }

    /// Dati di tracciamento orizzontale della tabella.
    static func parse(_ bytes: [UInt8]) -> Table? {
        func u16(_ offset: Int) -> Int? { offset + 2 <= bytes.count ? Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) : nil }
        func s16(_ offset: Int) -> Int? { u16(offset).map { Int(Int16(truncatingIfNeeded: $0)) } }
        func u32(_ offset: Int) -> Int? { guard let high = u16(offset), let low = u16(offset + 2) else { return nil }; return high << 16 | low }
        func fixed(_ offset: Int) -> Double? { u32(offset).map { Double(Int32(truncatingIfNeeded: $0)) / 65536 } }

        // Intestazione: versione (4), formato (2), offset dei dati orizzontali (2) e verticali (2), riservato (2).
        guard let horizontal = u16(6), horizontal != 0,
              let trackCount = u16(horizontal), let sizeCount = u16(horizontal + 2), let sizeOffset = u32(horizontal + 4),
              sizeCount > 0 else { return nil }
        var sizes: [Double] = []
        for index in 0..<sizeCount {
            guard let size = fixed(sizeOffset + 4 * index) else { return nil }
            sizes.append(size)
        }
        var tracks: [(track: Double, values: [Int])] = []
        for index in 0..<trackCount {
            // Voce di traccia: valore della traccia (4), indice del nome (2), offset dei valori per corpo (2).
            let entry = horizontal + 8 + 8 * index
            guard let track = fixed(entry), let valuesOffset = u16(entry + 6) else { return nil }
            var values: [Int] = []
            for sizeIndex in 0..<sizeCount {
                guard let value = s16(valuesOffset + 2 * sizeIndex) else { return nil }
                values.append(value)
            }
            tracks.append((track, values))
        }
        return Table(sizes: sizes, tracks: tracks.sorted { $0.track < $1.track })
    }
}

extension Tracking.Table {
    /// Valore in unità del font per la traccia 0 a un dato corpo: interpolazione lineare tra i corpi dichiarati,
    /// valore del corpo estremo fuori dall'intervallo. Se la traccia 0 manca si interpola tra le due che la racchiudono.
    func normalValue(atSize size: Double) -> Double? {
        if let normal = tracks.first(where: { $0.track == 0 }) { return value(of: normal.values, atSize: size) }
        guard let below = tracks.last(where: { $0.track < 0 }), let above = tracks.first(where: { $0.track > 0 }) else { return nil }
        let low = value(of: below.values, atSize: size), high = value(of: above.values, atSize: size)
        return low + (high - low) * (0 - below.track) / (above.track - below.track)
    }

    private func value(of values: [Int], atSize size: Double) -> Double {
        guard let upper = sizes.firstIndex(where: { $0 >= size }) else { return Double(values[values.count - 1]) }
        guard upper > 0, sizes[upper] != size else { return Double(values[upper]) }
        let lower = upper - 1
        let fraction = (size - sizes[lower]) / (sizes[upper] - sizes[lower])
        return Double(values[lower]) + (Double(values[upper]) - Double(values[lower])) * fraction
    }
}
