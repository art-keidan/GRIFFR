import AppKit

/// La disposizione delle fasce dell'interfaccia dettagliata: per ciascuna fascia (strumenti, carattere, paragrafo) le
/// zone, con il loro nome e i pulsanti che contengono. Vale per tutta l'applicazione e si ricorda; l'interfaccia
/// essenziale non la usa.
///
/// I pulsanti si chiamano con il nome dei comandi della barra («salva», «lorem») o dei controlli delle fasce
/// («famiglia», «corsivo»): un pulsante sta in un solo posto.
@MainActor
struct BandLayout: Codable, Equatable {
    struct Zone: Codable, Equatable {
        var title: String
        var items: [String]
    }

    /// Le fasce, dall'alto.
    enum Band: Int, CaseIterable { case tools, character, paragraph }

    var bands: [[Zone]]

    static let key = "BandLayout.advanced"
    static let changed = Notification.Name("WordProcessorBandLayoutChanged")

    /// Le zone di sempre del carattere e del paragrafo.
    static let defaultCharacter: [Zone] = [
        Zone(title: "famiglia", items: ["famiglia", "variabile"]),
        Zone(title: "peso", items: ["faccia", "pesi"]),
        Zone(title: "ruoli", items: ["ruoli"]),
        Zone(title: "corpo", items: ["corpo", "corpoOttico", "corpoOtticoScelta"]),
        Zone(title: "forma", items: ["corsivo", "maiuscoletto", "apice", "pedice"]),
        Zone(title: "segni", items: ["sottolineato", "barrato", "colore"]),
        Zone(title: "lingua", items: ["lingua"]),
        Zone(title: "simboli", items: ["carattereSpeciale"]),
    ]

    static let defaultParagraph: [Zone] = [
        Zone(title: "stili", items: ["stile", "stileCarattere", "stiliFlottanteBanda"]),
        Zone(title: "allineamento", items: ["allineamento"]),
        Zone(title: "spazi", items: ["interlinea", "spazi"]),
        Zone(title: "elenchi", items: ["puntato", "numerato", "lista", "riduciLivello", "aumentaLivello"]),
        Zone(title: "regole", items: ["regoleBanda"]),
    ]

    /// I nomi dei controlli delle fasce, per la zona che nasce trascinandone uno fuori dalle zone.
    static let itemNames: [String: String] = [
        "famiglia": "famiglia", "variabile": "variabile", "faccia": "faccia", "pesi": "pesi", "ruoli": "ruoli",
        "corpo": "corpo", "corpoOttico": "corpo ottico", "corpoOtticoScelta": "disegno ottico",
        "corsivo": "corsivo", "maiuscoletto": "maiuscoletto", "apice": "apice", "pedice": "pedice",
        "sottolineato": "sottolineato", "barrato": "barrato", "colore": "colore", "lingua": "lingua",
        "carattereSpeciale": "simboli", "stile": "stile", "stileCarattere": "stile di parola",
        "stiliFlottanteBanda": "flottanti", "allineamento": "allineamento", "interlinea": "interlinea", "spazi": "spazi",
        "puntato": "puntato", "numerato": "numerato", "lista": "lista", "riduciLivello": "livello", "aumentaLivello": "livello",
        "regoleBanda": "regole",
    ]

    static func name(of item: String) -> String {
        itemNames[item] ?? EditorWindowController.toolbarCommands.first { $0.id == item }?.title.lowercased() ?? item
    }

    /// I comandi della barra in gruppi, ciascuno in una zona col nome del genere dei suoi comandi.
    static func toolZones(from toolbarItems: [String]) -> [Zone] {
        var groups: [[String]] = [[]]
        for id in toolbarItems {
            if id == "|" { groups.append([]) } else { groups[groups.count - 1].append(id) }
        }
        return groups.filter { !$0.isEmpty }.map { Zone(title: EditorWindowController.zoneTitle(for: $0), items: $0) }
    }

    static var standard: BandLayout {
        BandLayout(bands: [toolZones(from: EditorWindowController.toolbarItems(for: .advanced)), defaultCharacter, defaultParagraph])
    }

