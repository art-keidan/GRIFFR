import AppKit
import SwiftUI
import Typesetting

/// I pulsanti intorno al capoverso progettato: le proprietà che non si trascinano, la portata, Salva e Annulla.
@MainActor
final class ParagraphDesignBarModel: ObservableObject {
    @Published var styleName: String?
    @Published var scope = ParagraphDesignScope.style
    @Published var hasChanges = false
    /// Aggiornamento dal vivo: spento, l'anteprima cambia solo il capoverso evidenziato (Save vale comunque per lo stile).
    @Published var livePreviewAll = true
    @Published var alignment: ParagraphStyle.Alignment = .left
    @Published var lineHeightMultiple: Double = 0
    @Published var keepTogether = false
    @Published var keepWithNext = false
    @Published var linesAtEnd = 1
    @Published var linesAtStart = 1
    @Published var listName = ""
    @Published var lists: [String] = []
    @Published var openingDistance: Double = 0
    @Published var hyphenates = true
    @Published var language = ""
    @Published var languages: [(code: String, name: String)] = []
    @Published var family = ""
    @Published var families: [String] = []
    @Published var size: Double = 12
    @Published var paragraphStyles: [String] = []
    @Published var nextStyle: String?
    /// Le proprietà che lo stile calcola con una formula: si cambiano nel compositore.
    @Published var locked: Set<InspectorProperty> = []
    /// La testata dello stile, la parte scelta, se si può cambiare, e gli stili che una parte può prendere.
    @Published var headingParts: [HeadingPart] = []
    @Published var selectedHeadingPart: Int?
    @Published var headingEditable = false
    @Published var partStyles: [String] = []
    var useStandardHeading: (() -> Void)?
    var removeHeading: (() -> Void)?
    var addHeadingPart: ((HeadingPart) -> Void)?
    var updateHeadingPart: ((Int, HeadingPart) -> Void)?
    var moveHeadingPart: ((Int, Int) -> Void)?
    var removeHeadingPart: ((Int) -> Void)?
    var selectHeadingPart: ((Int?) -> Void)?

    var set: ((InspectorProperty, StyleValues) -> Void)?
    var setNextStyle: ((String?) -> Void)?
    var setScope: ((ParagraphDesignScope) -> Void)?
    var setLivePreviewAll: ((Bool) -> Void)?
    var openFormula: ((InspectorProperty) -> Void)?
    var save: (() -> Void)?
    var cancel: (() -> Void)?

    /// Un valore scelto con un pulsante: nella bozza, o nel compositore se lo stile lo calcola.
    func change(_ property: InspectorProperty, _ build: (inout StyleValues) -> Void) {
        if locked.contains(property) {
            openFormula?(property)
            return
        }
        var values = StyleValues()
        build(&values)
        set?(property, values)
    }

    static let lineHeights: [(String, Double)] = [("Single", 0), ("1.15", 1.15), ("1.25", 1.25), ("1.5", 1.5), ("2", 2)]
    static let openingDistances: [Double] = [0, 36, 72, 108, 144, 216]
    static let sizes: [Double] = [8, 9, 10, 10.5, 11, 12, 13, 14, 16, 18, 20, 24, 30, 36]
}

struct ParagraphDesignBar: View {
    @ObservedObject var model: ParagraphDesignBarModel

