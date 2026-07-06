import AppKit
import Foundation
import os

enum MounterError: LocalizedError {
    case ntfs3gNotFound
    case unmountFailed(String)
    case mountFailed(String)
    case ejectFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .ntfs3gNotFound:
            return "ntfs-3g was not found. Install it with:\n  brew install --cask macfuse\n  brew install gromgit/fuse/ntfs-3g-mac"
        case .unmountFailed(let msg):
            return "Could not unmount the volume: \(msg)"
        case .mountFailed(let msg):
            return "ntfs-3g mount failed: \(msg)"
        case .ejectFailed(let msg):
            return "Could not eject the volume: \(msg)"
        case .userCancelled:
            return "Authentication was cancelled."
        }
    }
}

/// Handles remounting NTFS volumes read/write through ntfs-3g,
/// and unmounting/ejecting them.
final class Mounter {

    private let log = Logger(subsystem: "com.writeaway.app", category: "Mounter")

    /// Candidate install locations for ntfs-3g
    /// (Apple Silicon Homebrew, Intel Homebrew, MacPorts).
    private let ntfs3gCandidates = [
        "/opt/homebrew/sbin/ntfs-3g",
        "/opt/homebrew/bin/ntfs-3g",
        "/usr/local/sbin/ntfs-3g",
        "/usr/local/bin/ntfs-3g",
        "/opt/local/bin/ntfs-3g"
    ]

    var ntfs3gPath: String? {
        ntfs3gCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isNTFS3GInstalled: Bool { ntfs3gPath != nil }

    /// Unmounts the volume (from Apple's read-only driver if currently mounted)
    /// and remounts it read/write with ntfs-3g. Runs the privileged part through
    /// NSAppleScript so the user sees the standard macOS password dialog.
    func mountReadWrite(_ volume: NTFSVolume) throws {
        guard let ntfs3g = ntfs3gPath else { throw MounterError.ntfs3gNotFound }

        // 1. Unmount current (read-only) mount if present. diskutil handles
        //    this without privileges for volumes the user mounted.
        if volume.isMounted {
            let result = Shell.run("/usr/sbin/diskutil", ["unmount", volume.devicePath])
            if !result.succeeded {
                // Fall back to a forced unmount inside the privileged script below.
                Shell.run("/usr/sbin/diskutil", ["unmount", "force", volume.devicePath])
            }
        }

        // 2. Build the privileged mount command.
        //    All user-controlled values go through shellEscape() to prevent injection.
        let safeName = sanitize(volume.volumeName)
        let mountPoint = "/Volumes/\(safeName)"
        let escapedMountPoint = Shell.shellEscape(mountPoint)
        let escapedNtfs3g = Shell.shellEscape(ntfs3g)
        let escapedDevice = Shell.shellEscape(volume.devicePath)

        let options = [
            "local",                              // show as a local disk in Finder
            "allow_other",                        // usable by the logged-in user
            "auto_xattr",                         // extended attributes support
            "windows_names",                      // refuse names invalid on Windows
            "volname=\(safeName)"
        ].joined(separator: ",")

        let script = "/bin/mkdir -p \(escapedMountPoint) && "
            + "\(escapedNtfs3g) \(escapedDevice) \(escapedMountPoint) -o \(options)"

        log.info("Mounting \(volume.volumeName) (\(volume.devicePath)) read/write")
        try runPrivileged(script)
    }

    /// Unmounts a volume (works for both Apple-driver and ntfs-3g mounts).
    func unmount(_ volume: NTFSVolume) throws {
        guard volume.isMounted else { return }
        let result = Shell.run("/usr/sbin/diskutil", ["unmount", volume.devicePath])
        if !result.succeeded {
            // FUSE mounts made by root sometimes need privileged unmount.
            let escapedDevice = Shell.shellEscape(volume.devicePath)
            try runPrivileged("/usr/sbin/diskutil unmount force \(escapedDevice)")
        }
    }
    
    /// Ejects a volume (unmounts all volumes on the physical disk and spins it down).
    func eject(_ volume: NTFSVolume) throws {
        // Find the whole disk device (e.g., "disk4s1" -> "disk4")
        let wholeDisk = volume.deviceID.prefix(while: { $0.isLetter || $0.isNumber && $0 != "s" })
        guard !wholeDisk.isEmpty else { throw MounterError.ejectFailed("Invalid device ID: \(volume.deviceID)") }
        let wholeDiskPath = "/dev/\(wholeDisk)"
        
        let result = Shell.run("/usr/sbin/diskutil", ["eject", wholeDiskPath])
        if !result.succeeded {
            // FUSE mounts might block eject, try privileged unmount first
            try? unmount(volume)
            let secondTry = Shell.run("/usr/sbin/diskutil", ["eject", wholeDiskPath])
            if !secondTry.succeeded {
                throw MounterError.ejectFailed(secondTry.stderr.isEmpty ? "unknown error" : secondTry.stderr)
            }
        }
    }

    // MARK: - Privileged execution

    /// Runs a shell command with administrator privileges via NSAppleScript.
    /// Uses the native AppleScript bridge instead of shelling out to osascript,
    /// which avoids the fragile double-escaping (shell-inside-AppleScript-inside-shell).
    private func runPrivileged(_ shellCommand: String) throws {
        // NSAppleScript handles the AppleScript string escaping for us —
        // we only need to escape for the inner shell context, which is
        // already handled by Shell.shellEscape() at the call sites.
        let source = "do shell script \(appleScriptString(shellCommand)) with administrator privileges"

        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)!
        script.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if errorNumber == -128 {
                throw MounterError.userCancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw MounterError.mountFailed(message)
        }
    }

    // MARK: - Helpers

    /// Formats a Swift string as an AppleScript string literal with proper escaping.
    /// Handles backslashes and double quotes.
    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Keeps volume names safe for mount points and FUSE options.
    /// Only allows alphanumerics and a small set of safe punctuation.
    func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "NTFS Volume" : cleaned
    }
}

