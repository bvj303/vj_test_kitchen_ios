import Foundation

struct Ingredient: Codable, Identifiable, Sendable, Hashable {
    let id: Int64
    var recipeId: Int64
    var name: String
    var amount: Double
    var unit: String
}
