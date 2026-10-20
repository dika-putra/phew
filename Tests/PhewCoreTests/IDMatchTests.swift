import Testing
@testable import PhewCore

@Test func suggestsByContains() {
    #expect(suggestions(for: "derived", in: ["xcode.deriveddata", "gradle"]) == ["xcode.deriveddata"])
}

@Test func suggestsBySegment() {
    #expect(suggestions(for: "xcode.foo", in: ["xcode.archives", "xcode.caches", "gradle"]) == ["xcode.archives", "xcode.caches"])
}

@Test func suggestsAtMostThree() {
    #expect(suggestions(for: "x", in: ["x.a", "x.b", "x.c", "x.d"]).count == 3)
}

@Test func noSuggestion() {
    #expect(suggestions(for: "zzz", in: ["gradle"]) == [])
}
