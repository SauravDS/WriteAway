import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let monitor = DriveMonitor()
    private let mounter = Mounter()
    private var volumes: [NTFSVolume] = []
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "externaldrive.badge.checkmark",
                accessibilityDescription: "WriteAway"
            )
        }

        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        refresh()

        // Poll for plugged/unplugged drives. diskutil calls are cheap at this cadence.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // Also refresh immediately when macOS reports volume mount/unmount events.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(volumesChanged),
                           name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged),
                           name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc private func volumesChanged() { refresh() }

    private func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let found = self.monitor.scan()
            DispatchQueue.main.async {
                self.volumes = found
                self.updateIcon()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let hasReadOnly = volumes.contains { $0.isMounted && !$0.isWritable }
        let symbol = hasReadOnly
            ? "externaldrive.badge.exclamationmark"
            : "externaldrive.badge.checkmark"
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: "WriteAway")
    }

    // MARK: - Menu construction

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if !mounter.isNTFS3GInstalled {
            let warning = NSMenuItem(
                title: "⚠️ ntfs-3g not installed — see README",
                action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        if volumes.isEmpty {
            let empty = NSMenuItem(title: "No NTFS drives detected",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for (index, volume) in volumes.enumerated() {
            let state: String
            if !volume.isMounted {
                state = "not mounted"
            } else if volume.isWritable {
                state = "read/write ✓"
            } else {
                state = "read-only"
            }

            let header = NSMenuItem(
                title: "\(volume.volumeName) (\(volume.sizeDescription)) — \(state)",
                action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            if !volume.isMounted || !volume.isWritable {
                let mountItem = NSMenuItem(title: "   Mount Read/Write",
                                           action: #selector(mountReadWrite(_:)),
                                           keyEquivalent: "")
                mountItem.target = self
                mountItem.tag = index
                menu.addItem(mountItem)
            }

            if volume.isMounted {
                let openItem = NSMenuItem(title: "   Open in Finder",
                                          action: #selector(openInFinder(_:)),
                                          keyEquivalent: "")
                openItem.target = self
                openItem.tag = index
                menu.addItem(openItem)

                let unmountItem = NSMenuItem(title: "   Unmount",
                                             action: #selector(unmountVolume(_:)),
                                             keyEquivalent: "")
                unmountItem.target = self
                unmountItem.tag = index
                menu.addItem(unmountItem)
            }

            menu.addItem(.separator())
        }

        let refreshItem = NSMenuItem(title: "Refresh",
                                     action: #selector(manualRefresh),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit WriteAway",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func manualRefresh() { refresh() }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let volume = volume(for: sender), let path = volume.mountPoint else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func mountReadWrite(_ sender: NSMenuItem) {
        guard let volume = volume(for: sender) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.mounter.mountReadWrite(volume)
                DispatchQueue.main.async {
                    self.refresh()
                    self.notify(title: "Mounted read/write",
                                text: "\(volume.volumeName) is now writable.")
                }
            } catch MounterError.userCancelled {
                DispatchQueue.main.async { self.refresh() }
            } catch {
                DispatchQueue.main.async {
                    self.refresh()
                    self.showError(error)
                }
            }
        }
    }

    @objc private func unmountVolume(_ sender: NSMenuItem) {
        guard let volume = volume(for: sender) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.mounter.unmount(volume)
                DispatchQueue.main.async {
                    self.refresh()
                    self.notify(title: "Unmounted",
                                text: "\(volume.volumeName) can be unplugged safely.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.refresh()
                    self.showError(error)
                }
            }
        }
    }

    private func volume(for sender: NSMenuItem) -> NTFSVolume? {
        guard sender.tag >= 0, sender.tag < volumes.count else { return nil }
        return volumes[sender.tag]
    }

    // MARK: - Feedback

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "WriteAway"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func notify(title: String, text: String) {
        // Lightweight in-app confirmation; avoids the notification-permission
        // dance that UNUserNotificationCenter requires for unsigned apps.
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
