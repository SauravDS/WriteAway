# WriteAway

*Plug in an NTFS drive and write away — right away.*

A small macOS menu bar app that lets you **read and write NTFS external drives** on your MacBook. It detects plugged-in NTFS volumes and remounts them read/write using the open-source **ntfs-3g** driver via **macFUSE** — the same approach used by tools like Mounty and Paragon alternatives.

macOS mounts NTFS drives **read-only** out of the box. This app unmounts Apple's read-only mount and remounts the volume through ntfs-3g so you can copy files onto the drive.

## 1. Prerequisites (one-time setup)

Install [Homebrew](https://brew.sh) if you don't have it, then:

```bash
# macFUSE (kernel/system extension that lets user-space filesystems run)
brew install --cask macfuse

# ntfs-3g built for macFUSE
brew tap gromgit/homebrew-fuse
brew install ntfs-3g-mac
```

**Important:** after installing macFUSE you must allow its system extension:

1. Open **System Settings → Privacy & Security**.
2. Under Security you'll see a message that software from *"Benjamin Fleischer"* was blocked — click **Allow**.
3. Reboot your Mac. (On Apple Silicon you may be asked to enable kernel extensions in Recovery Mode: hold the power button at startup → Options → Utilities → Startup Security Utility → Reduced Security → check "Allow user management of kernel extensions".)

Verify the install:

```bash
which ntfs-3g          # should print /opt/homebrew/sbin/ntfs-3g (Apple Silicon)
                       # or /usr/local/sbin/ntfs-3g (Intel)
```

## 2. Build the app

You need Xcode Command Line Tools (`xcode-select --install`). Then:

```bash
cd WriteAway
swift build -c release
```

## 3. Run it

```bash
.build/release/WriteAway
```

A drive icon appears in your menu bar. Plug in an NTFS drive, click the icon, and choose **Mount Read/Write**. You'll get the standard macOS admin-password prompt (ntfs-3g must run as root to mount into `/Volumes`).

- **externaldrive ✓** icon — everything writable or no drives attached
- **externaldrive !** icon — an NTFS drive is currently mounted read-only

### Launch at login (optional)

```bash
mkdir -p ~/Applications/WriteAway
cp .build/release/WriteAway ~/Applications/WriteAway/
```

Then add the binary in **System Settings → General → Login Items → Open at Login**.

### Skip the password prompt (optional)

If you don't want to type your password each time, allow your user to run ntfs-3g without a password. Run `sudo visudo` and add (adjust path for Intel Macs):

```
yourusername ALL=(root) NOPASSWD: /opt/homebrew/sbin/ntfs-3g
```

*(The app currently uses the macOS admin dialog; this sudoers rule is useful if you later switch the mount call to `sudo ntfs-3g ...`.)*

## How it works

1. **Detection** — polls `diskutil list -plist external physical` and `diskutil info -plist <partition>` every 5 seconds (plus instant refresh on macOS mount/unmount notifications) and filters for NTFS filesystems.
2. **Remount** — unmounts Apple's read-only mount with `diskutil unmount`, then runs `ntfs-3g /dev/diskXsY /Volumes/<Name> -o local,allow_other,auto_xattr,windows_names,volname=<Name>` with administrator privileges via the standard macOS auth dialog.
3. **Unmount** — `diskutil unmount` (with a privileged forced fallback for FUSE mounts).

### Mount options used

| Option | Purpose |
|---|---|
| `local` | Volume appears as a local disk in Finder |
| `allow_other` | The logged-in user (not just root) can access files |
| `auto_xattr` | Extended attribute support (Finder metadata) |
| `windows_names` | Blocks filenames that would be invalid on Windows |
| `volname=` | Nice volume name in Finder sidebar |

## Troubleshooting

- **"ntfs-3g not installed" in the menu** — the app checks Homebrew/MacPorts paths; run the install steps above.
- **Mount fails with "macFUSE file system is not available"** — the macFUSE system extension wasn't approved; redo step 1 and reboot.
- **Drive won't unmount** — some app (Finder window, Terminal cd'd into it, Spotlight indexing) is using it. Close them or use the forced unmount the app falls back to.
- **Data safety** — always unmount before unplugging. NTFS write support via ntfs-3g is mature and widely used, but it is still a reverse-engineered driver; keep backups of anything important.

## Project layout

```
WriteAway/
├── Package.swift                       # SwiftPM manifest (no Xcode project needed)
└── Sources/WriteAway/
    ├── main.swift                      # App bootstrap (menu-bar-only app)
    ├── AppDelegate.swift               # Status item, menu, actions
    ├── DriveMonitor.swift              # NTFS volume discovery via diskutil
    └── Mounter.swift                   # ntfs-3g remount + unmount logic
```
