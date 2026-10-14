import Foundation

struct GearDraft: Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var category: GearCategory = .rods
    var trackingType: TrackingType = .reusable
    var countingUnit: CountingUnit = .piece
    var customUnit: String = ""
    var storage: String = ""
    var note: String = ""
    var photoID: UUID?
    var readyQty: Int?
    var careQty: Int? = 0

    init() {}

    init(gear: Gear) {
        id = gear.id
        name = gear.name
        category = gear.category
        trackingType = gear.trackingType
        countingUnit = gear.countingUnit
        customUnit = gear.customUnit ?? ""
        storage = gear.storage
        note = gear.note ?? ""
        photoID = gear.photoID
        readyQty = gear.readyQty
        careQty = gear.careQty
    }
}

enum GearField: Hashable {
    case name, customUnit, storage, note, ready, care, total
}

enum AdjustOperation: String, CaseIterable, Identifiable {
    case addStock, removeStock, sendToCare, markReady

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addStock: return "Add stock"
        case .removeStock: return "Remove stock"
        case .sendToCare: return "Send to care"
        case .markReady: return "Mark ready"
        }
    }

    var reasons: [StockReason] {
        switch self {
        case .addStock: return [.purchase, .found, .countCorrection]
        case .removeStock: return [.usedAtHome, .lostAtHome, .damaged, .countCorrection]
        case .sendToCare: return [.damaged, .countCorrection]
        case .markReady: return [.careCompleted, .countCorrection]
        }
    }

    var usesCare: Bool { self == .sendToCare || self == .markReady }
}

enum StockSource: String, CaseIterable, Identifiable {
    case ready, care
    var id: String { rawValue }
    var title: String { self == .ready ? "Ready" : "Needs Care" }
}

struct AdjustPreview: Equatable {
    var before: StockRules.Buckets
    var after: StockRules.Buckets
}

enum GearUseCases {
    static let maxNote = 2000

    static func validate(_ draft: GearDraft, isNew: Bool) -> [GearField: String] {
        var errors: [GearField: String] = [:]
        if let e = TextRules.check(draft.name, field: "Name", range: 1...80) { errors[.name] = e }
        if draft.countingUnit == .other, let e = TextRules.check(draft.customUnit, field: "Custom unit", range: 1...20) {
            errors[.customUnit] = e
        }
        if let e = TextRules.check(draft.storage, field: "Storage", range: 1...80) { errors[.storage] = e }
        if TextRules.trimmed(draft.note).count > maxNote { errors[.note] = "Notes can be up to \(maxNote) characters." }
        guard isNew else { return errors }
        guard let ready = draft.readyQty else {
            errors[.ready] = "Enter how many are ready."
            return errors
        }
        let care = draft.trackingType == .consumable ? 0 : (draft.careQty ?? 0)
        if !(0...StockRules.maxQuantity).contains(ready) { errors[.ready] = "Use a whole number from 0 to 9999." }
        if !(0...StockRules.maxQuantity).contains(care) { errors[.care] = "Use a whole number from 0 to 9999." }
        let total = ready + care
        if errors[.ready] == nil && errors[.care] == nil && !(1...StockRules.maxQuantity).contains(total) {
            errors[.total] = total == 0 ? "Add at least 1 item you actually own." : "A record can hold up to 9999 in total."
        }
        return errors
    }

    /// Neutral hint for repeated names; repeated names are allowed.
    static func duplicateNameHint(_ db: TBDatabase, draft: GearDraft) -> String? {
        let name = TextRules.trimmed(draft.name).lowercased()
        guard !name.isEmpty else { return nil }
        let match = db.gear.values.contains { $0.id != draft.id && $0.name.lowercased() == name }
        return match ? "You already have a record with this name. That's fine if you keep them separately." : nil
    }

