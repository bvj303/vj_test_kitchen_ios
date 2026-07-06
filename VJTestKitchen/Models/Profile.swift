import Foundation

struct Profile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var displayName: String?
    let createdAt: Date
}
