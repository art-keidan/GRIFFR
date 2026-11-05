import AppKit
import SwiftUI
import Typesetting

/// Il modello delle impostazioni: una coppia famiglia-ruolo alla volta, con entrambe le installazioni affiancate.
@MainActor
final class FontRoleSettingsModel: ObservableObject {
    let families: [String]
    @Published private(set) var family: String
    @Published private(set) var role: FontRole = .bold
    @Published private(set) var equivalence = FontRoleEquivalence()
    @Published private(set) var staticFaces: [String] = []
    @Published private(set) var variableBases: [String] = []
    @Published private(set) var axes: [FontAxis] = []
    @Published private(set) var axisValues: [String: Double] = [:]
    @Published private(set) var fixedAxes: Set<String> = []
    @Published private(set) var table: FontRoleTable

    var onChange: ((FontRoleTable) -> Void)?
    var onApply: (() -> Void)?

    init(table: FontRoleTable, families: [String]? = nil, preferredFamily: String? = nil) {
        self.table = table
        let available = OpticalFonts.families(families ?? NSFontManager.shared.availableFontFamilies.sorted())
        self.families = available
        family = preferredFamily.flatMap { available.contains($0) ? $0 : nil } ?? available.first ?? ""
        reload()
    }

    var isCustomized: Bool { table.customization(family: family, role: role) != nil }

    func selectFamily(_ name: String) {
        guard families.contains(name), name != family else { return }
        family = name
        reload()
    }

    func selectRole(_ newRole: FontRole) {
        guard newRole != role else { return }
        role = newRole
        reload()
    }

    func chooseStatic(_ name: String?) {
        equivalence.staticFace = name?.isEmpty == false ? name : nil
        commit()
    }

    func chooseVariableBase(_ name: String?) {
        guard let name, !name.isEmpty,
              let font = FontVariations.font(named: name, size: 12, preferringVariable: true), FontVariations.isVariable(font) else {
            equivalence.variableInstance = nil
            axes = []; axisValues = [:]; fixedAxes = []
            commit()
            return
        }
        equivalence.variableInstance = VariableFontInstance(fontName: FontVariations.baseName(of: font))
        axes = FontVariations.axes(of: font).filter { !$0.isHidden }
        axisValues = FontVariations.coordinates(of: font)
        fixedAxes = []
        commit()
    }

    func setAxis(_ tag: String, value: Double?) {
        guard var instance = equivalence.variableInstance, let axis = axes.first(where: { $0.tag == tag }) else { return }
        if let value {
            let clamped = min(max(value, axis.minimum), axis.maximum)
            fixedAxes.insert(tag)
            axisValues[tag] = clamped
        } else {
            fixedAxes.remove(tag)
            axisValues[tag] = axis.defaultValue
        }
        instance.variations = axes.compactMap { axis in
            fixedAxes.contains(axis.tag) ? AxisValue(tag: axis.tag, value: axisValues[axis.tag] ?? axis.defaultValue) : nil
        }
        equivalence.variableInstance = instance
        commit()
    }

    func reset() {
        table.resetCustomization(family: family, role: role)
        reload()
        onChange?(table)
    }

    func displayName(ofFont name: String) -> String {
        NSFont(name: name, size: 12)?.displayName ?? name
    }

    private func reload() {
        staticFaces = OpticalFonts.members(ofFamily: family).compactMap { entry in
            guard let name = entry.first as? String, let font = NSFont(name: name, size: 12) else { return nil }
            return FontVariations.isVariable(font as CTFont) ? nil : name
        }
        let query = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        var variables: [String] = []
        for descriptor in CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor] ?? [] {
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            guard FontVariations.isVariable(font) else { continue }
            let name = FontVariations.baseName(of: font)
            if !variables.contains(name) { variables.append(name) }
        }
        variableBases = variables
        equivalence = table.equivalence(family: family, role: role)
        if let instance = equivalence.variableInstance,
           let font = FontVariations.font(named: instance.fontName, size: 12, preferringVariable: true) {
            axes = FontVariations.axes(of: font).filter { !$0.isHidden }
            axisValues = FontVariations.coordinates(of: font)
            for value in instance.variations { axisValues[value.tag] = value.value }
            fixedAxes = Set(instance.variations.map(\.tag))
        } else {
            axes = []; axisValues = [:]; fixedAxes = []
        }
    }

    private func commit() {
        table.customize(family: family, role: role, to: equivalence)
        onChange?(table)
    }
}

/// Impostazioni › Fonts.
struct FontsSettingsView: View {
    @ObservedObject var model: FontRoleSettingsModel
    @State private var groupsFamilies = FontMenuPreferences.groupsFamilies

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Group families in font menus", isOn: Binding(
                        get: { groupsFamilies },
                        set: { groupsFamilies = $0; FontMenuPreferences.groupsFamilies = $0 }))
                    Text("Families that start with the same word (Noto Sans, Noto Serif…) go into a submenu named after that word.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("Typographic Equivalences")
                    .font(.headline)
                FontRoleSettingsView(model: model)
            }
            .padding(20)
        }
        .frame(minWidth: 590, minHeight: 420)
    }
}

struct FontRoleSettingsView: View {
    @ObservedObject var model: FontRoleSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Family", selection: Binding(get: { model.family }, set: model.selectFamily)) {
                    ForEach(model.families, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: .infinity)
                Picker("Role", selection: Binding(get: { model.role }, set: model.selectRole)) {
                    ForEach(FontRole.allCases, id: \.self) { role in
                        Text(title(of: role)).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    Text("Static").foregroundStyle(.secondary)
                    Picker("Static face", selection: Binding(get: { model.equivalence.staticFace ?? "" }, set: model.chooseStatic)) {
                        Text("None").tag("")
                        ForEach(model.staticFaces, id: \.self) { name in
                            Text(model.displayName(ofFont: name)).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Variable").foregroundStyle(.secondary)
                    Picker("Variable font", selection: Binding(get: { model.equivalence.variableInstance?.fontName ?? "" }, set: model.chooseVariableBase)) {
                        Text("None").tag("")
                        ForEach(model.variableBases, id: \.self) { name in
                            Text(model.displayName(ofFont: name)).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !model.axes.isEmpty {
                Divider()
                ForEach(model.axes) { axis in
                    HStack(spacing: 10) {
                        Toggle(axis.name.isEmpty ? axis.tag : axis.name, isOn: Binding(
                            get: { model.fixedAxes.contains(axis.tag) },
                            set: { model.setAxis(axis.tag, value: $0 ? (model.axisValues[axis.tag] ?? axis.defaultValue) : nil) }
                        ))
                        .fixedSize()
                        Slider(value: Binding(get: { model.axisValues[axis.tag] ?? axis.defaultValue },
                                              set: { model.setAxis(axis.tag, value: $0) }), in: axis.minimum...axis.maximum)
                            .disabled(!model.fixedAxes.contains(axis.tag))
                        Text(model.axisValues[axis.tag] ?? axis.defaultValue, format: .number.precision(.fractionLength(0...2)))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Spacer(minLength: 0)
            HStack {
                Button("Automatic", action: model.reset)
                    .disabled(!model.isCustomized)
                    .help("Restore only this family–role pair")
                Spacer()
                if model.onApply != nil {
                    Button("Reapply to Document") { model.onApply?() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 590, minHeight: model.axes.isEmpty ? 175 : 260)
        .themed()
    }

    private func title(of role: FontRole) -> String {
        switch role {
        case .regular: "Regular"
        case .italic: "Italic"
        case .bold: "Bold"
        case .boldItalic: "Bold Italic"
        }
    }
}
