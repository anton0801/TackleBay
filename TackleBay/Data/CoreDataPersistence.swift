import CoreData
import Foundation

enum PersistenceError: Error, LocalizedError {
    case storeUnavailable(String)
    case corrupted(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable(let m): return "The local database couldn't be opened. \(m)"
        case .corrupted(let m): return "Some saved data couldn't be read. \(m)"
        case .writeFailed(let m): return "The change couldn't be saved. \(m)"
        }
    }
}

/// Core Data store. Every record is a row keyed by its id with a versioned JSON payload;
/// a commit writes only the rows that changed, inside one context save (one SQLite transaction).
final class CoreDataPersistence {
    /// Schema history: v1 — initial. Bump with a new model version and a migration step.
    static let schemaVersion = "1"

    private enum Entity: String, CaseIterable {
        case gear = "GearRecord"
        case movement = "StockMovementRecord"
        case kit = "KitRecord"
        case trip = "TripRecord"
        case returnDraft = "ReturnDraftRecord"
        case returnResult = "TripReturnResultRecord"
        case photo = "PhotoRecord"
        case claim = "BonusClaimRecord"
        case receipt = "CastReceiptRecord"
        case ownership = "CollectibleOwnershipRecord"
        case meta = "MetaRecord"
    }

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = [CoreDataPersistence.schemaVersion]
        model.entities = Entity.allCases.map { entity in
            let description = NSEntityDescription()
            description.name = entity.rawValue
            description.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            let key = NSAttributeDescription()
            key.name = "key"
            key.attributeType = .stringAttributeType
            key.isOptional = false
            let payload = NSAttributeDescription()
            payload.name = "payload"
            payload.attributeType = .binaryDataAttributeType
            payload.isOptional = false
            let sort = NSAttributeDescription()
            sort.name = "sortKey"
            sort.attributeType = .integer64AttributeType
            sort.isOptional = false
            sort.defaultValue = 0
            description.properties = [key, payload, sort]
            description.uniquenessConstraints = [["key"]]
            return description
        }
        return model
    }()

    /// `storeURL == nil` creates an in-memory store (tests).
    init(storeURL: URL?) throws {
        container = NSPersistentContainer(name: "TackleBay", managedObjectModel: Self.model)
        let description: NSPersistentStoreDescription
        if let url = storeURL {
            description = NSPersistentStoreDescription(url: url)
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
        } else {
            // SQLite on /dev/null: an in-memory store that still enforces uniqueness constraints.
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw PersistenceError.storeUnavailable(error.localizedDescription) }
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
    }

    // MARK: Load

    func loadAll() throws -> TBDatabase {
        var result: Result<TBDatabase, Error> = .failure(PersistenceError.storeUnavailable(""))
        context.performAndWait {
            do {
                var db = TBDatabase()
                db.gear = try load(.gear, Gear.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.movements = try load(.movement, StockMovement.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.kits = try load(.kit, Kit.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.trips = try load(.trip, Trip.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.returnDrafts = try load(.returnDraft, ReturnDraft.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.returnResults = try load(.returnResult, TripReturnResult.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.photos = try load(.photo, PhotoRef.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.claims = try load(.claim, BonusClaim.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.receipts = try load(.receipt, CastReceipt.self).reduce(into: [:]) { $0[$1.id] = $1 }
                db.ownerships = try load(.ownership, CollectibleOwnership.self).reduce(into: [:]) { $0[$1.collectibleID] = $1 }
                let meta = try fetch(.meta, keys: nil)
                for object in meta {
                    guard let key = object.value(forKey: "key") as? String, let data = object.value(forKey: "payload") as? Data else { continue }
                    switch key {
                    case "wallet": db.wallet = try decoder.decode(BonusWallet.self, from: data)
                    case "settings": db.settings = try decoder.decode(AppSettings.self, from: data)
                    case "counters": db.counters = try decoder.decode(Counters.self, from: data)
                    default: break
                    }
                }
                result = .success(db)
            } catch {
                result = .failure(PersistenceError.corrupted(error.localizedDescription))
            }
        }
        return try result.get()
    }

    private func load<T: Decodable>(_ entity: Entity, _ type: T.Type) throws -> [T] {
        try fetch(entity, keys: nil).map { object in
            guard let data = object.value(forKey: "payload") as? Data else { throw PersistenceError.corrupted("Empty record.") }
            return try decoder.decode(T.self, from: data)
        }
    }

    private func fetch(_ entity: Entity, keys: [String]?) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity.rawValue)
        if let keys = keys { request.predicate = NSPredicate(format: "key IN %@", keys) }
        request.sortDescriptors = [NSSortDescriptor(key: "sortKey", ascending: true)]
        return try context.fetch(request)
    }

    // MARK: Save

    /// Writes the difference between two snapshots in one transaction. On failure nothing is written.
    func commit(from old: TBDatabase, to new: TBDatabase) throws {
        var thrown: Error?
        context.performAndWait {
            do {
                try write(from: old, to: new)
                if context.hasChanges { try context.save() }
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let error = thrown { throw PersistenceError.writeFailed(error.localizedDescription) }
    }

    /// Replaces the whole store content atomically (import / restore / reset).
    func replaceAll(with db: TBDatabase) throws {
        var thrown: Error?
        context.performAndWait {
            do {
                for entity in Entity.allCases {
                    for object in try fetch(entity, keys: nil) { context.delete(object) }
                }
                try write(from: TBDatabase(), to: db, forceMeta: true)
                try context.save()
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let error = thrown { throw PersistenceError.writeFailed(error.localizedDescription) }
    }

    private func write(from old: TBDatabase, to new: TBDatabase, forceMeta: Bool = false) throws {
        try sync(.gear, old.gear, new.gear, key: { $0.uuidString }, sort: { _ in 0 })
        try sync(.movement, old.movements, new.movements, key: { $0.uuidString }, sort: { $0.sequence })
        try sync(.kit, old.kits, new.kits, key: { $0.uuidString }, sort: { _ in 0 })
        try sync(.trip, old.trips, new.trips, key: { $0.uuidString }, sort: { _ in 0 })
        try sync(.returnDraft, old.returnDrafts, new.returnDrafts, key: { $0.uuidString }, sort: { _ in 0 })
        try sync(.returnResult, old.returnResults, new.returnResults, key: { $0.uuidString }, sort: { _ in 0 })
        try sync(.photo, old.photos, new.photos, key: { $0.uuidString }, sort: { _ in 0 })
        try sync(.claim, old.claims, new.claims, key: { $0.uuidString }, sort: { $0.sequence })
        try sync(.receipt, old.receipts, new.receipts, key: { $0.uuidString }, sort: { $0.sequence })
        try sync(.ownership, old.ownerships, new.ownerships, key: { $0.rawValue }, sort: { $0.sequence })
        var meta: [String: Data] = [:]
        if forceMeta || old.wallet != new.wallet { meta["wallet"] = try encoder.encode(new.wallet) }
        if forceMeta || old.settings != new.settings { meta["settings"] = try encoder.encode(new.settings) }
        if forceMeta || old.counters != new.counters { meta["counters"] = try encoder.encode(new.counters) }
        if !meta.isEmpty { try upsert(.meta, payloads: meta, sortKeys: [:]) }
    }

    private func sync<K: Hashable, V: Codable & Equatable>(_ entity: Entity, _ old: [K: V], _ new: [K: V],
                                                         key: (K) -> String, sort: (V) -> Int64) throws {
        var payloads: [String: Data] = [:]
        var sortKeys: [String: Int64] = [:]
        for (k, v) in new where old[k] != v {
            payloads[key(k)] = try encoder.encode(v)
            sortKeys[key(k)] = sort(v)
        }
        let removed = old.keys.filter { new[$0] == nil }.map(key)
        if !payloads.isEmpty { try upsert(entity, payloads: payloads, sortKeys: sortKeys) }
        if !removed.isEmpty {
            for object in try fetch(entity, keys: removed) { context.delete(object) }
        }
    }

    private func upsert(_ entity: Entity, payloads: [String: Data], sortKeys: [String: Int64]) throws {
        let existing = try fetch(entity, keys: Array(payloads.keys))
        var byKey: [String: NSManagedObject] = [:]
        for object in existing {
            if let k = object.value(forKey: "key") as? String { byKey[k] = object }
        }
        for (k, data) in payloads {
            let object = byKey[k] ?? NSEntityDescription.insertNewObject(forEntityName: entity.rawValue, into: context)
            object.setValue(k, forKey: "key")
            object.setValue(data, forKey: "payload")
            object.setValue(sortKeys[k] ?? 0, forKey: "sortKey")
        }
    }
}
