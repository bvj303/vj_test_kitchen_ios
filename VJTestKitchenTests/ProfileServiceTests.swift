import Foundation
import Testing
@testable import VJTestKitchen

struct ProfileServiceTests {
    /// Regression guard: the avatar object path must lowercase the uid.
    /// `UUID.uuidString` is uppercase, but the bucket's owner-folder RLS check
    /// compares against `auth.uid()::text` (lowercase) — an uppercase folder
    /// fails the policy with "new row violates row-level security policy".
    @Test func avatarObjectPathLowercasesTheUUID() {
        let uid = UUID(uuidString: "E4B6CDDC-055C-4CFC-81FC-D05EA967395E")!

        let path = ProfileService.avatarObjectPath(userId: uid)

        #expect(path == "e4b6cddc-055c-4cfc-81fc-d05ea967395e/avatar.jpg")
        #expect(path == path.lowercased())
    }
}