    private static let alignments: [(ParagraphStyle.Alignment, String, String)] = [
        (.left, "text.alignleft", "Align left"), (.center, "text.aligncenter", "Center"),
        (.right, "text.alignright", "Align right"), (.justified, "text.justify", "Justify"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if let index = model.selectedHeadingPart, model.headingParts.indices.contains(index) {
                HeadingPartRow(model: model, index: index, part: model.headingParts[index])
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: Theme.bar))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: Theme.line)))
        .fixedSize()
    }

    private var mainRow: some View {
        HStack(spacing: 4) {
            Text(model.styleName ?? "No style")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: Theme.text))
                .padding(.leading, 2)
            modeGroup
            separator
            ForEach(Self.alignments, id: \.1) { alignment, symbol, title in
                toggle(symbol, title, on: model.alignment == alignment, property: .alignment) { model.change(.alignment) { $0.alignment = alignment } }
            }
            iconMenu("arrow.up.and.down.text.horizontal", help: "Line height (the distance between lines: drag the lines under the letters)") {
                ForEach(ParagraphDesignBarModel.lineHeights, id: \.1) { title, value in
                    Button(title + (model.lineHeightMultiple == value ? "  ✓" : "")) { model.change(.lineHeightMultiple) { $0.lineHeightMultiple = value } }
                }
            }
            separator
            toggle("rectangle.compress.vertical", "Keep the lines together on one page", on: model.keepTogether, property: .keepTogether) {
                let on = !model.keepTogether
                model.change(.keepTogether) { $0.keeping.together = on }
            }
            toggle("link", "Keep with the next paragraph", on: model.keepWithNext, property: .keepWithNext) {
                let on = !model.keepWithNext
                model.change(.keepWithNext) { $0.keeping.withNext = on }
            }
            countMenu("arrow.down.to.line.compact", model.linesAtEnd, help: "Lines at least at the bottom of a page") { count in
                model.change(.orphanLines) { $0.keeping.linesAtEnd = count }
            }
            countMenu("arrow.up.to.line.compact", model.linesAtStart, help: "Lines at least at the top of a page") { count in
                model.change(.widowLines) { $0.keeping.linesAtStart = count }
            }
            iconMenu("arrow.down.doc", help: "Opening distance: where the paragraph starts when it opens pages (\(Self.points(model.openingDistance)))") {
                ForEach(ParagraphDesignBarModel.openingDistances, id: \.self) { distance in
                    Button(Self.points(distance) + (model.openingDistance == distance ? "  ✓" : "")) { model.change(.openingDistance) { $0.openingDistance = distance } }
                }
            }
            separator
            iconMenu("list.bullet", help: "List: \(model.listName.isEmpty ? "none" : model.listName)") {
                Button("None" + (model.listName.isEmpty ? "  ✓" : "")) { model.change(.list) { $0.listName = "" } }
                ForEach(model.lists, id: \.self) { name in
                    Button(name + (model.listName == name ? "  ✓" : "")) { model.change(.list) { $0.listName = name } }
                }
            }
            toggle("textformat.characters.dottedunderline", "Hyphenation", on: model.hyphenates, property: .hyphenates) {
                let on = !model.hyphenates
                model.change(.hyphenates) { $0.hyphenates = on }
            }
            iconMenu("globe", help: "Language: \(model.languages.first { $0.code == model.language }?.name ?? "the document's")") {
                Button("Document Language") { model.change(.language) { $0.language = "" } }
                ForEach(model.languages, id: \.code) { language in
                    Button(language.name + (model.language == language.code ? "  ✓" : "")) { model.change(.language) { $0.language = language.code } }
                }
            }
            iconMenu("return", help: "After Return: \(model.nextStyle.flatMap { $0.isEmpty ? nil : $0 } ?? "the same style")") {
                Button("Same Style") { model.setNextStyle?(nil) }
                ForEach(model.paragraphStyles, id: \.self) { name in
                    Button(name + (model.nextStyle == name ? "  ✓" : "")) { model.setNextStyle?(name) }
                }
            }
            iconMenu("textformat", help: "Font: \(model.family)") {
                ForEach(model.families, id: \.self) { family in
                    Button(family + (model.family == family ? "  ✓" : "")) { model.change(.family) { $0.family = family } }
                }
            }
            iconMenu("textformat.size", help: "Size: \(Self.points(model.size))") {
                ForEach(ParagraphDesignBarModel.sizes, id: \.self) { size in
                    Button(Self.points(size) + (model.size == size ? "  ✓" : "")) { model.change(.size) { $0.size = size } }
                }
            }
            separator
            headingMenu
        }
    }

    /// La testata dello stile: aggiungere le parti, sceglierne una, toglierla.
    private var headingMenu: some View {
        let mm = 72 / 25.4
        return iconMenu("rectangle.split.1x2", help: model.headingEditable
                        ? "Heading of the style: add parts, choose one to change it (on the page, click its band)"
                        : "Heading of the style: it belongs to the style, so it changes only with the eye open on the style") {
            Button("Ready-made Heading") { model.useStandardHeading?() }
            Divider()
            Button("Label") { model.addHeadingPart?(.label(text: "Chapter", style: nil, alignment: .left, minHeight: nil)) }
            Button("Section Number") { model.addHeadingPart?(.number(prefix: "", style: nil, alignment: .left, minHeight: nil)) }
            Button("Number Beside Title") { model.addHeadingPart?(.numberBeside(prefix: "", style: nil, side: .left, gap: 4 * mm)) }
            Button("Write Result") {
                model.addHeadingPart?(.result(formula: .sectionContainingTitle(role: Typesetting.Section.Role.part), prefix: "", style: nil, alignment: .left, minHeight: nil))
            }
            Button("Rule") { model.addHeadingPart?(.rule(thickness: 0.5 * mm, length: nil, alignment: .left)) }
            Button("Space") { model.addHeadingPart?(.space(3 * mm)) }
            if !model.headingParts.isEmpty {
                Divider()
                ForEach(Array(model.headingParts.enumerated()), id: \.offset) { index, part in
                    Button(part.title + (model.selectedHeadingPart == index ? "  ✓" : "")) { model.selectHeadingPart?(index) }
                }
                Divider()
                Button("Remove Heading") { model.removeHeading?() }
            }
        }
        .disabled(!model.headingEditable)
    }

    /// A chi vanno le modifiche e che cosa si aggiorna dal vivo: tre icone, una accesa.
    private var modeGroup: some View {
        let name = model.styleName.map { "“\($0)”" } ?? "the style"
        return HStack(spacing: 1) {
            // Un occhio solo: pieno, tutti i capoversi dello stile si aggiornano dal vivo; barrato, solo questo.
            modeButton(model.livePreviewAll ? "eye" : "eye.slash",
                       model.livePreviewAll ? "Live on every \(name) paragraph (click: only this one)" : "Live on this paragraph only (click: every \(name) paragraph); Save still changes the style",
                       on: model.scope == .style) {
                if model.scope == .style { model.setLivePreviewAll?(!model.livePreviewAll) } else { model.setScope?(.style) }
            }
            .disabled(model.styleName == nil)
            modeButton("paragraphsign", "Only this paragraph: the changes stay on it, the style does not change",
                       on: model.scope == .paragraph) { model.setScope?(.paragraph) }
        }
    }

    private func modeButton(_ symbol: String, _ help: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 16) }
            .buttonStyle(.hover(on ? .prominent : .borderless))
            .help(help)
    }

    private var separator: some View { Divider().frame(height: 16).padding(.horizontal, 2) }

    /// Un pulsante a icona che si accende quando la proprietà vale; ƒ se la calcola una formula.
    private func toggle(_ symbol: String, _ help: String, on: Bool, property: InspectorProperty, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 16)
                .overlay(alignment: .topTrailing) { if model.locked.contains(property) { Text("ƒ").font(.system(size: 7, weight: .bold)).offset(x: 4, y: -3) } }
        }
        .buttonStyle(.hover(on ? .prominent : .borderless))
        .help(model.locked.contains(property) ? "\(help): calculated by a formula — opens the composer" : help)
    }

    private func iconMenu<Content: View>(_ symbol: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) { Image(systemName: symbol) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(help)
    }

    /// Un numero di righe (1–9) con la sua icona.
    private func countMenu(_ symbol: String, _ value: Int, help: String, choose: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(Array(LineKeeping.lineRange), id: \.self) { count in
                Button("\(count)" + (count == value ? "  ✓" : "")) { choose(count) }
            }
        } label: {
            HStack(spacing: 1) { Image(systemName: symbol); Text("\(value)").font(.system(size: 10, weight: .semibold).monospacedDigit()) }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("\(help): \(value)")
    }

    static func points(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + " pt" }
}

