import CoreText
import SwiftUI
import Typesetting

/// Stato del pannello delle funzioni: rispecchia il font della selezione corrente.
@MainActor
final class FeaturePanelModel: ObservableObject {
    @Published var fontName = ""
    @Published var tables = ""
    @Published var usesMorx = false
    /// Spaziatura in punti che la tabella `trak` del font prevede al corpo corrente, se ce n'è una.
    @Published var tracking: CGFloat?
    @Published var otherFontsInSelection = 0
    @Published var types: [FeatureType] = []
    @Published var settings: [FeatureSetting] = []
    /// Tag OpenType che Core Text non elenca tra le funzioni: quelli che accetta di forzare, e quelli che il font
    /// applica da sé senza che si possano comandare.
    @Published var forceableTags: [String] = []
    @Published var automaticTags: [String] = []
    /// Il file da cui il font è letto.
    @Published var fontFile = ""
    /// Vero se il font è a più assi, e se la stessa famiglia è installata anche nell'altro modo (in file statici
    /// separati, o come font a più assi).
    @Published var isVariableFont = false
    @Published var hasOtherInstall = false
    /// Passa dal font a più assi ai file statici della stessa famiglia, o viceversa.
    var setUsesVariableFont: ((Bool) -> Void)?
    private var otherInstalls: [String: Bool] = [:]

    /// Se il documento applica la spaziatura `trak`. Vale per tutto il documento, non per il solo font mostrato.
    @Published var appliesFontTracking = true
    /// Avvisa l'editor che l'interruttore di `trak` è stato azionato.
    var setFontTracking: ((Bool) -> Void)?
    /// Se il documento allinea ai margini i bordi ottici dei glifi.
    @Published var usesOpticalMargins = true
    var setOpticalMargins: ((Bool) -> Void)?
    /// Vero se il font della selezione dichiara bordi ottici (tabella `opbd`, oppure `lfbd`/`rtbd` in GPOS).
    @Published var hasOpticalBounds = false

    /// Chiede all'editor di trasformare le impostazioni del font nella selezione.
    var apply: ((@escaping ([FeatureSetting]) -> [FeatureSetting]) -> Void)?

    /// Gli assi di variazione del font (vuoto se non ne ha), il valore che ciascuno ha ora, e quali sono fissati.
    @Published var axes: [FontAxis] = []
    @Published var axisValues: [String: Double] = [:]
    @Published var fixedAxes: Set<String> = []
    /// Fissa un asse a un valore; `nil` lo lascia tornare al suo valore naturale.
    var setAxis: ((String, Double?) -> Void)?
    /// Avvisa che il trascinamento di un cursore comincia o finisce: tutto il trascinamento è una modifica sola.
    var axisDragging: ((Bool) -> Void)?

    /// Le funzioni Graphite del font (vuoto se non ha le tabelle o se graphite2 manca), e quelle del testo scelto:
    /// `nil` se il testo si compone con Core Text, altrimenti `tag=valore` separate da spazi.
    @Published var graphiteFeatures: [GraphiteFeature] = []
    @Published var graphiteSettings: String?
    /// Chiede all'editor di dare al testo scelto queste funzioni Graphite (la composizione resta Graphite).
    var setGraphite: ((String) -> Void)?
    private var graphiteFeaturesByFont: [String: [GraphiteFeature]] = [:]

    /// Il valore di una funzione Graphite nel testo scelto: quello scritto, o quello predefinito del font.
    func graphiteValue(of feature: GraphiteFeature) -> UInt16 {
        for item in (graphiteSettings ?? "").split(separator: " ") {
            let parts = item.split(separator: "=", maxSplits: 1)
            if parts.count == 2, String(parts[0]) == feature.tag, let value = UInt16(parts[1]) { return value }
        }
        return feature.defaultValue
    }

    /// Dà a una funzione Graphite un valore: si scrivono solo le funzioni diverse dal valore predefinito.
    func setGraphiteValue(_ value: UInt16, of feature: GraphiteFeature) {
        let values = graphiteFeatures.map { $0.id == feature.id ? ($0, value) : ($0, graphiteValue(of: $0)) }
        setGraphite?(values.filter { $0.1 != $0.0.defaultValue }.map { "\($0.0.tag)=\($0.1)" }.joined(separator: " "))
    }

