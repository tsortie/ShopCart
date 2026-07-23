import Foundation

@MainActor
class GroceryListViewModel: ObservableObject {

    @Published var lists: [GroceryList] = []
    @Published var selectedListIndex: Int = 0
    @Published var searchText: String = ""
    @Published var recentlyDeletedList: GroceryList? = nil

    private let persistenceKey = "grocery_lists_v2"
    private let backupKey = "grocery_lists_v2_backup"

    init() {
        // Step 1: Always load from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([GroceryList].self, from: data) {
            self.lists = saved
        } else if let oldData = UserDefaults.standard.data(forKey: "grocery_list_v1"),
                  let old = try? JSONDecoder().decode(GroceryList.self, from: oldData) {
            self.lists = [old]
        } else {
            self.lists = [GroceryList(name: "Groceries")]
        }

        // Step 2: Safety net — restore from backup if lists are empty
        if lists.isEmpty {
            if let backupData = UserDefaults.standard.data(forKey: backupKey),
               let backup = try? JSONDecoder().decode([GroceryList].self, from: backupData),
               !backup.isEmpty {
                print("DEBUG: Restored from backup")
                self.lists = backup
            }
        }

        // Step 3: CloudKit setup — only for shared lists, never touches local lists
        Task {
            await CloudKitManager.shared.setup()
            await fetchSharedListsFromCloudKit()
        }

