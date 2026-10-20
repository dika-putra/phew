public enum Tier: String, Codable, Sendable, CaseIterable {
    case regenerates, redownload, dataLoss
}

public enum Flag: String, Codable, Sendable {
    case heavy, needsAdmin, needsFDA, optIn
}
