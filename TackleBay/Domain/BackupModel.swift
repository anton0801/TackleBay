import Foundation

struct BackupPhoto: Codable, Equatable {
    var ref: PhotoRef
    /// Base64 of the stored JPEG.
    var data: String
}

/// tackle-bay-backup-v1.json — UTF-8 JSON, photos inline as base64.
struct BackupFile: Codable {
    var schemaVersion: Int
    var app: String
    var createdAt: Date
    var gear: [Gear]
    var movements: [StockMovement]
    var kits: [Kit]
    var trips: [Trip]
    var returnDrafts: [ReturnDraft]
    var returnResults: [TripReturnResult]
    var photos: [BackupPhoto]
    var wallet: BonusWallet
    var claims: [BonusClaim]
    var receipts: [CastReceipt]
    var ownerships: [CollectibleOwnership]
    var settings: AppSettings
    var counters: Counters

    static let currentSchema = 1
    static let appID = "TackleBay"
    static let fileName = "tackle-bay-backup-v1.json"

    init(db: TBDatabase, photos: [BackupPhoto], createdAt: Date) {
        schemaVersion = Self.currentSchema
        app = Self.appID
        self.createdAt = createdAt
        gear = db.gear.values.sorted { $0.createdAt < $1.createdAt }
        movements = db.movements.values.sorted { $0.sequence < $1.sequence }
        kits = Array(db.kits.values)
        trips = Array(db.trips.values)
        returnDrafts = Array(db.returnDrafts.values)
        returnResults = Array(db.returnResults.values)
        self.photos = photos
        wallet = db.wallet
        claims = db.claims.values.sorted { $0.sequence < $1.sequence }
        receipts = db.receipts.values.sorted { $0.sequence < $1.sequence }
        ownerships = db.ownerships.values.sorted { $0.sequence < $1.sequence }
        settings = db.settings
        counters = db.counters
    }
}

struct BackupSummary: Equatable {
    var createdAt: Date
    var gearCount: Int
    var kitCount: Int
    var tripCount: Int
    var photoCount: Int
    var movementCount: Int
    var hasOpenTrip: Bool
    var tickets: Int
    var parts: Int
    var builtMiniatures: Int
}

