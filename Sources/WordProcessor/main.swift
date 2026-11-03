import AppKit

let application = NSApplication.shared
// Il primo controller creato diventa quello condiviso: va istanziato prima dell'avvio.
_ = DocumentController()
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
