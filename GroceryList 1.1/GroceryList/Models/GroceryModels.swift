import Foundation

// MARK: - SubItem
struct SubItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var quantity: Int = 1
    var isChecked: Bool = false

    init(id: UUID = UUID(), name: String, quantity: Int = 1, isChecked: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.isChecked = isChecked
    }
}

// MARK: - GroceryItem
struct GroceryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var quantity: Int = 1
    var isActive: Bool = true
    var subItems: [SubItem] = []
    var isExpanded: Bool = false

    init(id: UUID = UUID(), name: String, quantity: Int = 1, isActive: Bool = true, subItems: [SubItem] = [], isExpanded: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.isActive = isActive
        self.subItems = subItems
        self.isExpanded = isExpanded
    }

    var hasSubItems: Bool { !subItems.isEmpty }
}

// MARK: - GroceryList
struct GroceryList: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var items: [GroceryItem] = []
}
