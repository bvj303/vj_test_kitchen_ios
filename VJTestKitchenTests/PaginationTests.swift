import Foundation
import Testing
@testable import VJTestKitchen

struct PaginationTests {
    @Test func stopsOnceAShortPageIsReturned() async throws {
        var requestedRanges: [(Int, Int)] = []
        let source = [1, 2, 3]

        let result = try await Pagination.fetchAllPages(pageSize: 2) { from, to in
            requestedRanges.append((from, to))
            return Array(source.dropFirst(from).prefix(2))
        }

        #expect(result == [1, 2, 3])
        // [0,1] returns 2 (full) -> continue; [2,3] returns 1 (short) -> stop.
        #expect(requestedRanges.count == 2)
        #expect(requestedRanges[0] == (0, 1))
        #expect(requestedRanges[1] == (2, 3))
    }

    @Test func fetchesAnExtraEmptyPageWhenTotalIsAnExactMultiple() async throws {
        var calls = 0
        let source = [1, 2, 3, 4]

        let result = try await Pagination.fetchAllPages(pageSize: 2) { from, _ in
            calls += 1
            return Array(source.dropFirst(from).prefix(2))
        }

        #expect(result == [1, 2, 3, 4])
        // [0,1] full, [2,3] full, [4,5] empty -> stop.
        #expect(calls == 3)
    }

    @Test func singleShortPageMakesOneRequest() async throws {
        var calls = 0
        let result = try await Pagination.fetchAllPages(pageSize: 100) { _, _ in
            calls += 1
            return [1, 2, 3]
        }
        #expect(result == [1, 2, 3])
        #expect(calls == 1)
    }

    @Test func propagatesErrors() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await Pagination.fetchAllPages(pageSize: 2) { _, _ -> [Int] in throw Boom() }
        }
    }
}
