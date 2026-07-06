<div align="center">
  <h1>WriteAway</h1>
  <p><em>It's a pain for cross-OS users to work with NTFS based external drives on Mac, and here's the painkiller I built (of course, used Claude...)</em></p>
  <p>
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" />
    <img alt="macOS" src="https://img.shields.io/badge/macOS-13.0+-000000?style=flat-square&logo=apple&logoColor=white" />
    <img alt="GitHub Repo stars" src="https://img.shields.io/github/stars/SauravDS/WriteAway?style=social" />
  </p>
</div>

A lightweight macOS menu bar utility that allows you to **read and write NTFS external drives** on your MacBook natively and securely. It detects plugged-in NTFS volumes and remounts them read/write using the open-source **ntfs-3g** driver via **macFUSE** — effectively bypassing macOS's native read-only limitations.

## Features

- **Auto-Detection** — Instantly detects when NTFS drives are plugged in using zero-overhead macOS notifications.
- **One-Click Read/Write** — Seamlessly remounts drives with full write permissions.
- **Safe Eject** — Unmounts and safely spins down your external drives to prevent data corruption.
- **Toast Notifications** — Non-blocking toast notifications for mount, unmount, and eject events that do not interrupt your workflow.
- **Secure Execution** — All shell commands use proper string escaping and Apple's native `NSAppleScript` bridge to prevent shell-injection vulnerabilities.
- **Diagnostic Logging** — Uses native `os.Logger` so you can view mount logs and diagnose issues directly in the macOS Console.

## 1. Prerequisites (one-time setup)

Install [Homebrew](https://brew.sh) if you don't have it, then install macFUSE and ntfs-3g:

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
3. Reboot your Mac. *(On Apple Silicon you may be asked to enable kernel extensions in Recovery Mode: hold power at startup → Options → Utilities → Startup Security Utility → Reduced Security → check "Allow user management of kernel extensions".)*

Verify the install:

```bash
which ntfs-3g          # should print /opt/homebrew/sbin/ntfs-3g (Apple Silicon)
                       # or /usr/local/sbin/ntfs-3g (Intel)
```

## 2. Build the App

You need Xcode Command Line Tools (`xcode-select --install`). Then use the included build script to generate a proper macOS `.app` bundle:

```bash
cd WriteAway
./scripts/build-app.sh
```

This will create `WriteAway.app` in your project root.

## 3. Run and Install

Double-click `WriteAway.app` to run it, or drag it to your `~/Applications/` folder.

A drive icon appears in your menu bar. Plug in an NTFS drive, click the icon, and choose **Mount Read/Write**. You'll receive the standard macOS admin-password prompt (ntfs-3g must run as root to mount into `/Volumes`).

- **externaldrive ✓** icon — everything writable or no drives attached
- **externaldrive !** icon — an NTFS drive is currently mounted read-only

### Launch at login (optional)

Add `WriteAway.app` in **System Settings → General → Login Items → Open at Login**.

## How it works

1. **Detection** — Combines macOS `NSWorkspace` mount notifications with periodic `diskutil info` polling to detect NTFS filesystems instantly.
2. **Remount** — Unmounts Apple's read-only mount, then safely builds and executes `ntfs-3g` with administrator privileges via `NSAppleScript`.
3. **Eject / Unmount** — Uses `diskutil unmount` and `diskutil eject` to safely detach and power down external physical drives.

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
- **Data safety** — always unmount/eject before unplugging. NTFS write support via ntfs-3g is mature and widely used, but it is still a reverse-engineered driver; keep backups of anything important.

## Project layout

```
WriteAway/
├── Package.swift                       # SwiftPM manifest
├── Info.plist                          # App Bundle metadata
├── scripts/
│   ├── build-app.sh                    # Generates WriteAway.app bundle
│   └── run-tests.sh                    # Custom runner for tests on CLT-only setups
├── Sources/WriteAway/
│   ├── main.swift                      # App bootstrap
│   ├── AppDelegate.swift               # Status item, UI, actions, toasts
│   ├── DriveMonitor.swift              # NTFS volume discovery via diskutil
│   ├── ShellUtility.swift              # Deadlock-free process launching & shell escaping
│   └── Mounter.swift                   # ntfs-3g remount + unmount/eject logic
└── Tests/WriteAwayTests/               # Core logic test suite
```
