import CloudKit
import Foundation

extension Notification.Name {
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChanged")
}

@MainActor
class CloudKitManager {
    static let shared = CloudKitManager()

    let container = CKContainer(identifier: "iCloud.com.toddfeliciano.ShopCart")
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    let zoneID = CKRecordZone.ID(zoneName: "ShopCartZone", ownerName: CKCurrentUserDefaultName)

    // MARK: - Setup
    func setup() async {
        do {
            try await privateDB.save(CKRecordZone(zoneID: zoneID))
            try await setupSubscriptions()
            print("DEBUG: CloudKit setup complete")
        } catch {
            print("DEBUG: CloudKit setup error: \(error)")
        }
    }

    // MARK: - Save single list
    func save(_ list: GroceryList) async throws -> String {
        let record: CKRecord

        if let existingID = list.cloudKitRecordID {
            let recordID = CKRecord.ID(recordName: existingID, zoneID: zoneID)
            record = (try? await privateDB.record(for: recordID)) ??
                     CKRecord(recordType: "GroceryList", recordID: recordID)
        } else {
            record = CKRecord(recordType: "GroceryList",
                            recordID: CKRecord.ID(zoneID: zoneID))
        }

        record["name"] = list.name as CKRecordValue
        if let data = try? JSONEncoder().encode(list.items) {
            record["itemsData"] = data as CKRecordValue
        }

        let saved = try await privateDB.save(record)
        return saved.recordID.recordName
    }

    // MARK: - Fetch shared lists only
    func fetchSharedLists() async throws -> [GroceryList] {
        var lists: [GroceryList] = []
        let sharedZones = try await sharedDB.allRecordZones()
        let query = CKQuery(recordType: "GroceryList",
                           predicate: NSPredicate(value: true))

        for zone in sharedZones {
            let (results, _) = try await sharedDB.records(
                matching: query,
                inZoneWith: zone.zoneID
            )
            for (_, result) in results {
                if let record = try? result.get(),
                   let list = makeList(from: record, isShared: true) {
                    lists.append(list)
                }
            }
        }
        return lists
    }

    // MARK: - Delete
    func delete(_ list: GroceryList) async throws {
        guard let recordIDString = list.cloudKitRecordID else { return }
        let recordID = CKRecord.ID(recordName: recordIDString, zoneID: zoneID)
        try await privateDB.deleteRecord(withID: recordID)
    }

    // MARK: - Share
    func createShare(for list: GroceryList) async throws -> (CKShare, CKContainer) {
        guard let recordIDString = list.cloudKitRecordID else {
            throw CloudKitError.noRecordID
        }
        let recordID = CKRecord.ID(recordName: recordIDString, zoneID: zoneID)
        let record = try await privateDB.record(for: recordID)

        // Return existing share if one exists
        if let shareRef = record.share,
           let share = try await privateDB.record(for: shareRef.recordID) as? CKShare {
            share.publicPermission = .readWrite
            try await privateDB.modifyRecords(saving: [share], deleting: [])
            return (share, container)
        }

        // Create new share
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = list.name as CKRecordValue
        share.publicPermission = .readWrite
        try await privateDB.modifyRecords(saving: [record, share], deleting: [])
        return (share, container)
    }

    // MARK: - Accept Share
    func accept(_ metadata: CKShare.Metadata) async throws {
        try await container.accept(metadata)
        NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
    }

    // MARK: - Subscriptions
    private func setupSubscriptions() async throws {
        let privateSubID = "private-changes"
        let sharedSubID = "shared-changes"

        let existing = (try? await privateDB.allSubscriptions()) ?? []
        if existing.contains(where: { $0.subscriptionID == privateSubID }) { return }

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true

        let privateSub = CKDatabaseSubscription(subscriptionID: privateSubID)
        privateSub.notificationInfo = info

        let sharedSub = CKDatabaseSubscription(subscriptionID: sharedSubID)
        sharedSub.notificationInfo = info

        try await privateDB.save(privateSub)
        try await sharedDB.save(sharedSub)
    }

    // MARK: - Helper
    private func makeList(from record: CKRecord, isShared: Bool) -> GroceryList? {
        guard let name = record["name"] as? String else { return nil }
        var list = GroceryList(name: name)
        list.cloudKitRecordID = record.recordID.recordName
        list.isShared = isShared
        if let data = record["itemsData"] as? Data,
           let items = try? JSONDecoder().decode([GroceryItem].self, from: data) {
            list.items = items
        }
        return list
    }

    enum CloudKitError: Error {
        case noRecordID
    }
}
