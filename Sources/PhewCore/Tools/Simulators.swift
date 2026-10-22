import Foundation

public struct Runtime: Sendable, Equatable {
    public let uuid: String
    public let build: String
    public let version: String
    public let identifier: String
    public let sizeBytes: Int64
    public let lastUsed: Date?
    public let booted: Int

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-5" -> "iOS".
    public var platform: String {
        identifier.split(separator: ".").last.flatMap { $0.split(separator: "-").first }.map(String.init) ?? "Simulator"
    }
}

private func parseDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    let f = ISO8601DateFormatter()
    if let d = f.date(from: text) { return d }
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: text)
}

struct DeviceList: Decodable {
    struct Device: Decodable {
        let udid: String
        let state: String
        let isAvailable: Bool
        let dataPath: String?
    }
    let devices: [String: [Device]]
}

/// Runtimes from `simctl runtime list -j`, with the booted simulator count per runtime from
/// `simctl list devices -j`. Sizes come from simctl, never from du: the runtime folders are
/// mounted disk images and du counts them again.
public func parseRuntimes(runtimesJSON: Data, devicesJSON: Data) -> [Runtime] {
    guard let raw = try? JSONSerialization.jsonObject(with: runtimesJSON) as? [String: [String: Any]] else { return [] }
    let devices = (try? JSONDecoder().decode(DeviceList.self, from: devicesJSON))?.devices ?? [:]
    return raw.map { uuid, r in
        let identifier = r["runtimeIdentifier"] as? String ?? ""
        return Runtime(uuid: uuid, build: r["build"] as? String ?? "", version: r["version"] as? String ?? "",
                       identifier: identifier, sizeBytes: (r["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                       lastUsed: parseDate(r["lastUsedAt"] as? String),
                       booted: devices[identifier]?.filter { $0.state == "Booted" }.count ?? 0)
    }
    .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
}

private let xcrun = "/usr/bin/xcrun"
public let dyldRoot = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld")

public enum Simulators {
    public static func items(run: @Sendable ([String]) async -> ShellResult? = liveRun,
                             dyldRoot root: URL = dyldRoot) async -> [Item] {
        var items: [Item] = []
        let devicesOut = await run([xcrun, "simctl", "list", "devices", "-j"])
        let runtimesOut = await run([xcrun, "simctl", "runtime", "list", "-j"])
        let devicesJSON = Data((devicesOut?.status == 0 ? devicesOut?.stdout : nil)?.utf8 ?? "".utf8)
        let unavailable = ((try? JSONDecoder().decode(DeviceList.self, from: devicesJSON))?.devices.values
            .flatMap { $0 } ?? []).filter { !$0.isAvailable }
        if !unavailable.isEmpty {
            let urls = unavailable.compactMap(\.dataPath).map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            let target = PathTarget(id: "ios.simulators", group: "Xcode", title: "Simulators without a runtime",
                                    tier: .regenerates, paths: urls.map(\.path))
            var item = Item(id: target.id, target: target, urls: urls, bytes: DiskSize.allocated(urls).bytes,
                            lastUsed: nil, state: .ready)
            // CoreSimulator can lag before it marks simulators unavailable, so retry.
            item.removal = .steps([.retry(times: 3, delaySeconds: 3, [xcrun, "simctl", "delete", "unavailable"])])
            items.append(item)
        }
        if let runtimesOut, runtimesOut.status == 0 {
            let byRuntime = (try? JSONDecoder().decode(DeviceList.self, from: devicesJSON))?.devices ?? [:]
            for r in parseRuntimes(runtimesJSON: Data(runtimesOut.stdout.utf8), devicesJSON: devicesJSON) {
                let udids = (byRuntime[r.identifier] ?? []).map(\.udid)
                // A device of this runtime that boots after the scan shows up as a process with its
                // device folder in the command line; checked again before the delete.
                let target = PathTarget(id: "ios.runtimes:\(r.uuid)", group: "Xcode", title: "\(r.platform) \(r.version) runtime",
                                        tier: .redownload, flags: [.heavy], paths: [],
                                        skipIfRunning: udids.map { "proc:Simulator=CoreSimulator/Devices/\($0)/" })
                var item = Item(id: target.id, target: target, urls: [], bytes: r.sizeBytes, lastUsed: r.lastUsed,
                                state: r.booted > 0 ? .inUse(app: "Simulator") : .ready)
                // simctl wants the UUID (or build), not "18.5". Only this runtime's simulators are
                // deleted afterwards, not every unavailable one on the Mac.
                var steps: [Step] = [.run([xcrun, "simctl", "runtime", "delete", r.uuid])]
                if !udids.isEmpty {
                    steps.append(.retry(times: 3, delaySeconds: 3, [xcrun, "simctl", "delete"] + udids))
                    item.note = "Also deletes \(udids.count) simulator\(udids.count == 1 ? "" : "s") of this runtime and their app data"
                }
                item.removal = .steps(steps)
                item.measure = .runtime(uuid: r.uuid)
                items.append(item)
            }
        }
        for build in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for folder in (try? FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? [] {
                // Only per-runtime caches with content: an admin prompt for an empty folder helps no one.
                let bytes = DiskSize.allocated(folder).bytes
                guard folder.lastPathComponent.hasPrefix("com.apple.CoreSimulator.SimRuntime."), bytes > 0 else { continue }
                let target = PathTarget(id: "ios.dyld:\(folder.path)", group: "Xcode", title: dyldTitle(folder.lastPathComponent),
                                        tier: .regenerates, flags: [.needsAdmin], paths: [root.path])
                var item = Item(id: target.id, target: target, urls: [folder], bytes: bytes,
                                lastUsed: nil, state: .ready)
                item.removal = .adminDyld
                items.append(item)
            }
        }
        return items
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-5.22F77" -> "Simulator dyld cache, iOS 18.5 (22F77)".
    static func dyldTitle(_ name: String) -> String {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        guard name.hasPrefix(prefix) else { return "Simulator dyld cache, \(name)" }
        let rest = name.dropFirst(prefix.count)
        guard let dot = rest.lastIndex(of: ".") else { return "Simulator dyld cache, \(rest)" }
        let parts = rest[..<dot].split(separator: "-")
        let runtime = parts.first.map { "\($0) " + parts.dropFirst().joined(separator: ".") } ?? String(rest[..<dot])
        return "Simulator dyld cache, \(runtime) (\(rest[rest.index(after: dot)...]))"
    }

    public static func runtimePresent(_ uuid: String, run: @Sendable ([String]) async -> ShellResult? = liveRun) async -> Bool? {
        guard let out = await run([xcrun, "simctl", "runtime", "list", "-j"]), out.status == 0,
              let raw = try? JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any] else { return nil }
        return raw[uuid] != nil
    }
}

public enum AdminResult: Sendable, Equatable {
    case done
    case cancelled
    case failed(String)
}

/// The root-run delete accepts only folders inside the simulator dyld cache (never the root itself).
public func adminDyldPathsAllowed(_ urls: [URL]) -> Bool {
    let root = dyldRoot.pathComponents
    return !urls.isEmpty && urls.allSatisfy { url in
        let c = url.standardizedFileURL.pathComponents
        return c.count > root.count && c.starts(with: root)
    }
}
