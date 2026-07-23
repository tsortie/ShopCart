import Foundation

@MainActor
extension GroceryItem {
    var sortedSubItems: [SubItem] {
        subItems.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
class GroceryListViewModel: ObservableObject {
    
    @Published var lists: [GroceryList] = []
    @Published var selectedListIndex: Int = 0
    @Published var searchText: String = ""
    
    
    private let persistenceKey = "grocery_lists_v2"
    
    init() {
        // UserDefaults is ALWAYS loaded first, no matter what
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([GroceryList].self, from: data) {
            self.lists = saved
        } else {
            if let oldData = UserDefaults.standard.data(forKey: "grocery_list_v1"),
               let old = try? JSONDecoder().decode(GroceryList.self, from: oldData) {
                self.lists = [old]
            } else {
                self.lists = [GroceryList(name: "Groceries")]
            }
        }

        // CloudKit runs in background and NEVER affects local-only lists
        Task { @MainActor in
            await CloudKitManager.shared.setup()
            await refreshFromCloudKit()
            // Only sync lists that are already marked as shared
            await syncSharedListsToCloudKit()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitChange),
            name: .cloudKitDataChanged,
            object: nil
        )
    }
    
    @objc private func handleCloudKitChange() {
        Task { await refreshFromCloudKit() }
    }
    
    private func syncSharedListsToCloudKit() async {
        let sharedLists = lists.filter { $0.isShared || $0.cloudKitRecordID != nil }
        for i in 0..<lists.count {
            guard lists[i].isShared || lists[i].cloudKitRecordID != nil else { continue }
            do {
                let recordName = try await CloudKitManager.shared.save(lists[i])
                await MainActor.run {
                    if i < lists.count {
                        lists[i].cloudKitRecordID = recordName
                    }
                }
            } catch {
                print("DEBUG: CloudKit sync error for \(lists[i].name): \(error)")
            }
        }
    }
    
    private func refreshFromCloudKit() async {
        do {
            let cloudLists = try await CloudKitManager.shared.fetchAllLists()
            await MainActor.run {
                for cloudList in cloudLists {
                    if let localIndex = lists.firstIndex(where: {
                        $0.cloudKitRecordID == cloudList.cloudKitRecordID
                    }) {
                        // Only update if this list came FROM CloudKit originally
                        if lists[localIndex].isShared {
                            lists[localIndex] = cloudList
                        }
                    } else if cloudList.isShared {
                        // Only append lists that are explicitly shared
                        // Never append lists that could duplicate local ones
                        if !lists.contains(where: { $0.name == cloudList.name && !$0.isShared }) {
                            lists.append(cloudList)
                        }
                    }
                }
                if let data = try? JSONEncoder().encode(lists) {
                    UserDefaults.standard.set(data, forKey: persistenceKey)
                }
            }
        } catch {
            // On any CloudKit error, do absolutely nothing to local data
            print("DEBUG: CloudKit refresh error: \(error)")
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
    
    func importFromDeepLink(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value
        else { return }
        
        // Handle both standard and URL-safe base64
        var base64 = dataParam
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
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
    
    @Published var recentlyDeletedList: GroceryList? = nil
    
    func deleteList(at offsets: IndexSet) {
        if let index = offsets.first {
            recentlyDeletedList = lists[index]
            let listToDelete = lists[index]
            Task { try? await CloudKitManager.shared.delete(listToDelete) }
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
    
    // MARK: - Item CRUD
    func addItem(name: String, quantity: Int = 1) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = GroceryItem(name: name.trimmingCharacters(in: .whitespaces), quantity: quantity, isActive: false)
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
            let anyChecked = lists[selectedListIndex].items[idx].subItems.contains(where: { $0.isChecked })
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
    func save() {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
            UserDefaults.standard.set(data, forKey: "\(persistenceKey)_backup")
        }
        // Only push to CloudKit if there are shared lists
        let hasSharedLists = lists.contains { $0.isShared || $0.cloudKitRecordID != nil }
        if hasSharedLists {
            Task { await syncSharedListsToCloudKit() }
        }
    }
    
    private func syncToCloudKit() async {
        print("DEBUG: Starting CloudKit sync for \(lists.count) lists")
        for i in 0..<lists.count {
            do {
                print("DEBUG: Saving list '\(lists[i].name)'")
                let recordName = try await CloudKitManager.shared.save(lists[i])
                print("DEBUG: Saved with record name: \(recordName)")
                await MainActor.run {
                    if i < lists.count && lists[i].cloudKitRecordID != recordName {
                        lists[i].cloudKitRecordID = recordName
                        if let data = try? JSONEncoder().encode(lists) {
                            UserDefaults.standard.set(data, forKey: persistenceKey)
                        }
                    }
                }
            } catch {
                print("DEBUG: CloudKit save error for \(lists[i].name): \(error)")
            }
        }
        print("DEBUG: Sync complete")
    }
}