/// Salva e Annulla, fissi in alto a destra della zona visibile: restano a portata anche scorrendo le pagine.
struct ParagraphDesignActions: View {
    @ObservedObject var model: ParagraphDesignBarModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: model.hasChanges ? Theme.accent : Theme.line))
                .frame(width: 7, height: 7)
                .help(model.hasChanges ? "Unsaved changes" : "No changes yet")
            Button("Cancel") { model.cancel?() }
                .buttonStyle(.hover(.borderless))
                .help("Discard the changes (Esc)")
            Button("Save") { model.save?() }
                .buttonStyle(.hover(model.hasChanges ? .prominent : .bordered))
                .help("Write the changes into the document: one step of Undo")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: Theme.bar))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: Theme.line)))
        .fixedSize()
    }
}

// MARK: - La vista Selection del pannello

/// La vista Selection: per ora solo l'ingresso alla progettazione del capoverso.
@MainActor
final class SelectionPanelModel: ObservableObject {
    @Published var isDesigning = false
    @Published var styleName: String?
    var toggle: (() -> Void)?
}

struct SelectionPanelView: View {
    @ObservedObject var model: SelectionPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.toggle?() } label: {
                Label(model.isDesigning ? "Save and Stop Designing" : "Design the Paragraph", systemImage: "paragraphsign")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.hover(model.isDesigning ? .prominent : .bordered))
            .controlSize(.large)
            Text(model.isDesigning
                 ? "Drag the handles on the page: indents, space before and after, the lines under the letters for the distance between lines, and the page margins. The changes show live on every paragraph of the style\(model.styleName.map { " “\($0)”" } ?? ""), or on this one only; Save writes them, Cancel (Esc) discards them."
                 : "Design the paragraph of the cursor directly on the page: the rest of the text fades, and its measures become handles.")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Theme.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: Theme.side))
    }
}

