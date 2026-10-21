import Foundation

public struct FoundArtifact: Sendable, Equatable {
    public let url: URL
    public let tier: Tier
    public let contents: Bool
    /// Only for `files(in:suffix:)` artifacts: the files to delete.
    public let files: [URL]
}

public struct FoundProject: Sendable {
    public let root: URL
    public var stacks: [String]
    public var artifacts: [FoundArtifact]
    public var lastModified: Date?
}

public struct WalkResult: Sendable {
    public let projects: [FoundProject]
    public let unreadable: [URL]
}

public enum ProjectWalker {
    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]

    /// One pass over the roots. Every rule is evaluated on every folder; artifacts of nested
    /// projects (a Flutter app's ios/Pods) join the outermost project.
    public static func walk(roots: [URL]) -> WalkResult {
        var projects: [FoundProject] = []
        var unreadable: [URL] = []
        let fm = FileManager.default

        for root in roots.map(\.standardizedFileURL) {
            var artifactPaths = Set<String>()
            // Folders whose Python rule asks for recursive __pycache__ collection.
            var recursiveOwners: [(folder: [String], name: String, tier: Tier)] = []
            var failed: [URL] = []
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { url, _ in
                failed.append(url)
                return true
            }) else { continue }

            func projectIndex(for components: [String]) -> Int? {
                projects.firstIndex { components.starts(with: $0.root.pathComponents) }
            }

            func visit(_ url: URL, depthRoot: Bool) {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else {
                    if !depthRoot { e.skipDescendants() }
                    return
                }
                let components = url.pathComponents
                if v.isDirectory != true {
                    if let i = projectIndex(for: components), let date = v.contentModificationDate {
                        projects[i].lastModified = max(projects[i].lastModified ?? date, date)
                    }
                    return
                }
                let name = url.lastPathComponent
                if !depthRoot {
                    if artifactPaths.contains(url.path) || ProjectRules.pruned.contains(name)
                        || fm.fileExists(atPath: url.appending(path: "pyvenv.cfg").path) {
                        e.skipDescendants()
                        return
                    }
                    if let owner = recursiveOwners.first(where: { $0.name == name && components.starts(with: $0.folder) }),
                       let i = projectIndex(for: components) {
                        add(FoundArtifact(url: url, tier: owner.tier, contents: false, files: []), to: i)
                        e.skipDescendants()
                        return
                    }
                }
                let rules = ProjectRules.matching(url)
                guard !rules.isEmpty else { return }
                let i: Int
                if let existing = projectIndex(for: components) {
                    i = existing
                } else {
                    projects.append(FoundProject(root: url, stacks: [], artifacts: [], lastModified: nil))
                    i = projects.count - 1
                }
                for rule in rules {
                    if !projects[i].stacks.contains(rule.stack) { projects[i].stacks.append(rule.stack) }
                    for artifact in rule.artifacts {
                        if case .recursive(let n) = artifact.kind {
                            recursiveOwners.append((components, n, artifact.tier))
                        }
                        for found in resolve(artifact, in: url) { add(found, to: i) }
                    }
                }
            }

            func add(_ artifact: FoundArtifact, to i: Int) {
                guard artifactPaths.insert(artifact.url.path).inserted else { return }
                projects[i].artifacts.append(artifact)
            }

            visit(root, depthRoot: true)
            while let url = e.nextObject() as? URL {
                visit(url.standardizedFileURL, depthRoot: false)
            }
            unreadable += failed.map(\.standardizedFileURL)
        }
        return WalkResult(projects: projects, unreadable: unreadable)
    }

    private static func resolve(_ artifact: Artifact, in folder: URL) -> [FoundArtifact] {
        let fm = FileManager.default
        func isRealDir(_ url: URL) -> Bool {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return v?.isDirectory == true && v?.isSymbolicLink != true
        }
        switch artifact.kind {
        case .folder(let path), .contents(let path):
            let url = folder.appending(path: path).standardizedFileURL
            guard isRealDir(url) else { return [] }
            let contents = if case .contents = artifact.kind { true } else { false }
            return [FoundArtifact(url: url, tier: artifact.tier, contents: contents, files: [])]
        case .files(let path, let suffix):
            let url = folder.appending(path: path).standardizedFileURL
            let files = ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasSuffix(suffix) }
                .map(\.standardizedFileURL)
            return files.isEmpty ? [] : [FoundArtifact(url: url, tier: artifact.tier, contents: false, files: files)]
        case .venvs:
            let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return children.map(\.standardizedFileURL)
                .filter { isRealDir($0) && fm.fileExists(atPath: $0.appending(path: "pyvenv.cfg").path) }
                .map { FoundArtifact(url: $0, tier: artifact.tier, contents: false, files: []) }
        case .recursive:
            return [] // found by the walk itself
        }
    }
}
