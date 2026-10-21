import Foundation

public struct SizeResult: Sendable, Equatable {
    public var bytes: Int64
    public var unreadable: [URL]
}

public enum DiskSize {
    private static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .fileResourceIdentifierKey, .linkCountKey,
        .isSymbolicLinkKey, .isDirectoryKey, .volumeIdentifierKey,
    ]

    /// Allocated size of a file or folder. Hidden entries are counted, hard links once,
    /// symlinks are not followed and folders on another volume (mounts) are not entered.
    public static func allocated(_ url: URL) -> SizeResult {
        allocated([url])
    }

    /// One hard-link set for all urls, so a file linked under two of them counts once.
    public static func allocated(_ urls: [URL]) -> SizeResult {
        var result = SizeResult(bytes: 0, unreadable: [])
        var seen = Set<NSObject>()
        for url in urls { measure(url, into: &result, seen: &seen) }
        return result
    }

    private static func measure(_ url: URL, into result: inout SizeResult, seen: inout Set<NSObject>) {
        let root: URLResourceValues
        do {
            root = try url.resourceValues(forKeys: Set(keys))
        } catch {
            // Missing is size 0; anything else (permissions, privacy protection) is unreadable.
            if (error as? CocoaError)?.code != .fileReadNoSuchFile { result.unreadable.append(url) }
            return
        }
        if root.isSymbolicLink == true { return }
        let rootVolume = root.volumeIdentifier as? NSObject

        func add(_ v: URLResourceValues) {
            if (v.linkCount ?? 1) > 1, let id = v.fileResourceIdentifier as? NSObject {
                guard seen.insert(id).inserted else { return }
            }
            result.bytes += Int64(v.totalFileAllocatedSize ?? 0)
        }

        guard root.isDirectory == true else {
            add(root)
            return
        }
        var unreadable: [URL] = []
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: []) { failed, _ in
            unreadable.append(failed)
            return true
        }
        while let item = enumerator?.nextObject() as? URL {
            guard let v = try? item.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if let vol = v.volumeIdentifier as? NSObject, let rootVolume, !vol.isEqual(rootVolume) {
                    enumerator?.skipDescendants()
                }
                continue
            }
            add(v)
        }
        result.unreadable += unreadable
    }

    /// Free space as Finder shows it (includes purgeable space macOS can reclaim on demand).
    public static func available(for volume: URL = URL(fileURLWithPath: "/")) -> Int64 {
        let v = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
