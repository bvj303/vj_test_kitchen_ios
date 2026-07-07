import Foundation

struct Profile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var displayName: String?
    var firstName: String?
    var lastName: String?
    var username: String?
    let createdAt: Date
}
