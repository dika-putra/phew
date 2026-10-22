import Foundation

/// SDK versions that projects pin: version -> project folders.
public struct Pins: Sendable, Equatable {
    public var flutter: [String: Set<URL>] = [:]
    public var node: [String: Set<URL>] = [:]
    public var rust: [String: Set<URL>] = [:]
}

public enum PinFinder {
    public static func find(roots: [URL]) -> Pins {
        var pins = Pins()
        for root in roots {
            let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            while let url = e?.nextObject() as? URL {
                let name = url.lastPathComponent
                if ProjectRules.pruned.contains(name) { e?.skipDescendants(); continue }
                let project = url.deletingLastPathComponent().standardizedFileURL
                switch name {
                case ".fvmrc":
                    if let v = jsonString(url, "flutter") { pins.flutter[v, default: []].insert(project) }
                case "fvm_config.json" where project.lastPathComponent == ".fvm":
                    // Legacy file; a set keeps a project with both files counted once.
                    if let v = jsonString(url, "flutterSdkVersion") {
                        pins.flutter[v, default: []].insert(project.deletingLastPathComponent())
                    }
                case ".nvmrc":
                    if let v = firstLine(url) { pins.node[String(v.trimmingPrefix("v")), default: []].insert(project) }
                case "rust-toolchain":
                    if let v = firstLine(url) { pins.rust[v, default: []].insert(project) }
                case "rust-toolchain.toml":
                    if let v = tomlChannel(url) { pins.rust[v, default: []].insert(project) }
                default:
                    break
                }
            }
        }
        return pins
    }

    private static func jsonString(_ url: URL, _ key: String) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object[key] as? String
    }

    private static func firstLine(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
        return line?.isEmpty == false ? line : nil
    }

    private static func tomlChannel(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let match = text.firstMatch(of: /channel\s*=\s*"([^"]+)"/) else { return nil }
        return String(match.1)
    }
}

/// `.nvmrc` matches by version prefix on a dot boundary: "20" matches 20.11.0, not 200.1.0.
/// Aliases such as "lts/*" or "node" never match a specific folder.
public func nodePinMatches(_ pin: String, _ version: String) -> Bool {
    let p = pin.trimmingCharacters(in: .whitespaces).trimmingPrefix("v")
    let v = version.trimmingPrefix("v")
    guard !p.isEmpty, p.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
    return v == p || v.hasPrefix(p + ".")
}
