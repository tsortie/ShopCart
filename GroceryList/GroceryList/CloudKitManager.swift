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
            print("DEBUG: Creating CloudKit zone")
            try await privateDB.save(CKRecordZone(zoneID: zoneID))
            print("DEBUG: Zone created successfully")
            try await setupSubscriptions()
            print("DEBUG: Subscriptions set up")
        } catch {
            print("DEBUG: CloudKit setup error: \(error)")
        }
    }

    // MARK: - Save
    func save(_ list: GroceryList) async throws -> String {
        let record: CKRecord

        if let existingID = list.cloudKitRecordID {
            let recordID = CKRecord.ID(recordName: existingID, zoneID: zoneID)
            if list.isShared {
                record = (try? await sharedDB.record(for: recordID)) ?? CKRecord(recordType: "GroceryList", recordID: recordID)
            } else {
                record = (try? await privateDB.record(for: recordID)) ?? CKRecord(recordType: "GroceryList", recordID: recordID)
            }
        } else {
            record = CKRecord(recordType: "GroceryList", recordID: CKRecord.ID(zoneID: zoneID))
        }

        record["name"] = list.name as CKRecordValue
        if let data = try? JSONEncoder().encode(list.items) {
            record["itemsData"] = data as CKRecordValue
        }

        let saved: CKRecord
        if list.isShared {
            saved = try await sharedDB.save(record)
        } else {
            saved = try await privateDB.save(record)
        }
        return saved.recordID.recordName
    }

    // MARK: - Fetch
    func fetchAllLists() async throws -> [GroceryList] {
        var lists: [GroceryList] = []
        let query = CKQuery(recordType: "GroceryList", predicate: NSPredicate(value: true))

        let (privateResults, _) = try await privateDB.records(matching: query, inZoneWith: zoneID)
        for (_, result) in privateResults {
            if let record = try? result.get(), let list = makeList(from: record, isShared: false) {
                lists.append(list)
            }
        }

        let sharedZones = try await sharedDB.allRecordZones()
        for zone in sharedZones {
            let (sharedResults, _) = try await sharedDB.records(matching: query, inZoneWith: zone.zoneID)
            for (_, result) in sharedResults {
                if let record = try? result.get(), let list = makeList(from: record, isShared: true) {
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
        guard let recordIDString = list.cloudKitRecordID else { throw CloudKitError.noRecordID }
        let recordID = CKRecord.ID(recordName: recordIDString, zoneID: zoneID)
        let record = try await privateDB.record(for: recordID)

        if let shareRef = record.share {
            if let share = try await privateDB.record(for: shareRef.recordID) as? CKShare {
                share.publicPermission = .readWrite
                try await privateDB.modifyRecords(saving: [share], deleting: [])
                return (share, container)
            }
        }

        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = list.name as CKRecordValue
        share.publicPermission = .readWrite  // Anyone with the link can edit

        try await privateDB.modifyRecords(saving: [record, share], deleting: [])
        return (share, container)
    }

    // MARK: - Accept Share
    func accept(_ metadata: CKShare.Metadata) async throws {
        try await container.accept(metadata)
    }

    // MARK: - Subscriptions
    private func setupSubscriptions() async throws {
        let privateSubID = "private-db-changes"
        let sharedSubID = "shared-db-changes"

        if let existing = try? await privateDB.allSubscriptions(),
           existing.contains(where: { $0.subscriptionID == privateSubID }) { return }

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true

        let privateSub = CKDatabaseSubscription(subscriptionID: privateSubID)
        privateSub.notificationInfo = notificationInfo

        let sharedSub = CKDatabaseSubscription(subscriptionID: sharedSubID)
        sharedSub.notificationInfo = notificationInfo

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