    /// Tabelle che contano per la composizione, nell'ordine in cui vengono mostrate.
    private static let layoutTables = ["morx", "mort", "kerx", "kern", "feat", "just", "opbd", "lcar", "trak", "bsln", "prop", "GSUB", "GPOS", "GDEF"]

    func show(font: CTFont?, otherFonts: Int) {
        otherFontsInSelection = otherFonts
        guard let font else {
            fontName = ""; tables = ""; types = []; settings = []; forceableTags = []; automaticTags = []; usesMorx = false; tracking = nil; hasOpticalBounds = false
            axes = []; axisValues = [:]; fixedAxes = []; fontFile = ""; isVariableFont = false; hasOtherInstall = false
            graphiteFeatures = []
            return
        }
        let baseName = FontVariations.baseName(of: font)
        if graphiteFeaturesByFont[baseName] == nil { graphiteFeaturesByFont[baseName] = Graphite.features(of: font) }
        graphiteFeatures = graphiteFeaturesByFont[baseName] ?? []
        let present = font.tableTags
        // Per una faccia ottenuta spostando gli assi Core Text compone un nome con i valori in esadecimale: si mostra quello di base.
        fontName = "\(font.displayName) — \(FontVariations.baseName(of: font))"
        axes = FontVariations.axes(of: font).filter { !$0.isHidden }
        axisValues = FontVariations.coordinates(of: font)
        fixedAxes = Set(FontVariations.values(of: font).map(\.tag))
        fontFile = FontVariations.fileURL(of: font)?.lastPathComponent ?? ""
        isVariableFont = FontVariations.isVariable(font)
        // Cercare l'altra installazione costa una ricerca tra i font: la risposta si ricorda per famiglia e stile.
        let key = "\(CTFontCopyFamilyName(font))|\(CTFontCopyAttribute(font, kCTFontStyleNameAttribute) as? String ?? "")|\(isVariableFont)"
        if otherInstalls[key] == nil { otherInstalls[key] = FontVariations.counterpart(of: font, variable: !isVariableFont) != nil }
        hasOtherInstall = otherInstalls[key] ?? false
        tables = Self.layoutTables.filter(present.contains).joined(separator: " ")
        usesMorx = present.contains("morx") || present.contains("mort")
        types = FontFeatures.types(of: font)
        settings = FontFeatures.settings(of: font)
        forceableTags = FontFeatures.forceableOpenTypeTags(of: font)
        // `aalt` non è una funzione di composizione: è l'accesso a tutte le alternative, che Core Text propone
        // più sopra come «Alternative» (tipo 17).
        automaticTags = FontFeatures.unlistedOpenTypeTags(of: font).filter { !forceableTags.contains($0) && $0 != "aalt" }
        tracking = Tracking.normalTracking(for: font)
        let positioning = FontFeatures.openTypeTags(of: font).gpos
        hasOpticalBounds = present.contains("opbd") || positioning.contains("lfbd") || positioning.contains("rtbd")
    }
}

struct FeaturePanelView: View {
    @ObservedObject var model: FeaturePanelModel
    /// Vero quando il pannello è un gruppo dell'ispettore: niente scorrimento proprio né margini.
    var embedded = false

    /// Il pannello come vista AppKit. Tenere SwiftUI in questo solo file evita che i suoi tipi `Document` e
    /// `TextSelection` si confondano con quelli del nostro motore nel resto dell'app.
    @MainActor
    static func makeHostingView(model: FeaturePanelModel) -> NSView {
        NSHostingView(rootView: FeaturePanelView(model: model).themed())
    }

    var body: some View {
        if embedded {
            sections
        } else {
            ScrollView {
                sections
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 300)
        }
    }

