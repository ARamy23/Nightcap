import Testing

@Suite("Sanity")
struct SanityTests {
    @Test("the iOS test bundle runs at all")
    func bundleRuns() {
        #expect(1 + 1 == 2)
    }
}
