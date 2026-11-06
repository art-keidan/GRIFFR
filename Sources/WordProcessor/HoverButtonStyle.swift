import AppKit
import SwiftUI

/// I pulsanti di SwiftUI con un leggero riscontro al passaggio del mouse, come quelli delle barre.
/// Il pulsante resta quello di sistema (con bordo, prominente, senza bordo, semplice o collegamento): sopra si posa
/// soltanto una velatura azzurra mentre il mouse ci passa, e nessuna se il pulsante è disattivato.
struct HoverButtonStyle: PrimitiveButtonStyle {
    enum Kind { case bordered, prominent, borderless, plain, link }
    var kind: Kind = .bordered

    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration, kind: kind)
    }
}

extension PrimitiveButtonStyle where Self == HoverButtonStyle {
    /// Lo stile dei pulsanti dell'app: quello di sistema scelto con `kind`, più il passaggio del mouse.
    static func hover(_ kind: HoverButtonStyle.Kind = .bordered) -> HoverButtonStyle { HoverButtonStyle(kind: kind) }
}

private struct HoverButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let kind: HoverButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        styled
            .hoverHighlight(hovered && isEnabled, framed: kind == .bordered || kind == .prominent, onAccent: kind == .prominent)
            .onHover { hovered = $0 }
    }

    @ViewBuilder private var styled: some View {
        switch kind {
        case .bordered: Button(configuration).buttonStyle(.bordered)
        case .prominent: Button(configuration).buttonStyle(.borderedProminent)
        case .borderless: Button(configuration).buttonStyle(.borderless)
        case .plain: Button(configuration).buttonStyle(.plain)
        case .link: Button(configuration).buttonStyle(.link)
        }
    }
}

extension View {
    /// La velatura del passaggio del mouse. Su un pulsante con bordo copre la sua scatola; su uno senza bordo (icone,
    /// righe, menu a icona) disegna dietro una scatola tenue poco più grande del segno.
    @ViewBuilder func hoverHighlight(_ on: Bool, framed: Bool, onAccent: Bool = false) -> some View {
        if framed {
            overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onAccent ? Color.white.opacity(0.14) : Color(nsColor: Theme.accent).opacity(0.08))
                    .opacity(on ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.12), value: on)
        } else {
            background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: Theme.accent).opacity(0.10))
                    .padding(-3)
                    .opacity(on ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: on)
        }
    }

    /// Il passaggio del mouse per i controlli che non sono pulsanti, come i menu a icona.
    func hoverable() -> some View { modifier(Hoverable()) }
}

private struct Hoverable: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.hoverHighlight(hovered && isEnabled, framed: false).onHover { hovered = $0 }
    }
}
