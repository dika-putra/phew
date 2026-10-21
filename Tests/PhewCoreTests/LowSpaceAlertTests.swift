import Testing
@testable import PhewCore

private let GB: Int64 = 1_000_000_000
private let on = LowSpaceAlert(enabled: true, thresholdGB: 20)

private func run(_ values: [Int64], _ settings: LowSpaceAlert = on) -> [Bool] {
    var s = LowSpaceAlertState()
    return values.map { s.shouldNotify(available: $0 * GB, settings: settings) }
}

@Test func notifiesOnceBelowThreshold() {
    #expect(run([19, 19]) == [true, false])
}

@Test func rearmsAboveHysteresis() {
    #expect(run([19, 24, 19, 26, 19]) == [true, false, false, false, true])
}

@Test func disabledNeverNotifies() {
    #expect(run([1], LowSpaceAlert(enabled: false, thresholdGB: 20)) == [false])
}
