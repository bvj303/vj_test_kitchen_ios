import Foundation

/// Helper for reading every row of a PostgREST table. PostgREST caps a single
/// response at a default max-rows limit (~1000), so an unpaginated `.select()`
/// silently truncates large result sets. `fetchAllPages` walks fixed-size
/// ranges until a short page comes back, so callers get the full set.
enum Pagination {
    /// PostgREST's common default max-rows. Kept as the default page size so a
    /// full page implies "there may be more".
    static let defaultPageSize = 1000

    /// Repeatedly invokes `fetchPage(from:to:)` with inclusive zero-based row
    /// ranges, accumulating results until a page shorter than `pageSize` is
    /// returned (which means the end was reached).
    static func fetchAllPages<T>(
        pageSize: Int = defaultPageSize,
        fetchPage: (_ from: Int, _ to: Int) async throws -> [T]
    ) async throws -> [T] {
        precondition(pageSize > 0, "pageSize must be positive")
        var all: [T] = []
        var from = 0
        while true {
            let page = try await fetchPage(from, from + pageSize - 1)
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            from += pageSize
        }
        return all
    }
}
