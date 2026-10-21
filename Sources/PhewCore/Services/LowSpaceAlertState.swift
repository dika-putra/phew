/// Notifies once when free space drops below the threshold, then waits until space is back
/// above threshold + 5 GB, so a disk hovering at the limit does not notify every check.
public struct LowSpaceAlertState: Codable, Sendable, Equatable {
    public var armed = true

    public init() {}

    public mutating func shouldNotify(available: Int64, settings: LowSpaceAlert) -> Bool {
        let gb: Int64 = 1_000_000_000
        let threshold = Int64(settings.thresholdGB) * gb
        if available > threshold + 5 * gb { armed = true }
        guard settings.enabled, armed, available < threshold else { return false }
        armed = false
        return true
    }
}
