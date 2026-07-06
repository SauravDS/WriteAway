import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu bar app: no Dock icon, no main window.
app.setActivationPolicy(.accessory)

app.run()