extension EditorWindowController {
    /// La vista Selection del pannello.
    func makeSelectionPanel() -> NSView {
        selectionPanelModel.toggle = { [weak self] in self?.toggleParagraphDesign(nil) }
        let host = NSHostingView(rootView: SelectionPanelView(model: selectionPanelModel).themed())
        // Come faceva l'ispettore: le misure del contenuto non vanno alla finestra, che altrimenti cambierebbe dimensione.
        host.sizingOptions = []
        return host
    }
}

// MARK: - Le proprietà della parte della testata scelta

extension HeadingPart {
    var alignment: HeadingAlignment? {
        switch self {
        case .label(_, _, let a, _), .number(_, _, let a, _), .result(_, _, _, let a, _), .rule(_, _, let a): a
        case .numberBeside(_, _, let side, _): side
        default: nil
        }
    }

    func with(alignment: HeadingAlignment) -> HeadingPart {
        switch self {
        case .label(let t, let s, _, let h): .label(text: t, style: s, alignment: alignment, minHeight: h)
        case .number(let p, let s, _, let h): .number(prefix: p, style: s, alignment: alignment, minHeight: h)
        case .result(let f, let p, let s, _, let h): .result(formula: f, prefix: p, style: s, alignment: alignment, minHeight: h)
        case .rule(let t, let l, _): .rule(thickness: t, length: l, alignment: alignment)
        case .numberBeside(let p, let s, _, let g): .numberBeside(prefix: p, style: s, side: alignment, gap: g)
        default: self
        }
    }

    var style: String?? {
        switch self {
        case .label(_, let s, _, _), .number(_, let s, _, _), .result(_, _, let s, _, _), .numberBeside(_, let s, _, _): .some(s)
        default: nil
        }
    }

