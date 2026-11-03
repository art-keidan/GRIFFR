import AppKit
import Typesetting

/// La barra di «Cerca e sostituisci», sopra la pagina: il campo di ricerca con le frecce e il conto delle occorrenze,
/// le opzioni, il campo della sostituzione con i suoi due pulsanti, e la chiusura. Invio va all'occorrenza dopo,
/// Maiusc-Invio a quella prima, Esc chiude. Chi la usa riceve le richieste attraverso le chiamate qui sotto.
@MainActor
final class FindBar: NSObject, NSSearchFieldDelegate, NSTextFieldDelegate {
    let searchField = NSSearchField()
    let replaceField = NSTextField()
    let countLabel = BandLabel(labelWithString: "")
    private(set) var view: BandView!

    /// Il testo da cercare o le opzioni sono cambiati.
    var onChange: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?

    private(set) var options = TextSearch.Options()
    var query: String { searchField.stringValue }
    var template: String { replaceField.stringValue }

    override init() {
        super.init()
        searchField.placeholderString = "Cerca"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.font = Theme.font
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replaceField.placeholderString = "Sostituisci con"
        replaceField.delegate = self
        replaceField.font = Theme.font
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        countLabel.font = Theme.smallFont
        countLabel.textColor = Theme.secondary
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.widthAnchor.constraint(equalToConstant: 88).isActive = true

        let previous = BandButton(symbol: "chevron.up", help: "Occorrenza precedente (Maiusc-Invio, Maiusc-⌘G)", target: self, action: #selector(previousPressed))
        let next = BandButton(symbol: "chevron.down", help: "Occorrenza successiva (Invio, ⌘G)", target: self, action: #selector(nextPressed))
        let optionMenu = BandPopUp(width: 42, pullsDown: true, help: "Opzioni di ricerca")
        optionMenu.fixedTitle = ""
        optionMenu.symbolImage = Theme.symbol("slider.horizontal.3", "Opzioni di ricerca")
        optionMenu.attachFiller { [weak self] menu in
            guard let self else { return }
            for (index, title, help) in Self.optionTitles {
                let item = menu.addItem(withTitle: title, action: #selector(self.optionPressed(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.toolTip = help
                item.state = self.optionIsOn(index) ? .on : .off
                item.isEnabled = index != 3 || !self.options.isPattern
            }
        }
        let replace = BandButton(label: "Sostituisci", help: "Sostituisce l'occorrenza scelta e va alla successiva", target: self, action: #selector(replacePressed))
        let replaceAll = BandButton(label: "Tutti", help: "Sostituisce tutte le occorrenze (un passo solo di Annulla)", target: self, action: #selector(replaceAllPressed))
        let close = BandButton(symbol: "xmark", help: "Chiudi la ricerca (Esc)", target: self, action: #selector(closePressed))
        view = Bands.band([searchField, previous, next, countLabel, Bands.separator(), optionMenu,
                           Bands.spacer(), replaceField, replace, replaceAll, Bands.separator(), close], height: 34)
        view.fill = Theme.side
    }

    private static let optionTitles = [(0, "Aa · Maiuscole e minuscole", "Maiuscole e minuscole contano"),
                                       (1, "Parola intera", "Solo parole intere"),
                                       (2, "Modello", "Espressione regolare; nella sostituzione $1, $2… sono i gruppi"),
                                       (3, "Ignora i segni", "«e» trova anche é, è, ē, ἐ… (non con il modello)")]

    private func optionIsOn(_ index: Int) -> Bool {
        switch index {
        case 0: options.matchesCase
        case 1: options.wholeWords
        case 2: options.isPattern
        default: options.ignoresDiacritics
        }
    }

    /// Accende o spegne un'opzione (anche dalle prove): 0 maiuscole, 1 parola intera, 2 modello, 3 segni.
    func setOption(_ index: Int, _ on: Bool) {
        switch index {
        case 0: options.matchesCase = on
        case 1: options.wholeWords = on
        case 2: options.isPattern = on
        case 3: options.ignoresDiacritics = on
        default: return
        }
        onChange?()
    }

    @objc private func optionPressed(_ sender: NSMenuItem) {
        setOption(sender.tag, !optionIsOn(sender.tag))
    }

    @objc private func previousPressed() { onPrevious?() }
    @objc private func nextPressed() { onNext?() }
    @objc private func replacePressed() { onReplace?() }
    @objc private func replaceAllPressed() { onReplaceAll?() }
    @objc private func closePressed() { onClose?() }

    /// Il conto accanto alle frecce: «3 di 12», «12 occorrenze», «Nessuna», o un avviso.
    func showCount(_ text: String, warning: Bool = false) {
        countLabel.stringValue = text
        countLabel.textColor = warning ? Theme.warn : Theme.secondary
    }

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === searchField { onChange?() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === searchField {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() } else { onNext?() }
            } else {
                onReplace?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
