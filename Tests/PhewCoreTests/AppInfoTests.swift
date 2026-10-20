import Testing
@testable import PhewCore

@Test func versionStringIncludesRepo() {
    #expect(AppInfo.version.split(separator: ".").count == 3)
    #expect(AppInfo.versionLine == "phew \(AppInfo.version) (https://github.com/dika-putra/phew)")
}