    /// Ciò che la barra degli strumenti dice di sé nella configurazione dei comandi: i comandi della fascia degli
    /// strumenti, zona per zona (gli altri controlli che vi stanno non sono comandi della barra).
    var toolbarItems: [String] {
        let known = Set(EditorWindowController.toolbarCommands.map(\.id))
        return bands[Band.tools.rawValue].map { $0.items.filter(known.contains) }.filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, group in
                if !result.isEmpty { result.append("|") }
                result.append(contentsOf: group)
            }
    }

    var allItems: [String] { bands.flatMap { $0.flatMap(\.items) } }

    /// La disposizione ricordata, allineata alla configurazione dei comandi della barra (che si cambia anche da
    /// «Personalizza gli strumenti…»): se questa è cambiata, la fascia degli strumenti la segue; ciò che vi stava e
    /// non è un comando resta, in fondo; un comando che arriva nella barra lascia la fascia dove stava.
    static func load(from defaults: UserDefaults = .standard) -> BandLayout {
        let commands = EditorWindowController.toolbarItems(for: .advanced)
        guard let data = defaults.data(forKey: key), var layout = try? JSONDecoder().decode(BandLayout.self, from: data),
              layout.bands.count == Band.allCases.count else { return standard }
        guard layout.toolbarItems != commands else { return layout.normalized() }
        let known = Set(EditorWindowController.toolbarCommands.map(\.id))
        let others = layout.bands[Band.tools.rawValue].flatMap(\.items).filter { !known.contains($0) }
        var tools = toolZones(from: commands)
        // I nomi dati a mano restano alle zone che hanno ancora gli stessi comandi.
        for index in tools.indices {
            if let old = layout.bands[Band.tools.rawValue].first(where: { $0.items.filter(known.contains) == tools[index].items }) {
                tools[index].title = old.title
            }
        }
        if !others.isEmpty { tools.append(Zone(title: "altro", items: others)) }
        let inTools = Set(tools.flatMap(\.items))
        layout.bands[Band.tools.rawValue] = tools
        for band in [Band.character, .paragraph] {
            for index in layout.bands[band.rawValue].indices {
                layout.bands[band.rawValue][index].items.removeAll { inTools.contains($0) }
            }
        }
        return layout.normalized()
    }

    /// Senza zone vuote, senza pulsanti ripetuti, e con ogni controllo delle fasce da qualche parte (uno nuovo va
    /// nella zona di sempre, se c'è, o in una zona sua in fondo alla sua fascia).
    func normalized() -> BandLayout {
        var result = self
        var seen = Set<String>()
        for band in result.bands.indices {
            for zone in result.bands[band].indices {
                result.bands[band][zone].items = result.bands[band][zone].items.filter { seen.insert($0).inserted }
            }
        }
        for (band, defaults) in [(Band.character, Self.defaultCharacter), (.paragraph, Self.defaultParagraph)] {
            for zone in defaults {
                for item in zone.items where !seen.contains(item) {
                    seen.insert(item)
                    if let index = result.bands[band.rawValue].firstIndex(where: { $0.title == zone.title }) {
                        result.bands[band.rawValue][index].items.append(item)
                    } else {
                        result.bands[band.rawValue].append(Zone(title: zone.title, items: [item]))
                    }
                }
            }
        }
        for band in result.bands.indices { result.bands[band].removeAll { $0.items.isEmpty } }
        return result
    }

    /// Salva la disposizione, allinea la configurazione dei comandi della barra e avvisa le finestre.
    func save(to defaults: UserDefaults = .standard) {
        let layout = normalized()
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.key)
        if EditorWindowController.toolbarItems(for: .advanced) != layout.toolbarItems {
            EditorWindowController.setToolbarItems(layout.toolbarItems, for: .advanced)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// La modalità in cui si sistema la disposizione: zone e pulsanti si trascinano, e i pulsanti non fanno il loro
/// comando. Vale per tutte le finestre; spenta, nulla si trascina.
@MainActor
enum BandLayoutEditing {
    static let changed = Notification.Name("WordProcessorBandLayoutEditingChanged")

    static var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