    /// Creates the record together with its single Initial movement. Saving the same draft twice is a no-op.
    @discardableResult
    static func create(_ db: inout TBDatabase, draft: GearDraft, isDemo: Bool = false, sampleArt: String? = nil, now: Date) throws -> Gear {
        if let existing = db.gear[draft.id] { return existing }
        let errors = validate(draft, isNew: true)
        if let first = errors.first { throw DomainError.validation(first.value) }
        let ready = draft.readyQty ?? 0
        let care = draft.trackingType == .consumable ? 0 : (draft.careQty ?? 0)
        let gear = Gear(id: draft.id,
                        name: TextRules.trimmed(draft.name),
                        category: draft.category,
                        trackingType: draft.trackingType,
                        countingUnit: draft.countingUnit,
                        customUnit: draft.countingUnit == .other ? TextRules.trimmed(draft.customUnit) : nil,
                        storage: TextRules.trimmed(draft.storage),
                        note: TextRules.optional(draft.note),
                        photoID: draft.photoID,
                        sampleArt: sampleArt,
                        readyQty: 0,
                        careQty: 0,
                        outQty: 0,
                        stockRevision: 0,
                        isArchived: false,
                        isDemo: isDemo,
                        createdAt: now,
                        updatedAt: now)
        db.gear[gear.id] = gear
        try StockRules.record(&db, gearID: gear.id, operationID: gear.id, tripID: nil, kind: .added,
                              deltaReady: ready, deltaCare: care, deltaOut: 0, reason: nil, note: nil, now: now)
        return db.gear[gear.id]!
    }

    /// Edits the passport. Tracking type and counting unit are fixed after creation; stock is untouched.
    @discardableResult
    static func update(_ db: inout TBDatabase, draft: GearDraft, now: Date) throws -> Gear {
        guard var gear = db.gear[draft.id] else { throw DomainError.notFound("Gear is no longer available.") }
        let errors = validate(draft, isNew: false)
        if let first = errors.first { throw DomainError.validation(first.value) }
        gear.name = TextRules.trimmed(draft.name)
        gear.category = draft.category
        gear.storage = TextRules.trimmed(draft.storage)
        gear.note = TextRules.optional(draft.note)
        gear.photoID = draft.photoID
        gear.updatedAt = now
        db.gear[gear.id] = gear
        return gear
    }

    static func plannedTripsReferencing(_ db: TBDatabase, gearID: UUID) -> [Trip] {
        db.trips.values.filter { $0.status == .planned && $0.lines.contains { $0.gearID == gearID } }
            .sorted { $0.plannedDepartureAt < $1.plannedDepartureAt }
    }

    static func archiveBlockReason(_ db: TBDatabase, gearID: UUID) -> String? {
        guard let gear = db.gear[gearID] else { return "Gear is no longer available." }
        if gear.outQty > 0 { return "This gear is out on a trip. Return it before archiving." }
        let trips = plannedTripsReferencing(db, gearID: gearID)
        if let first = trips.first {
            return "Remove it from the planned trip “\(first.name)” first."
        }
        return nil
    }

    static func archive(_ db: inout TBDatabase, gearID: UUID, now: Date) throws {
        if let reason = archiveBlockReason(db, gearID: gearID) { throw DomainError.blocked(reason) }
        db.gear[gearID]?.isArchived = true
        db.gear[gearID]?.updatedAt = now
    }

    static func restore(_ db: inout TBDatabase, gearID: UUID, now: Date) throws {
        guard db.gear[gearID] != nil else { throw DomainError.notFound("Gear is no longer available.") }
        db.gear[gearID]?.isArchived = false
        db.gear[gearID]?.updatedAt = now
    }

    /// Hard delete is only for a record nobody references and that has nothing but its initial stock.
    static func deleteBlockReason(_ db: TBDatabase, gearID: UUID) -> String? {
        guard let gear = db.gear[gearID] else { return "Gear is no longer available." }
        if gear.outQty > 0 { return "This gear is out on a trip." }
        if db.kits.values.contains(where: { $0.lines.contains { $0.gearID == gearID } }) {
            return "A kit uses this gear. Archive it instead."
        }
        if db.trips.values.contains(where: { $0.lines.contains { $0.gearID == gearID } }) {
            return "A trip uses this gear. Archive it instead."
        }
        let moves = db.movements.values.filter { $0.gearID == gearID }
        if moves.count > 1 || moves.contains(where: { $0.kind != .added }) {
            return "This gear has stock history. Archive it instead."
        }
        return nil
    }

    /// Returns the photo that the caller should remove from disk after commit.
    @discardableResult
    static func delete(_ db: inout TBDatabase, gearID: UUID) throws -> UUID? {
        if let reason = deleteBlockReason(db, gearID: gearID) { throw DomainError.blocked(reason) }
        let photo = db.gear[gearID]?.photoID
        db.gear[gearID] = nil
        for m in db.movements.values where m.gearID == gearID { db.movements[m.id] = nil }
        if let photo = photo, !db.gear.values.contains(where: { $0.photoID == photo }) {
            db.photos[photo] = nil
            return photo
        }
        return nil
    }

