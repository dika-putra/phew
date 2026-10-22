import Foundation

/// "1.2GB (35%)" -> 1_200_000_000. Docker prints decimal units.
public func parseDockerSize(_ text: String) -> Int64? {
    guard let match = text.firstMatch(of: /^\s*([0-9.]+)\s*([kKMGT]?B)/), let value = Double(match.1) else { return nil }
    let scale: Double = switch match.2.uppercased() {
    case "B": 1
    case "KB": 1e3
    case "MB": 1e6
    case "GB": 1e9
    default: 1e12
    }
    return Int64((value * scale).rounded())
}

public struct DockerReclaimable: Sendable, Equatable {
    public var images: Int64 = 0
    public var buildCache: Int64 = 0
}

/// Input: `docker system df --format '{{.Type}}\t{{.Reclaimable}}'`. Volumes are ignored on purpose.
public func parseDockerDF(_ text: String) -> DockerReclaimable? {
    var r = DockerReclaimable()
    var found = false
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2, let bytes = parseDockerSize(parts[1]) else { continue }
        switch parts[0] {
        case "Images", "Containers": r.images += bytes; found = true
        case "Build Cache": r.buildCache += bytes; found = true
        default: break
        }
    }
    return found ? r : nil
}

public enum DockerScan: Sendable, Equatable {
    case notInstalled
    /// Docker Desktop is installed but not running: only the disk image size is known.
    case off(diskBytes: Int64)
    case running([Item])
}

public enum Docker {
    static let dfCommand = "docker system df --format '{{.Type}}\t{{.Reclaimable}}'"

    public static func scan(home: URL, run: @Sendable ([String]) async -> ShellResult? = liveRun) async -> DockerScan {
        let raw = home.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        let hasCLI = lastLine(await run(loginShell("command -v docker"))) != nil
        guard hasCLI || FileManager.default.fileExists(atPath: raw.path) else { return .notInstalled }
        guard hasCLI, lastLine(await run(loginShell("docker info --format '{{.ServerVersion}}'"))) != nil else {
            // Docker.raw is sparse: its apparent size is the VM disk limit, so use the allocated size.
            return .off(diskBytes: DiskSize.allocated(raw).bytes)
        }
        guard let output = await run(loginShell(dfCommand)), output.status == 0,
              let df = parseDockerDF(output.stdout) else { return .running([]) }
        return .running([
            item("docker.buildcache", "Docker build cache", .regenerates, df.buildCache,
                 [.run(loginShell("docker builder prune -a -f"))]),
            // Locally built images can't be pulled again, so this is data loss. Volumes are never pruned.
            item("docker.images", "Docker images and stopped containers", .dataLoss, df.images,
                 [.run(loginShell("docker container prune -f")), .run(loginShell("docker image prune -a -f"))]),
        ])
    }

    /// Reclaimable bytes for one Docker item now, for measuring a clean.
    public static func reclaimable(for itemID: String, run: @Sendable ([String]) async -> ShellResult? = liveRun) async -> Int64? {
        guard let output = await run(loginShell(dfCommand)), output.status == 0,
              let df = parseDockerDF(output.stdout) else { return nil }
        return itemID == "docker.buildcache" ? df.buildCache : df.images
    }

    private static func item(_ id: String, _ title: String, _ tier: Tier, _ bytes: Int64, _ steps: [Step]) -> Item {
        let target = PathTarget(id: id, group: "Docker", title: title, tier: tier, paths: [])
        var item = Item(id: id, target: target, urls: [], bytes: bytes, lastUsed: nil, state: .ready)
        item.removal = .steps(steps)
        item.measure = .docker
        return item
    }
}
