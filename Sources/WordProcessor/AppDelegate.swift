import AppKit
import SwiftUI
import Typesetting

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fontRoleWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        FontLoader.registerAdobeFonts()
        EditorWindowController.addLoremToToolbarOnce()
        EditorWindowController.addSpellingToToolbarOnce()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// GRIFFR › Impostazioni…: le equivalenze appartengono all'applicazione, non al documento aperto.
    @objc func showFontRoleSettings(_ sender: Any?) {
        let target = (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? EditorWindowController
        let model = FontRoleSettingsModel(table: FontRolePreferences.table())
        model.onChange = { FontRolePreferences.save($0) }
        if let target { model.onApply = { [weak target] in target?.reapplyFontRoles() } }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Fonts"
        window.contentView = NSHostingView(rootView: FontsSettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(sender)
        fontRoleWindow = window
    }

    /// Il programma resta aperto anche senza finestre, come le altre applicazioni del Mac.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