    func with(style: String?) -> HeadingPart {
        switch self {
        case .label(let t, _, let a, let h): .label(text: t, style: style, alignment: a, minHeight: h)
        case .number(let p, _, let a, let h): .number(prefix: p, style: style, alignment: a, minHeight: h)
        case .result(let f, let p, _, let a, let h): .result(formula: f, prefix: p, style: style, alignment: a, minHeight: h)
        case .numberBeside(let p, _, let side, let g): .numberBeside(prefix: p, style: style, side: side, gap: g)
        default: self
        }
    }

    /// Il testo che si scrive: dell'etichetta, o quello prima del numero o del risultato.
    var editableText: String? {
        switch self {
        case .label(let t, _, _, _): t
        case .number(let p, _, _, _), .result(_, let p, _, _, _), .numberBeside(let p, _, _, _): p
        default: nil
        }
    }

    func with(text: String) -> HeadingPart {
        switch self {
        case .label(_, let s, let a, let h): .label(text: text, style: s, alignment: a, minHeight: h)
        case .number(_, let s, let a, let h): .number(prefix: text, style: s, alignment: a, minHeight: h)
        case .result(let f, _, let s, let a, let h): .result(formula: f, prefix: text, style: s, alignment: a, minHeight: h)
        case .numberBeside(_, let s, let side, let g): .numberBeside(prefix: text, style: s, side: side, gap: g)
        default: self
        }
    }
}

/// La riga delle proprietà della parte scelta: testo, allineamento (o lato), stile, ordine, togli.
struct HeadingPartRow: View {
    @ObservedObject var model: ParagraphDesignBarModel
    let index: Int
    let part: HeadingPart
    @State private var text = ""

    private var alignments: [(HeadingAlignment, String)] {
        if case .numberBeside = part { return [(.left, "Left"), (.right, "Right"), (.outside, "Out"), (.inside, "In")] }
        return [(.left, "Left"), (.center, "Center"), (.right, "Right"), (.outside, "Out"), (.inside, "In")]
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(part.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.text))
            if let current = part.editableText {
                TextField(part.isLabel ? "Text" : "Before the number", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onAppear { text = current }
                    .onChange(of: current) { _, value in text = value }
                    .onSubmit { model.updateHeadingPart?(index, part.with(text: text)) }
                    .help("Press Return to apply")
            }
            if let current = part.alignment {
                HStack(spacing: 1) {
                    ForEach(alignments, id: \.0) { alignment, title in
                        Button(title) { model.updateHeadingPart?(index, part.with(alignment: alignment)) }
                            .buttonStyle(.hover(current == alignment ? .prominent : .borderless))
                    }
                }
            }
            if let current = part.style {
                Menu {
                    Button("Title's Style" + (current == nil ? "  ✓" : "")) { model.updateHeadingPart?(index, part.with(style: nil)) }
                    ForEach(model.partStyles, id: \.self) { name in
                        Button(name + (current == name ? "  ✓" : "")) { model.updateHeadingPart?(index, part.with(style: name)) }
                    }
                } label: { Label(current ?? "Title's style", systemImage: "textformat").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("The style that gives the part its look")
            }
            Divider().frame(height: 16)
            Button { model.moveHeadingPart?(index, -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.hover(.borderless)).disabled(index == 0).help("Move up")
            Button { model.moveHeadingPart?(index, 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.hover(.borderless)).disabled(index >= model.headingParts.count - 1).help("Move down")
            Button { model.removeHeadingPart?(index) } label: { Image(systemName: "trash") }
                .buttonStyle(.hover(.borderless)).help("Remove the part")
            Button { model.selectHeadingPart?(nil) } label: { Image(systemName: "xmark") }
                .buttonStyle(.hover(.borderless)).help("Done with this part")
        }
        .disabled(!model.headingEditable)
    }
}

extension HeadingPart {
    var isLabel: Bool { if case .label = self { true } else { false } }
}

