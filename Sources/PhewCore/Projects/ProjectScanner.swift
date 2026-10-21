import Foundation

public struct SkippedArtifact: Sendable, Equatable {
    public let url: URL
    public let reason: String
}

public struct ProjectScan: Sendable {
    public let items: [Item]
    public let skipped: [SkippedArtifact]
    public let unreadable: [URL]
}

public struct ProjectScanner: Sendable {
    let roots: [URL]
    let dormantDays: Int
    let now: Date

    public init(roots: [URL], dormantDays: Int, now: Date = .now) {
        self.roots = roots
        self.dormantDays = dormantDays
        self.now = now
    }

    public func scan() async -> ProjectScan {
        let walk = ProjectWalker.walk(roots: roots)
        // What would be deleted per artifact, before the git check.
        var candidates: [(FoundProject, FoundArtifact, [URL])] = []
        var skippedRepos: [SkippedArtifact] = []
        for project in walk.projects {
            for artifact in project.artifacts {
                let urls: [URL]
                if !artifact.files.isEmpty {
                    urls = artifact.files
                } else if artifact.contents {
                    // Laravel ships tracked .gitignore files in these folders; never delete them.
                    urls = ((try? FileManager.default.contentsOfDirectory(at: artifact.url, includingPropertiesForKeys: nil)) ?? [])
                        .map(\.standardizedFileURL)
                        .filter { $0.lastPathComponent != ".gitignore" }
                } else {
                    // Deleting a dependency that is its own git checkout could lose unpushed commits.
                    if let repo = nestedRepo(in: artifact.url) {
                        let rel = repo.path.dropFirst(project.root.standardizedFileURL.path.count + 1)
                        skippedRepos.append(SkippedArtifact(url: artifact.url, reason: "Holds a git repository (\(rel))"))
                        continue
                    }
                    urls = [artifact.url]
                }
                if !urls.isEmpty { candidates.append((project, artifact, urls)) }
            }
        }
        let verdicts = await GitSafety.check(candidates.flatMap(\.2))

        var items: [Item] = []
        var skipped = skippedRepos
        for (project, artifact, urls) in candidates {
            let allowed = urls.filter { verdicts[$0] == .allowed }
            guard !allowed.isEmpty else {
                let v = urls.compactMap { verdicts[$0] }
                let reason = v.contains(.tracked) ? "Tracked by git"
                    : v.contains(.notIgnored) ? "Not ignored by git" : "Couldn't check git status"
                skipped.append(SkippedArtifact(url: artifact.url, reason: reason))
                continue
            }
            items.append(item(project, artifact, allowed))
        }
        return ProjectScan(items: items, skipped: skipped, unreadable: walk.unreadable)
    }

    /// A `.git` up to four levels down (vendor/org/pkg/.git, node_modules/@scope/pkg/.git).
    // ponytail: depth 4 keeps the check cheap on huge node_modules; deeper checkouts are not seen.
    private func nestedRepo(in folder: URL) -> URL? {
        let base = folder.pathComponents.count
        let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = e?.nextObject() as? URL {
            if url.lastPathComponent == ".git" { return url.deletingLastPathComponent().standardizedFileURL }
            if url.pathComponents.count - base >= 4 { e?.skipDescendants() }
        }
        return nil
    }

    private func item(_ project: FoundProject, _ artifact: FoundArtifact, _ urls: [URL]) -> Item {
        let root = project.root.standardizedFileURL
        let name = root.lastPathComponent
        let relative = String(artifact.url.path.dropFirst(root.path.count + 1))
        let target = PathTarget(
            id: "projects:\(artifact.url.path)", group: "Projects", title: "\(name): \(relative)",
            tier: artifact.tier, paths: [artifact.url.path], contents: artifact.contents || !artifact.files.isEmpty
        )
        // No file date means we can't tell; treat as active so nothing is preselected by accident.
        let dormant = project.lastModified.map { now.timeIntervalSince($0) > Double(dormantDays) * 86_400 } ?? false
        var item = Item(id: target.id, target: target, urls: urls, bytes: DiskSize.allocated(urls).bytes,
                        lastUsed: project.lastModified, state: .ready)
        item.project = ProjectInfo(root: root, name: name, stacks: project.stacks,
                                   lastModified: project.lastModified, dormant: dormant)
        item.preselected = Item.defaultSelection(target) && dormant
        return item
    }
}
