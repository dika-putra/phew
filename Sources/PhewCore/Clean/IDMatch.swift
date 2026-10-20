/// Up to three ids that contain the input or share its first dot segment.
public func suggestions(for id: String, in ids: [String]) -> [String] {
    let input = id.lowercased()
    let segment = input.split(separator: ".").first.map(String.init) ?? input
    return Array(ids.filter { candidate in
        let c = candidate.lowercased()
        return c.contains(input) || c.split(separator: ".").first.map(String.init) == segment
    }.prefix(3))
}
