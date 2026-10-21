import Foundation

public enum GitVerdict: Sendable, Equatable {
    case allowed
    case tracked
    case notIgnored
    case unknown
}

/// Inside a git repo, a path may be deleted only when git ignores it and it holds no tracked file.
public enum GitSafety {
    public static func check(_ urls: [URL]) async -> [URL: GitVerdict] {
        var verdicts: [URL: GitVerdict] = [:]
        var byRepo: [URL: [URL]] = [:]
        for url in urls {
            if let repo = repoRoot(of: url) {
                byRepo[repo, default: []].append(url)
            } else {
                verdicts[url] = .allowed
            }
        }
        for (repo, members) in byRepo {
            let result = await check(members, in: repo)
            verdicts.merge(result) { _, new in new }
        }
        return verdicts
    }

    private static func repoRoot(of url: URL) -> URL? {
        var dir = url.standardizedFileURL.deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: ".git").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private static func check(_ urls: [URL], in repo: URL) async -> [URL: GitVerdict] {
        let unknown = Dictionary(uniqueKeysWithValues: urls.map { ($0, GitVerdict.unknown) })
        let prefix = repo.standardizedFileURL.path + "/"
        let relative = urls.map { String($0.standardizedFileURL.path.dropFirst(prefix.count)) }
        // Absolute path: /bin/sh in a GUI app does not get Homebrew's PATH.
        guard let git = Shell.which("git")?.path else { return unknown }

        let input = FileManager.default.temporaryDirectory.appending(path: "phew-git-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: input) }
        do {
            try Data(relative.joined(separator: "\0").utf8).write(to: input)
            let ignored = try await Shell.run(
                "/bin/sh", ["-c", "\"$2\" -C \"$0\" check-ignore -z --stdin < \"$1\"", repo.path, input.path, git])
            // check-ignore: 0 = some ignored, 1 = none ignored, anything else is an error.
            guard ignored.status == 0 || ignored.status == 1 else { return unknown }
            let tracked = try await Shell.run(git, ["-C", repo.path, "--literal-pathspecs", "ls-files", "-z", "--"] + relative)
            guard tracked.status == 0 else { return unknown }

            let ignoredSet = Set(ignored.stdout.split(separator: "\0").map(String.init))
            let trackedFiles = tracked.stdout.split(separator: "\0").map(String.init)
            var verdicts: [URL: GitVerdict] = [:]
            for (url, rel) in zip(urls, relative) {
                if trackedFiles.contains(where: { $0 == rel || $0.hasPrefix(rel + "/") }) {
                    verdicts[url] = .tracked
                } else if !ignoredSet.contains(rel) {
                    verdicts[url] = .notIgnored
                } else {
                    verdicts[url] = .allowed
                }
            }
            return verdicts
        } catch {
            return unknown
        }
    }
}