enum BackupValidator {
    /// Validates structure, references, limits, demo membership, stock journal and bonus ledger.
    /// Returns the database that would replace the current one.
    static func validate(_ file: BackupFile) throws -> (TBDatabase, BackupSummary) {
        func fail(_ reason: String) -> DomainError { .validation(reason) }
        guard file.app == BackupFile.appID else { throw fail("This file isn't a Tackle Bay backup.") }
        guard file.schemaVersion == BackupFile.currentSchema else { throw fail("This backup version isn't supported.") }

        func unique<T, K: Hashable>(_ items: [T], _ key: (T) -> K, _ what: String) throws -> [K: T] {
            var map: [K: T] = [:]
            for item in items {
                if map.updateValue(item, forKey: key(item)) != nil { throw fail("Some \(what) records repeat.") }
            }
            return map
        }

        var db = TBDatabase()
        db.gear = try unique(file.gear, { $0.id }, "gear")
        db.movements = try unique(file.movements, { $0.id }, "stock history")
        db.kits = try unique(file.kits, { $0.id }, "kit")
        db.trips = try unique(file.trips, { $0.id }, "trip")
        db.returnDrafts = try unique(file.returnDrafts, { $0.id }, "return draft")
        db.returnResults = try unique(file.returnResults, { $0.id }, "trip result")
        db.photos = try unique(file.photos.map(\.ref), { $0.id }, "photo")
        db.claims = try unique(file.claims, { $0.id }, "ticket")
        db.receipts = try unique(file.receipts, { $0.id }, "bonus result")
        db.ownerships = try unique(file.ownerships, { $0.collectibleID }, "miniature")
        db.wallet = file.wallet
        db.settings = file.settings
        db.counters = file.counters

        if file.gear.count > 20_000 || file.kits.count > 5_000 || file.trips.count > 20_000 || file.movements.count > 500_000 {
            throw fail("This backup is larger than Tackle Bay supports.")
        }

        // Gear passports and quantities.
        for g in db.gear.values {
            let draft = GearDraft(gear: g)
            if !GearUseCases.validate(draft, isNew: false).isEmpty { throw fail("Some gear records have invalid details.") }
            if StockRules.validate(StockRules.buckets(g), tracking: g.trackingType) != nil {
                throw fail("Some gear records have invalid quantities.")
            }
            if let p = g.photoID, db.photos[p] == nil { throw fail("A gear photo is missing from the backup.") }
            if g.sampleArt != nil && !g.isDemo { throw fail("Sample artwork is attached to your own gear.") }
        }
        // Operation/gear pairs and sequence uniqueness are covered by the stock invariant check below.
        for m in db.movements.values where db.gear[m.gearID] == nil { throw fail("Stock history points to missing gear.") }

        for k in db.kits.values {
            if TextRules.check(k.name, field: "Kit name", range: 1...60) != nil || k.lines.isEmpty || k.lines.count > KitUseCases.maxLines {
                throw fail("Some kits have invalid details.")
            }
            if Set(k.lines.map(\.gearID)).count != k.lines.count { throw fail("A kit lists the same gear twice.") }
            for l in k.lines {
                guard let g = db.gear[l.gearID] else { throw fail("A kit points to missing gear.") }
                if g.isDemo != k.isDemo { throw fail("Sample and personal records are mixed in a kit.") }
                if !(1...StockRules.maxQuantity).contains(l.requiredQty) { throw fail("A kit has invalid quantities.") }
            }
        }

        let open = db.trips.values.filter { $0.isOpenTrip }
        if open.count > 1 { throw fail("The backup has more than one active trip.") }
        for t in db.trips.values {
            if TextRules.check(t.name, field: "Trip name", range: 1...80) != nil || TextRules.check(t.place, field: "Place", range: 1...100) != nil
                || t.lines.count > TripUseCases.maxLines {
                throw fail("Some trips have invalid details.")
            }
            if Set(t.lines.map(\.gearID)).count != t.lines.count { throw fail("A trip lists the same gear twice.") }
            for l in t.lines {
                guard let g = db.gear[l.gearID] else { throw fail("A trip points to missing gear.") }
                if g.isDemo != t.isDemo { throw fail("Sample and personal records are mixed in a trip.") }
                if !(1...StockRules.maxQuantity).contains(l.requiredQty) || !(0...l.requiredQty).contains(l.packedQty) {
                    throw fail("A trip has invalid quantities.")
                }
                if t.status != .planned && t.status != .cancelled && l.takenQty == nil { throw fail("A started trip is missing its snapshot.") }
                if let taken = l.takenQty, taken < 0 { throw fail("A trip has invalid quantities.") }
            }
            let draft = db.draft(for: t.id)
            switch t.status {
            case .returning: if draft == nil { throw fail("A returning trip is missing its draft.") }
            case .completed: if db.result(for: t.id) == nil { throw fail("A completed trip is missing its result.") }
            default: if draft != nil { throw fail("A return draft belongs to a trip that isn't returning.") }
            }
            if t.status != .planned && t.status != .cancelled && t.startedAt == nil { throw fail("A started trip has no start time.") }
        }
        for d in db.returnDrafts.values {
            guard let t = db.trips[d.tripID], t.status == .returning else { throw fail("A return draft points to a missing trip.") }
            for e in d.entries {
                guard let line = t.lines.first(where: { $0.id == e.tripLineID }), let taken = line.takenQty else {
                    throw fail("A return draft points to a missing row.")
                }
                let tracking = line.snapshot?.trackingType ?? .reusable
                if TripUseCases.validateEntry(e, taken: taken, tracking: tracking) != nil { throw fail("A return draft has invalid quantities.") }
            }
        }
        if Set(db.returnDrafts.values.map(\.tripID)).count != db.returnDrafts.count { throw fail("A trip has two return drafts.") }
        for r in db.returnResults.values {
            guard let t = db.trips[r.tripID], t.status == .completed else { throw fail("A trip result points to a missing trip.") }
            for e in r.entries where e.returned + e.care + e.used + e.lost != e.taken { throw fail("A trip result doesn't add up.") }
        }
        if Set(db.returnResults.values.map(\.tripID)).count != db.returnResults.count { throw fail("A trip has two results.") }

        if let problem = StockRules.invariantProblems(db).first { throw fail("Stock history doesn't match quantities. \(problem)") }
        if let problem = BonusUseCases.ledgerProblems(db).first { throw fail(problem) }

        let summary = BackupSummary(createdAt: file.createdAt, gearCount: db.gear.count, kitCount: db.kits.count,
                                    tripCount: db.trips.count, photoCount: db.photos.count, movementCount: db.movements.count,
                                    hasOpenTrip: !open.isEmpty, tickets: db.wallet.tickets, parts: db.wallet.parts,
                                    builtMiniatures: db.ownerships.count)
        return (db, summary)
    }
}
