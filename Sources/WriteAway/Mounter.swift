import Foundation

enum MounterError: LocalizedError {
    case ntfs3gNotFound
    case unmountFailed(String)
    case mountFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .ntfs3gNotFound:
            return "ntfs-3g was not found. Install it with:\n  brew install --cask macfuse\n  brew install gromgit/fuse/ntfs-3g-mac"
        case .unmountFailed(let msg):
            return "Could not unmount the volume: \(msg)"
        case .mountFailed(let msg):
            return "ntfs-3g mount failed: \(msg)"
        case .userCancelled:
            return "Authentication was cancelled."
        }
    }
}

/// Handles remounting NTFS volumes read/write through ntfs-3g,
/// and unmounting/ejecting them.
final class Mounter {

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
    /// an osascript administrator prompt, so the user sees the standard
    /// macOS password dialog.
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

        // 2. Build the privileged mount script.
        let mountPoint = "/Volumes/\(sanitize(volume.volumeName))"
        let options = [
            "local",                              // show as a local disk in Finder
            "allow_other",                        // usable by the logged-in user
            "auto_xattr",                         // extended attributes support
            "windows_names",                      // refuse names invalid on Windows
            "volname=\(sanitize(volume.volumeName))"
        ].joined(separator: ",")

        let script = """
        /bin/mkdir -p '\(mountPoint)' && \
        '\(ntfs3g)' '\(volume.devicePath)' '\(mountPoint)' -o \(options)
        """

        try runPrivileged(script)
    }

    /// Unmounts a volume (works for both Apple-driver and ntfs-3g mounts).
    func unmount(_ volume: NTFSVolume) throws {
        guard volume.isMounted else { return }
        let result = Shell.run("/usr/sbin/diskutil", ["unmount", volume.devicePath])
        if !result.succeeded {
            // FUSE mounts made by root sometimes need privileged unmount.
            try runPrivileged("/usr/sbin/diskutil unmount force '\(volume.devicePath)'")
        }
    }

    // MARK: - Privileged execution

    /// Runs a shell command with administrator privileges via osascript.
    /// This shows the standard macOS authentication dialog.
    private func runPrivileged(_ shellCommand: String) throws {
        // Escape for embedding inside an AppleScript double-quoted string.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        let result = Shell.run("/usr/bin/osascript", ["-e", appleScript])

        if !result.succeeded {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("-128") { // User canceled
                throw MounterError.userCancelled
            }
            throw MounterError.mountFailed(stderr.isEmpty ? "unknown error" : stderr)
        }
    }

    // MARK: - Helpers

    /// Keeps volume names safe to embed in shell single quotes and mount options.
    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "NTFS Volume" : cleaned
    }
}