        // Step 4: Listen for CloudKit changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitChange),
            name: .cloudKitDataChanged,
            object: nil
        )
    }

    @objc private func handleCloudKitChange() {
        Task { await fetchSharedListsFromCloudKit() }
    }

    // MARK: - CloudKit: only fetch shared lists
    private func fetchSharedListsFromCloudKit() async {
        do {
            let sharedLists = try await CloudKitManager.shared.fetchSharedLists()
            guard !sharedLists.isEmpty else { return }

            for cloudList in sharedLists {
                if let localIndex = lists.firstIndex(where: {
                    $0.cloudKitRecordID == cloudList.cloudKitRecordID
                }) {
                    // Update existing shared list
                    lists[localIndex] = cloudList
                } else {
                    // Add new shared list from someone else
                    lists.append(cloudList)
                }
            }
            saveLocally()
        } catch {
            // Never touch local data on error
            print("DEBUG: CloudKit fetch error: \(error)")
        }
    }

    // MARK: - CloudKit: sync a single shared list
    private func syncToCloudKit(_ list: GroceryList) async {
        guard list.isShared || list.cloudKitRecordID != nil else { return }
        do {
            let recordName = try await CloudKitManager.shared.save(list)
            if let idx = lists.firstIndex(where: { $0.id == list.id }) {
                lists[idx].cloudKitRecordID = recordName
                saveLocally()
            }
        } catch {
            print("DEBUG: CloudKit sync error: \(error)")
        }
    }

    // MARK: - Current list
    var list: GroceryList {
        get { lists[selectedListIndex] }
        set { lists[selectedListIndex] = newValue }
    }

    // MARK: - Computed
    var filteredItems: [GroceryItem] {
        if searchText.isEmpty { return list.items }
        return list.items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.subItems.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var activeItems: [GroceryItem] {
        filteredItems.filter { !$0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var inactiveItems: [GroceryItem] {
        filteredItems.filter { $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Sharing
    func markAsShared(listID: UUID, recordName: String) {
        if let idx = lists.firstIndex(where: { $0.id == listID }) {
            lists[idx].isShared = true
            lists[idx].cloudKitRecordID = recordName
            saveLocally()
        }
    }

    func exportAsDeepLink() -> URL? {
        guard let data = try? JSONEncoder().encode(list),
              let base64 = data.base64EncodedString()
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let name = list.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "shopcart://import?data=\(base64)")
    }

    func importFromDeepLink(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value
        else { return }

        var base64 = dataParam
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64),
              var imported = try? JSONDecoder().decode(GroceryList.self, from: data)
        else { return }

        imported.id = UUID()
        lists.append(imported)
        selectedListIndex = lists.count - 1
        save()
    }

    func importList(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              var imported = try? JSONDecoder().decode(GroceryList.self, from: data)
        else { return }
        imported.id = UUID()
        lists.append(imported)
        selectedListIndex = lists.count - 1
        save()
    }

    // MARK: - List management
    func addList(name: String) {
        let newList = GroceryList(name: name.trimmingCharacters(in: .whitespaces))
        lists.append(newList)
        selectedListIndex = lists.count - 1
        save()
    }

    func deleteList(at offsets: IndexSet) {
        if let index = offsets.first {
            recentlyDeletedList = lists[index]
            let listToDelete = lists[index]
            if listToDelete.cloudKitRecordID != nil {
                Task { try? await CloudKitManager.shared.delete(listToDelete) }
            }
        }
        lists.remove(atOffsets: offsets)
        if lists.isEmpty { lists.append(GroceryList(name: "Groceries")) }
        selectedListIndex = max(0, min(selectedListIndex, lists.count - 1))
        save()
    }

    func undoDeleteList() {
        guard let deleted = recentlyDeletedList else { return }
        lists.append(deleted)
        selectedListIndex = lists.count - 1
        recentlyDeletedList = nil
        save()
    }

    func clearUndoHistory() {
        recentlyDeletedList = nil
    }

    func renameList(id: UUID, name: String) {
        if let idx = lists.firstIndex(where: { $0.id == id }) {
            lists[idx].name = name.trimmingCharacters(in: .whitespaces)
            save()
        }
    }

    func selectList(at index: Int) {
        guard index >= 0 && index < lists.count else { return }
        selectedListIndex = index
        searchText = ""
    }

    func moveList(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < lists.count,
              destination >= 0, destination < lists.count
        else { return }
        let currentID = lists[selectedListIndex].id
        let item = lists.remove(at: source)
        lists.insert(item, at: destination)
        if let newIndex = lists.firstIndex(where: { $0.id == currentID }) {
            selectedListIndex = newIndex
        }
        save()
    }

    // MARK: - Item CRUD
    func addItem(name: String, quantity: Int = 1) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = GroceryItem(name: name.trimmingCharacters(in: .whitespaces),
                              quantity: quantity, isActive: false)
        lists[selectedListIndex].items.append(item)
        save()
    }

    func removeItem(id: UUID) {
        lists[selectedListIndex].items.removeAll { $0.id == id }
        save()
    }

    func toggleItemActive(id: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == id }) {
            lists[selectedListIndex].items[idx].isActive.toggle()
            if lists[selectedListIndex].items[idx].isActive {
                for subIdx in lists[selectedListIndex].items[idx].subItems.indices {
                    lists[selectedListIndex].items[idx].subItems[subIdx].isChecked = false
                }
            }
            save()
        }
    }

    func updateItemName(id: UUID, newName: String) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == id }) {
            lists[selectedListIndex].items[idx].name = newName.trimmingCharacters(in: .whitespaces)
            save()
        }
    }

    func incrementItem(id: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == id }) {
            lists[selectedListIndex].items[idx].quantity += 1
            save()
        }
    }

    func decrementItem(id: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == id }) {
            if lists[selectedListIndex].items[idx].quantity > 1 {
                lists[selectedListIndex].items[idx].quantity -= 1
            }
            save()
        }
    }

    func toggleExpanded(id: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == id }) {
            lists[selectedListIndex].items[idx].isExpanded.toggle()
            save()
        }
    }

    // MARK: - SubItem CRUD
    func addSubItem(to itemID: UUID, name: String, quantity: Int = 1) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == itemID }) {
            let sub = SubItem(name: name.trimmingCharacters(in: .whitespaces), quantity: quantity)
            lists[selectedListIndex].items[idx].subItems.append(sub)
            lists[selectedListIndex].items[idx].isExpanded = true
            save()
        }
    }

    func removeSubItem(from itemID: UUID, subID: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == itemID }) {
            lists[selectedListIndex].items[idx].subItems.removeAll { $0.id == subID }
            save()
        }
    }

    func toggleSubItem(itemID: UUID, subID: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == itemID }),
           let subIdx = lists[selectedListIndex].items[idx].subItems.firstIndex(where: { $0.id == subID }) {
            lists[selectedListIndex].items[idx].subItems[subIdx].isChecked.toggle()
            let anyChecked = lists[selectedListIndex].items[idx].subItems.contains { $0.isChecked }
            lists[selectedListIndex].items[idx].isActive = anyChecked ? false : true
            save()
        }
    }

    func incrementSubItem(itemID: UUID, subID: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == itemID }),
           let subIdx = lists[selectedListIndex].items[idx].subItems.firstIndex(where: { $0.id == subID }) {
            lists[selectedListIndex].items[idx].subItems[subIdx].quantity += 1
            save()
        }
    }

    func decrementSubItem(itemID: UUID, subID: UUID) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == itemID }),
           let subIdx = lists[selectedListIndex].items[idx].subItems.firstIndex(where: { $0.id == subID }) {
            if lists[selectedListIndex].items[idx].subItems[subIdx].quantity > 1 {
                lists[selectedListIndex].items[idx].subItems[subIdx].quantity -= 1
            }
            save()
        }
    }

    func updateSubItemName(itemID: UUID, subID: UUID, newName: String) {
        if let idx = lists[selectedListIndex].items.firstIndex(where: { $0.id == itemID }),
           let subIdx = lists[selectedListIndex].items[idx].subItems.firstIndex(where: { $0.id == subID }) {
            lists[selectedListIndex].items[idx].subItems[subIdx].name = newName.trimmingCharacters(in: .whitespaces)
            save()
        }
    }

    // MARK: - Persistence
    private func saveLocally() {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
            UserDefaults.standard.set(data, forKey: backupKey)
        }
    }

    func save() {
        saveLocally()
        let currentList = list
        if currentList.isShared || currentList.cloudKitRecordID != nil {
            Task { await syncToCloudKit(currentList) }
        }
    }
}
