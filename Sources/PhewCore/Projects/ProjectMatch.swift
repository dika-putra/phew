/// Resolves `projects`, `projects:<project root>` and `projects:<artifact path>` ids.
public func matchProjectItems(_ ids: [String], in items: [Item]) -> (matched: [Item], unknown: [String]) {
    var matched: [Item] = []
    var unknown: [String] = []
    for id in ids {
        let hits: [Item]
        if id == "projects" {
            hits = items.filter(\.preselected)
        } else {
            let path = String(id.dropFirst("projects:".count))
            // An empty or relative path would match everything below the current folder.
            guard id.hasPrefix("projects:"), path.hasPrefix("/"), path != "/" else {
                unknown.append(id)
                continue
            }
            // Match on a path boundary: /a/web must not match /a/website.
            hits = items.filter { $0.id == id || $0.target.paths[0].hasPrefix(path + "/") }
        }
        if hits.isEmpty { unknown.append(id) }
        for item in hits where !matched.contains(where: { $0.id == item.id }) { matched.append(item) }
    }
    return (matched, unknown)
}
