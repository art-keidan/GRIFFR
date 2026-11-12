import AppKit

/// L'identità salvata sul richiamo di un flottante. L'etichetta serve a sceglierlo.
public struct FloatingIdentity: Equatable, Sendable {
    public let id: UUID
    public var label: String?

    public init(id: UUID = UUID(), label: String? = nil) {
        self.id = id
        self.label = label
    }

    public var encoded: String { id.uuidString + (label.map { "\n" + $0 } ?? "") }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "\n", maxSplits: 1)
        guard let first = parts.first, let id = UUID(uuidString: String(first)) else { return nil }
        self.init(id: id, label: parts.count == 2 ? String(parts[1]) : nil)
    }

    public static func validLabel(_ label: String) -> Bool {
        !label.isEmpty && label == label.trimmingCharacters(in: .whitespacesAndNewlines) && !label.contains(where: \.isNewline)
    }

    public static func at(_ location: Int, in text: NSAttributedString) -> Self? {
        guard let encoded = text.attribute(.floatingIdentity, at: location, effectiveRange: nil) as? String else { return nil }
        return Self(encoded: encoded)
    }

    public static func occurrences(in text: NSAttributedString) -> [(location: Int, identity: Self)] {
        var result: [(Int, Self)] = []
        text.enumerateAttribute(.floatingIdentity, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let identity = (value as? String).flatMap(Self.init(encoded:)) else { return }
            for location in range.location..<NSMaxRange(range) where TextStyling.isNoteAnchor(in: text, at: location) {
                result.append((location, identity))
            }
        }
        return result
    }

    static func identifyMissing(in text: NSMutableAttributedString) {
        var locations: [Int] = []
        text.enumerateAttribute(.footnote, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value != nil else { return }
            for location in range.location..<NSMaxRange(range)
                where TextStyling.isNoteAnchor(in: text, at: location) && at(location, in: text) == nil {
                locations.append(location)
            }
        }
        for location in locations {
            text.addAttribute(.floatingIdentity, value: Self().encoded, range: NSRange(location: location, length: 1))
        }
    }

    /// Copia o sposta le occorrenze del frammento e riscrive i rimandi nello stesso frammento.
    public static func preparePaste(_ fragment: NSMutableAttributedString, into destination: NSAttributedString,
                                    sameDocument: Bool, moving: Set<UUID> = []) {
        let current = occurrences(in: destination)
        let occupied = Set(current.map { $0.identity.id })
        var labels = Set(current.compactMap { $0.identity.label })
        var mapping: [UUID: UUID] = [:]
        for (location, identity) in occurrences(in: fragment) {
            let keep = sameDocument && moving.contains(identity.id) && !occupied.contains(identity.id)
            let id = keep ? identity.id : UUID()
            mapping[identity.id] = id
            var label = identity.label
            if let original = label {
                var index = 2
                while let value = label, !labels.insert(value).inserted {
                    label = "\(original) (\(index))"
                    index += 1
                }
            }
            fragment.addAttribute(.floatingIdentity, value: Self(id: id, label: label).encoded, range: NSRange(location: location, length: 1))
        }
        var changes: [(NSRange, ObjectReference)] = []
        fragment.enumerateAttribute(.field, in: NSRange(location: 0, length: fragment.length)) { value, range, _ in
            // Un rimando a una nota dichiarata punta a un'occorrenza, non a un oggetto copiato: resta com'è.
            guard let encoded = value as? String, case .reference(var reference)? = Field(encoded: encoded),
                  reference.declaredNote == nil else { return }
            if let id = mapping[reference.target] {
                reference.target = id
            } else if !sameDocument {
                let missing = UUID()
                mapping[reference.target] = missing
                reference.target = missing
            }
            changes.append((range, reference))
        }
        for (range, reference) in changes {
            fragment.addAttribute(.field, value: Field.reference(reference).encoded, range: range)
        }
        identifyMissing(in: fragment)
    }
}

