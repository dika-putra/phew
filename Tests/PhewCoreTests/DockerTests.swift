import Foundation
import Testing
@testable import PhewCore

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

@Test func parsesSizes() {
    #expect(parseDockerSize("1.2GB (35%)") == 1_200_000_000)
    #expect(parseDockerSize("512MB") == 512_000_000)
    #expect(parseDockerSize("0B") == 0)
    #expect(parseDockerSize("2.5kB") == 2_500)
    #expect(parseDockerSize("1TB") == 1_000_000_000_000)
    #expect(parseDockerSize("n/a") == nil)
}

@Test func parsesSystemDF() throws {
    let df = try #require(parseDockerDF(try fixture("docker-system-df.txt")))
    #expect(df.images == 3_214_000_000 + 12_500_000)
    #expect(df.buildCache == 845_300_000)
}

@Test func offReportsDiskSize() async throws {
    try await withTempDirAsync { home in
        let raw = home.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        try writeFile(raw, bytes: 2 * 1_048_576)
        let h = try FileHandle(forWritingTo: raw)
        try h.truncate(atOffset: 10 * 1_073_741_824)   // sparse: apparent 10 GiB, allocated about 2 MiB
        try h.close()
        let scan = await Docker.scan(home: home, run: shellStub(["command -v docker": "/usr/local/bin/docker"]))
        guard case .off(let bytes) = scan else { Issue.record("expected off, got \(scan)"); return }
        #expect(bytes >= 2 * 1_048_576 && bytes < 100 * 1_048_576)
    }
}

@Test func notInstalled() async throws {
    try await withTempDirAsync { home in
        #expect(await Docker.scan(home: home, run: shellStub([:])) == .notInstalled)
    }
}

@Test func runningItemsNeverPruneVolumes() async throws {
    try await withTempDirAsync { home in
        let df = try fixture("docker-system-df.txt").split(separator: "\n").dropFirst().joined(separator: "\n")
        let scan = await Docker.scan(home: home, run: shellStub([
            "command -v docker": "/usr/local/bin/docker",
            "docker info --format '{{.ServerVersion}}'": "27.3.1",
            "docker system df --format '{{.Type}}\t{{.Reclaimable}}'": df]))
        guard case .running(let items) = scan else { Issue.record("expected running, got \(scan)"); return }
        #expect(items.map(\.id) == ["docker.buildcache", "docker.images"])
        #expect(items.allSatisfy { $0.target.group == "Docker" && $0.measure == .docker })
        #expect(items[1].target.tier == .dataLoss)
        for item in items {
            guard case .steps(let steps) = item.removal else { Issue.record("no steps"); continue }
            #expect(!"\(steps)".contains("--volumes"))
        }
    }
}
