import Foundation

struct Tag: Codable, Identifiable, Sendable, Hashable {
    let id: Int64
    var name: String
}