public struct ObjectReference: Hashable, Sendable {
    public enum Reading: String, CaseIterable, Sendable {
        case number, page
        public var title: String { self == .number ? "Number" : "Page" }
    }

    public var target: UUID
    public var reading: Reading
    /// Per un rimando a una nota dichiarata da uno stile: la sua occorrenza (capoverso, stile, dichiarazione); `target` è
    /// allora l'identità della dichiarazione. `nil` per un rimando a un flottante con la sua identità (`FloatingIdentity`).
    public var declaredNote: DeclaredNoteSlot?

    public init(target: UUID, reading: Reading = .number) {
        self.target = target
        self.reading = reading
    }

    /// Un rimando a una nota dichiarata.
    public init(declaredNote: DeclaredNoteSlot, reading: Reading = .number) {
        self.target = declaredNote.declaration
        self.reading = reading
        self.declaredNote = declaredNote
    }

    /// Lo stesso rimando con lo stile dichiarante rinominato (`nil` se il rimando non ne ha uno da rinominare).
    func renamingDeclaringStyle(_ renames: [String: String?]) -> ObjectReference? {
        guard var slot = declaredNote, let renamed = renames[slot.declaringStyle], let new = renamed else { return nil }
        slot.declaringStyle = new
        var reference = self
        reference.declaredNote = slot
        return reference
    }

    /// I rimandi a note dichiarate di uno stile rinominato seguono il nome nuovo; quelli di uno stile tolto restano (e
    /// leggono «(??)»: la loro nota non c'è più).
    public static func renameDeclaringStyles(in text: NSMutableAttributedString, _ renames: [String: String?]) {
        guard !renames.isEmpty, text.length > 0 else { return }
        var changes: [(NSRange, Field)] = []
        text.enumerateAttribute(.field, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let encoded = value as? String, case .reference(let reference)? = Field(encoded: encoded),
                  let renamed = reference.renamingDeclaringStyle(renames) else { return }
            changes.append((range, .reference(renamed)))
        }
        for (range, field) in changes { text.addAttribute(.field, value: field.encoded, range: range) }
    }
}

extension NSAttributedString.Key {
    public static let floatingIdentity = Self("WordProcessorFloatingIdentity")
    public static let paragraphIdentity = Self("WordProcessorParagraphIdentity")
    static let finalParagraphIdentity = Self("WordProcessorFinalParagraphIdentity")
}

extension DocumentLayout {
    func values(for references: Set<ObjectReference>) -> [ObjectReference: String] {
        guard !references.isEmpty else { return [:] }
        let locations = Dictionary(FloatingIdentity.occurrences(in: text).map { ($0.identity.id, $0.location) },
                                   uniquingKeysWith: { first, _ in first })
        return Dictionary(uniqueKeysWithValues: references.map { reference in
            if let slot = reference.declaredNote {
                // La nota dichiarata presentata con quell'occorrenza; sospesa o tolta, il rimando non ha valore.
                guard let note = declaredNotes.first(where: {
                    $0.paragraphID == slot.paragraph && $0.declaringStyle == slot.declaringStyle && $0.declaration == slot.declaration
                }) else { return (reference, "(??)") }
                switch reference.reading {
                case .number: return (reference, note.mark)
                case .page:
                    let index = locatedLine(for: note.position, affinity: .upstream)?.page
                    return (reference, index.map { pages[$0].number } ?? "")
                }
            }
            guard let anchor = locations[reference.target] else { return (reference, "(??)") }
            switch reference.reading {
            case .number:
                return (reference, noteMarks[anchor] ?? "")
            case .page:
                let placed = pages.firstIndex { page in
                    page.images.contains { $0.floatingAnchor == anchor }
                        || page.lines.contains { $0.noteRange?.location == anchor + 1 }
                }
                let index = placed ?? locatedLine(for: anchor, affinity: .downstream)?.page
                return (reference, index.map { pages[$0].number } ?? "")
            }
        })
    }

    public func referenceValue(_ reference: ObjectReference) -> String {
        values(for: [reference])[reference] ?? "(??)"
    }
}
