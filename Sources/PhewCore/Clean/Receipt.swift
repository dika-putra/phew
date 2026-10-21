public struct ReceiptEntry: Sendable, Equatable {
    public let itemID: String
    public let title: String
    public let claimed: Int64
    public let measured: Int64
    public let failures: [String]
    public let skippedReason: String?

    public init(itemID: String, title: String, claimed: Int64, measured: Int64, failures: [String], skippedReason: String?) {
        self.itemID = itemID
        self.title = title
        self.claimed = claimed
        self.measured = measured
        self.failures = failures
        self.skippedReason = skippedReason
    }
}

public struct Receipt: Sendable, Equatable {
    public let entries: [ReceiptEntry]
    public let freeBefore: Int64
    public let freeAfter: Int64

    public init(entries: [ReceiptEntry], freeBefore: Int64, freeAfter: Int64) {
        self.entries = entries
        self.freeBefore = freeBefore
        self.freeAfter = freeAfter
    }

    public var measuredTotal: Int64 { entries.reduce(0) { $0 + $1.measured } }

    /// Entries where what was freed differs from what the scan expected by more than 1 MiB and 5%.
    public var mismatches: [ReceiptEntry] {
        entries.filter { e in
            e.skippedReason == nil && abs(e.claimed - e.measured) > max(1_048_576, e.claimed / 20)
        }
    }
}