    // MARK: Adjust stock

    static func preview(_ gear: Gear, operation: AdjustOperation, quantity: Int, source: StockSource) throws -> AdjustPreview {
        let before = StockRules.buckets(gear)
        guard (1...StockRules.maxQuantity).contains(quantity) else {
            throw DomainError.validation("Use a whole number from 1 to 9999.")
        }
        if gear.trackingType == .consumable && (operation.usesCare || (operation == .removeStock && source == .care)) {
            throw DomainError.validation("Consumable items don't use Needs Care.")
        }
        var after = before
        switch operation {
        case .addStock:
            after.ready += quantity
        case .removeStock:
            if source == .ready {
                guard quantity <= before.ready else { throw DomainError.validation("Only \(gear.unit.format(before.ready)) ready at home.") }
                after.ready -= quantity
            } else {
                guard quantity <= before.care else { throw DomainError.validation("Only \(gear.unit.format(before.care)) in Needs Care.") }
                after.care -= quantity
            }
        case .sendToCare:
            guard quantity <= before.ready else { throw DomainError.validation("Only \(gear.unit.format(before.ready)) ready at home.") }
            after.ready -= quantity
            after.care += quantity
        case .markReady:
            guard quantity <= before.care else { throw DomainError.validation("Only \(gear.unit.format(before.care)) in Needs Care.") }
            after.care -= quantity
            after.ready += quantity
        }
        if after.owned > StockRules.maxQuantity { throw DomainError.validation("A record can hold up to 9999 in total.") }
        return AdjustPreview(before: before, after: after)
    }

    /// One movement per confirmed adjustment. Out is never touched here.
    @discardableResult
    static func adjust(_ db: inout TBDatabase,
                       gearID: UUID,
                       operation: AdjustOperation,
                       quantity: Int,
                       source: StockSource,
                       reason: StockReason,
                       note: String?,
                       expectedRevision: Int64,
                       operationID: UUID,
                       tripID: UUID? = nil,
                       now: Date) throws -> StockMovement {
        if let done = db.movements.values.first(where: { $0.operationID == operationID && $0.gearID == gearID }) {
            return done
        }
        guard let gear = db.gear[gearID] else { throw DomainError.notFound("Gear is no longer available.") }
        guard operation.reasons.contains(reason) else { throw DomainError.validation("Choose a reason for this change.") }
        if TextRules.trimmed(note).count > 1000 { throw DomainError.validation("Notes can be up to 1000 characters.") }
        if gear.stockRevision != expectedRevision {
            throw DomainError.conflict("Stock changed while you were editing. Check the new preview and confirm again.")
        }
        let preview = try preview(gear, operation: operation, quantity: quantity, source: source)
        let kind: MovementKind
        switch operation {
        case .addStock: kind = .adjusted
        case .removeStock: kind = reason == .usedAtHome ? .used : (reason == .lostAtHome ? .lost : .adjusted)
        case .sendToCare: kind = .sentToCare
        case .markReady: kind = .markedReady
        }
        return try StockRules.record(&db, gearID: gearID, operationID: operationID, tripID: tripID, kind: kind,
                                     deltaReady: preview.after.ready - preview.before.ready,
                                     deltaCare: preview.after.care - preview.before.care,
                                     deltaOut: 0,
                                     reason: reason,
                                     note: TextRules.optional(note),
                                     now: now)
    }

    /// Needs Care → Ready. Owned stays the same.
    @discardableResult
    static func markReady(_ db: inout TBDatabase, gearID: UUID, quantity: Int, note: String?, expectedRevision: Int64, operationID: UUID, now: Date) throws -> StockMovement {
        try adjust(&db, gearID: gearID, operation: .markReady, quantity: quantity, source: .care, reason: .careCompleted,
                   note: note, expectedRevision: expectedRevision, operationID: operationID, now: now)
    }

    // MARK: Queries

    static func lastCareMovement(_ db: TBDatabase, gearID: UUID) -> StockMovement? {
        db.movements(for: gearID).first { $0.deltaCare > 0 }
    }
}
