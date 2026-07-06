import Foundation

/// Represents one NTFS partition on an external drive.
struct NTFSVolume: Equatable {
    let deviceID: String        // e.g. "disk4s1"
    let volumeName: String      // e.g. "MY_PASSPORT"
    let mountPoint: String?     // e.g. "/Volumes/MY_PASSPORT", nil if unmounted
    let isWritable: Bool        // true once mounted through ntfs-3g
    let sizeDescription: String // human-readable size

    var devicePath: String { "/dev/\(deviceID)" }
    var isMounted: Bool { mountPoint != nil }
}

/// Discovers external NTFS partitions by shelling out to `diskutil`.
/// Polling with diskutil is deliberately chosen over DiskArbitration here:
/// it needs no entitlements, and its plist output is a stable public interface.
final class DriveMonitor {

    /// Returns all NTFS partitions on external physical disks.
    func scan() -> [NTFSVolume] {
        guard let listData = Shell.runForData("/usr/sbin/diskutil",
                                              ["list", "-plist", "external", "physical"]),
              let listPlist = try? PropertyListSerialization.propertyList(
                  from: listData, options: [], format: nil) as? [String: Any],
              let wholeDisks = listPlist["AllDisksAndPartitions"] as? [[String: Any]]
        else { return [] }

        var partitionIDs: [String] = []
        for disk in wholeDisks {
            if let partitions = disk["Partitions"] as? [[String: Any]] {
                for p in partitions {
                    if let id = p["DeviceIdentifier"] as? String {
                        partitionIDs.append(id)
                    }
                }
            }
            // A disk formatted without a partition table shows up as the whole disk.
            if disk["Partitions"] == nil,
               let id = disk["DeviceIdentifier"] as? String {
                partitionIDs.append(id)
            }
        }

        return partitionIDs.compactMap { info(for: $0) }
    }

    /// Fetches `diskutil info` for one partition and returns it if it's NTFS.
    private func info(for deviceID: String) -> NTFSVolume? {
        guard let data = Shell.runForData("/usr/sbin/diskutil", ["info", "-plist", deviceID]),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        // FilesystemType is "ntfs" for Apple's driver; for an ntfs-3g (FUSE)
        // mount diskutil reports the personality differently, so also check
        // the volume kind and our own mount marker.
        let fsType = (plist["FilesystemType"] as? String) ?? ""
        let fsName = (plist["FilesystemName"] as? String) ?? ""
        let mountPoint = (plist["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let looksLikeNTFS =
            fsType.lowercased().contains("ntfs") ||
            fsName.lowercased().contains("ntfs") ||
            isNTFS3GMount(deviceID: deviceID, mountPoint: mountPoint)

        guard looksLikeNTFS else { return nil }

        let name = (plist["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? deviceID
        let writable = (plist["WritableVolume"] as? Bool) ?? false
        let size = (plist["TotalSize"] as? Int64).map { formatBytes($0) } ?? "unknown size"

        return NTFSVolume(
            deviceID: deviceID,
            volumeName: name,
            mountPoint: mountPoint,
            isWritable: writable,
            sizeDescription: size
        )
    }

    /// ntfs-3g mounts appear in `mount` output as "<dev> on <path> (... ntfs-3g ...)"
    /// or with fstypename macfuse. Checking `mount` covers volumes diskutil
    /// no longer reports as ntfs once FUSE owns them.
    private func isNTFS3GMount(deviceID: String, mountPoint: String?) -> Bool {
        let result = Shell.run("/sbin/mount")
        guard result.succeeded else { return false }
        for line in result.stdout.split(separator: "\n") {
            if line.contains("/dev/\(deviceID) ") &&
               (line.contains("ntfs-3g") || line.contains("macfuse") || line.contains("osxfuse")) {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