    private var sections: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
                header
                if model.types.isEmpty && model.forceableTags.isEmpty && !model.fontName.isEmpty {
                    Text("Il font non dichiara funzioni selezionabili.").foregroundStyle(.secondary)
                }
                if model.hasOtherInstall { installSection }
                if !model.axes.isEmpty { axesSection }
                if model.tables.contains("trak") { trackingSection }
                if model.hasOpticalBounds { opticalMarginsSection }
                ForEach(model.types) { type in
                    typeSection(type)
                }
                if !model.forceableTags.isEmpty { unlistedSection }
                if !model.automaticTags.isEmpty { automaticSection }
                if !model.graphiteFeatures.isEmpty { graphiteSection }
        }
    }

    /// Le funzioni Graphite del font: valgono quando il testo si compone con Graphite.
    private var graphiteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Funzioni Graphite").font(.headline)
            if model.graphiteSettings == nil {
                Text("Valgono quando la composizione è Graphite: si sceglie nell'ispettore, Carattere › Composizione.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.graphiteFeatures, id: \.id) { feature in
                graphiteRow(feature)
            }
        }
        .disabled(model.graphiteSettings == nil)
    }

    /// Una funzione Graphite: un interruttore se è sì/no, altrimenti i suoi valori a scelta, come le funzioni OpenType.
    @ViewBuilder
    private func graphiteRow(_ feature: GraphiteFeature) -> some View {
        let current = model.graphiteValue(of: feature)
        let name = feature.name.isEmpty ? feature.tag : feature.name
        let code = Text("gr.\(feature.tag)").font(.caption.monospaced()).foregroundStyle(.secondary)
        if feature.values.count == 2 && Set(feature.values.map(\.value)) == [0, 1] {
            Toggle(isOn: Binding(get: { current == 1 }, set: { model.setGraphiteValue($0 ? 1 : 0, of: feature) })) {
                HStack(alignment: .firstTextBaseline) { Text(name); code }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) { Text(name); code }
                Picker("", selection: Binding(get: { current }, set: { model.setGraphiteValue($0, of: feature) })) {
                    ForEach(feature.values, id: \.value) { value in
                        Text(value.name.isEmpty ? String(value.value) : value.name).tag(value.value)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Funzioni del font").font(.title3.bold())
            if model.fontName.isEmpty {
                Text("Nessun font nella selezione.").foregroundStyle(.secondary)
            } else {
                Text(model.fontName).textSelection(.enabled)
                Text("Tabelle: \(model.tables)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if !model.fontFile.isEmpty {
                    Text("File: \(model.fontFile)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if model.otherFontsInSelection > 0 {
                    Text("La selezione contiene anche \(model.otherFontsInSelection) altr\(model.otherFontsInSelection == 1 ? "o" : "i") font: le modifiche toccano solo il testo in questo font.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    /// Quando la famiglia è installata sia come font a più assi sia in file statici: quale dei due usare.
    private var installSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Famiglia installata in due modi").font(.headline)
            Toggle(isOn: Binding<Bool>(
                get: { model.isVariableFont },
                set: { model.setUsesVariableFont?($0) }
            )) { Text("Usa il font a più assi") }
            Text(model.isVariableFont ? "Statico: perde gli assi fissati a mano." : "Variabile: attiva i cursori degli assi.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Gli assi di un font a più assi: un cursore e un campo numerico per ciascuno.
    private var axesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Assi del font").font(.headline)
                Text("tabella fvar").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            ForEach(model.axes) { axis in
                axisRow(axis)
            }
            if !model.fixedAxes.isEmpty {
                Button("Riporta tutti gli assi al valore naturale") {
                    for axis in model.axes where model.fixedAxes.contains(axis.tag) { model.setAxis?(axis.tag, nil) }
                }
                .controlSize(.small)
            }
        }
    }

    private func axisRow(_ axis: FontAxis) -> some View {
        let value = Binding<Double>(
            get: { model.axisValues[axis.tag] ?? axis.defaultValue },
            set: { model.setAxis?(axis.tag, min(max($0, axis.minimum), axis.maximum)) })
        let isFixed = model.fixedAxes.contains(axis.tag)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(axis.name)
                Text(axis.tag).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
            HStack(spacing: 6) {
                Slider(value: value, in: axis.minimum...max(axis.maximum, axis.minimum + 0.0001)) { dragging in model.axisDragging?(dragging) }
                    .controlSize(.small)
                Button {
                    model.setAxis?(axis.tag, nil)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(!isFixed)
                .help("Lascia l'asse al suo valore naturale")
                .accessibilityLabel("Riporta \(axis.name) al valore naturale")
            }
            Text("da \(axis.minimum, format: .number.precision(.fractionLength(0...2))) a \(axis.maximum, format: .number.precision(.fractionLength(0...2))), predefinito \(axis.defaultValue, format: .number.precision(.fractionLength(0...2)))\(isFixed ? " · fissato" : "")")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    /// La tabella `trak` non è una funzione selezionabile del font, ma si comanda da qui come le altre.
    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spaziatura per corpo").font(.headline)
                Text("tabella trak").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding<Bool>(
                get: { model.appliesFontTracking },
                set: { model.setFontTracking?($0) }
            )) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Applica")
                    if let tracking = model.tracking {
                        Text("\(tracking, format: .number.precision(.fractionLength(0...3)).sign(strategy: .always())) pt per glifo a questo corpo")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    } else {
                        Text("nessuna a questo corpo").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
                .help("Spaziatura prevista dal font per il corpo corrente; vale per tutto il documento.")
        }
    }

    private var opticalMarginsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Margini ottici").font(.headline)
                Text(model.tables.contains("opbd") ? "tabella opbd" : "lfbd · rtbd").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding<Bool>(
                get: { model.usesOpticalMargins },
                set: { model.setOpticalMargins?($0) }
            )) { Text("Applica") }
            Text("Punteggiatura oltre il margine · tutto il documento")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func typeSection(_ type: FeatureType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(type.name).font(.headline)
                Text(typeCode(type)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if type.isExclusive {
                Picker("", selection: Binding<FeatureSetting>(
                    get: { type.activeSelector(in: model.settings)?.setting ?? type.selectors[0].setting },
                    set: { chosen in
                        guard let selector = type.selectors.first(where: { $0.setting == chosen }) else { return }
                        model.apply? { type.selecting(selector, in: $0) }
                    }
                )) {
                    ForEach(type.selectors) { selector in
                        selectorLabel(selector).tag(selector.setting)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } else {
                ForEach(type.selectors) { selector in
                    Toggle(isOn: Binding<Bool>(
                        get: { type.isOn(selector, in: model.settings) },
                        set: { on in model.apply? { type.setting(selector, on: on, in: $0) } }
                    )) { selectorLabel(selector) }
                }
            }
        }
    }

    private var unlistedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Altri tag OpenType").font(.headline)
            Text(model.usesMorx ? "Con morx questi interruttori possono non avere effetto." : "Tag forzabili non elencati sopra.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(model.forceableTags, id: \.self) { tag in
                Toggle(isOn: Binding<Bool>(
                    get: { model.settings.contains(.openType(tag: tag, value: 1)) },
                    set: { on in
                        model.apply? { settings in
                            settings.filter { if case .openType(tag, _) = $0 { false } else { true } }
                                + (on ? [.openType(tag: tag, value: 1)] : [])
                        }
                    }
                )) { Text(tag).font(.body.monospaced()) }
            }
        }
    }

    /// Le funzioni di composizione: solo un elenco, perché non si comandano.
    private var automaticSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Funzioni applicate dal font da sé").font(.headline)
            Text(model.automaticTags.joined(separator: "  ")).font(.caption.monospaced()).textSelection(.enabled)
            Text("Solo lettura: Core Text non consente di cambiarle.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func typeCode(_ type: FeatureType) -> String {
        switch type.key {
        case .aat(let id): "tipo \(id)" + (type.isExclusive ? " · esclusivo" : "")
        case .openType(let tag): "OpenType \(tag)"
        }
    }

    private func selectorLabel(_ selector: FeatureSelector) -> some View {
        var code = selector.setting.description
        if case .aat = selector.setting, let tag = selector.openTypeTag { code += " · \(tag)" }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(selector.name)
            Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}
