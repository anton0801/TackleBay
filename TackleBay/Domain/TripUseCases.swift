import Foundation

struct TripDraft: Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var place: String = ""
    var plannedDepartureAt: Date = Date()
    var note: String = ""
    var initialKitID: UUID?
    var isDemo = false
    /// Pre-filled rows (Repeat Trip). All packed values are zero.
    var lines: [TripLine] = []

    init() {}

    init(trip: Trip) {
        id = trip.id
        name = trip.name
        place = trip.place
        plannedDepartureAt = trip.plannedDepartureAt
        note = trip.note ?? ""
        isDemo = trip.isDemo
        lines = trip.lines
    }
}

struct KitMergeRow: Identifiable, Equatable {
    var id: UUID { gearID }
    let gearID: UUID
    let name: String
    let existing: Int?
    let added: Int
    let result: Int
    let importance: Importance
    let capped: Bool
}

struct KitMergePreview: Equatable {
    var rows: [KitMergeRow]
    var unavailable: [String]
    var sampleMismatch: Bool
    var overflow: Bool
    var hasMerges: Bool { rows.contains { $0.existing != nil } }
}

struct PackingProgress: Equatable {
    let packed: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }
    var text: String { total == 0 ? "No required items" : "\(packed) of \(total) essentials packed" }
}

struct DepartureReview: Equatable {
    var progress: PackingProgress
    var missingRequired: [TripLine]
    var packedLines: [TripLine]
    var blockers: [String]
    var conflictTrips: [String]
    var canStart: Bool { blockers.isEmpty }
    var needsMissingNote: Bool { !missingRequired.isEmpty }
}

enum TripUseCases {
    static let maxLines = 100

    // MARK: Queries

    static func progress(_ trip: Trip) -> PackingProgress {
        let required = trip.lines.filter { $0.importance == .required }
        let packed = required.filter { $0.packedQty >= $0.requiredQty }.count
        return PackingProgress(packed: packed, total: required.count)
    }

    static func lineName(_ db: TBDatabase, _ line: TripLine) -> String {
        line.snapshot?.name ?? db.gear[line.gearID]?.name ?? "Unavailable gear"
    }

    static func lineUnit(_ db: TBDatabase, _ line: TripLine) -> UnitLabel {
        line.snapshot?.unit ?? db.gear[line.gearID]?.unit ?? UnitLabel(singular: "unit", plural: "units")
    }

    static func isLineAvailable(_ db: TBDatabase, _ line: TripLine) -> Bool {
        KitUseCases.isAvailable(db, gearID: line.gearID)
    }

    /// Active trip wins; otherwise the earliest planned date, including dates that already passed.
    static func homeTrip(_ db: TBDatabase) -> Trip? {
        if let open = db.openTrip { return open }
        return db.trips.values.filter { $0.status == .planned }
            .sorted { ($0.plannedDepartureAt, $0.id.uuidString) < ($1.plannedDepartureAt, $1.id.uuidString) }
            .first
    }

    /// Other plans on the same day sharing gear. Plans never reserve stock, this is only a warning.
    static func dateConflicts(_ db: TBDatabase, trip: Trip, calendar: Calendar = .current) -> [Trip] {
        let gearIDs = Set(trip.lines.map(\.gearID))
        return db.trips.values.filter { other in
            other.id != trip.id && other.status == .planned
                && calendar.isDate(other.plannedDepartureAt, inSameDayAs: trip.plannedDepartureAt)
                && !gearIDs.isDisjoint(with: other.lines.map(\.gearID))
        }.sorted { $0.plannedDepartureAt < $1.plannedDepartureAt }
    }

    // MARK: Plans

    static func validate(_ draft: TripDraft) -> String? {
        if let e = TextRules.check(draft.name, field: "Trip name", range: 1...80) { return e }
        if let e = TextRules.check(draft.place, field: "Place", range: 1...100) { return e }
        if TextRules.trimmed(draft.note).count > 2000 { return "Notes can be up to 2000 characters." }
        return nil
    }

    @discardableResult
    static func create(_ db: inout TBDatabase, draft: TripDraft, now: Date) throws -> Trip {
        if let existing = db.trips[draft.id] { return existing }
        if let e = validate(draft) { throw DomainError.validation(e) }
        var lines: [TripLine] = draft.lines.map {
            TripLine(id: UUID(), gearID: $0.gearID, requiredQty: $0.requiredQty, packedQty: 0, importance: $0.importance,
                     packingNote: $0.packingNote, snapshot: nil, takenQty: nil)
        }
        if let kitID = draft.initialKitID {
            guard let kit = db.kits[kitID] else { throw DomainError.notFound("This kit is no longer available.") }
            if kit.isDemo != draft.isDemo {
                throw DomainError.validation(draft.isDemo ? "The sample trip can only use the sample kit." : "Sample kits stay in the sample collection. Choose one of your kits.")
            }
            for kl in kit.lines where KitUseCases.isAvailable(db, gearID: kl.gearID) {
                if let i = lines.firstIndex(where: { $0.gearID == kl.gearID }) {
                    lines[i].requiredQty = min(StockRules.maxQuantity, lines[i].requiredQty + kl.requiredQty)
                    if kl.importance == .required { lines[i].importance = .required }
                } else {
                    lines.append(TripLine(id: UUID(), gearID: kl.gearID, requiredQty: kl.requiredQty, packedQty: 0,
                                          importance: kl.importance, packingNote: kl.note, snapshot: nil, takenQty: nil))
                }
            }
        }
        if lines.count > maxLines { throw DomainError.validation("A packing list can hold up to \(maxLines) items.") }
        let trip = Trip(id: draft.id, name: TextRules.trimmed(draft.name), place: TextRules.trimmed(draft.place),
                        plannedDepartureAt: draft.plannedDepartureAt, status: .planned, note: TextRules.optional(draft.note),
                        isDemo: draft.isDemo, isHidden: false, revision: 1, createdAt: now, updatedAt: now,
                        startedAt: nil, endedAt: nil, cancelledAt: nil, startOperationID: nil, returnOperationID: nil,
                        startedName: nil, startedPlace: nil, missingItemsNote: nil, lines: lines, liveNotes: [], personalNote: nil)
        db.trips[trip.id] = trip
        return trip
    }

    static func updatePlan(_ db: inout TBDatabase, draft: TripDraft, now: Date) throws {
        guard var trip = db.trips[draft.id] else { throw DomainError.notFound("This trip is no longer available.") }
        guard trip.status == .planned else { throw DomainError.blocked("Only planned trips can be edited.") }
        if let e = validate(draft) { throw DomainError.validation(e) }
        trip.name = TextRules.trimmed(draft.name)
        trip.place = TextRules.trimmed(draft.place)
        trip.plannedDepartureAt = draft.plannedDepartureAt
        trip.note = TextRules.optional(draft.note)
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    private static func touch(_ trip: inout Trip, _ now: Date) {
        trip.revision += 1
        trip.updatedAt = now
    }

    private static func plannedTrip(_ db: TBDatabase, _ tripID: UUID) throws -> Trip {
        guard let trip = db.trips[tripID] else { throw DomainError.notFound("This trip is no longer available.") }
        guard trip.status == .planned else { throw DomainError.blocked("The packing list is fixed once the trip starts.") }
        return trip
    }

    private static func checkGearForTrip(_ db: TBDatabase, trip: Trip, gearID: UUID) throws {
        guard let gear = db.gear[gearID], !gear.isArchived else { throw DomainError.validation("This gear is unavailable.") }
        if gear.isDemo != trip.isDemo {
            throw DomainError.validation(trip.isDemo ? "The sample trip can only use sample gear." : "Sample gear stays in the sample collection. Pick your own gear.")
        }
    }

    /// Adds a row or returns the existing one for the same gear (rows are unique by gear).
    @discardableResult
    static func addGear(_ db: inout TBDatabase, tripID: UUID, gearID: UUID, now: Date) throws -> UUID {
        var trip = try plannedTrip(db, tripID)
        if let existing = trip.lines.first(where: { $0.gearID == gearID }) { return existing.id }
        try checkGearForTrip(db, trip: trip, gearID: gearID)
        guard trip.lines.count < maxLines else { throw DomainError.validation("A packing list can hold up to \(maxLines) items.") }
        let line = TripLine(id: UUID(), gearID: gearID, requiredQty: 1, packedQty: 0, importance: .required,
                            packingNote: nil, snapshot: nil, takenQty: nil)
        trip.lines.append(line)
        touch(&trip, now)
        db.trips[trip.id] = trip
        return line.id
    }

    static func updateLine(_ db: inout TBDatabase, tripID: UUID, lineID: UUID, required: Int, packed: Int,
                           importance: Importance, note: String?, now: Date) throws {
        var trip = try plannedTrip(db, tripID)
        guard let i = trip.lines.firstIndex(where: { $0.id == lineID }) else { throw DomainError.notFound("This row is no longer in the list.") }
        guard (1...StockRules.maxQuantity).contains(required) else { throw DomainError.validation("Required must be from 1 to 9999.") }
        guard (0...required).contains(packed) else { throw DomainError.validation("Packed can be from 0 to \(required).") }
        if TextRules.trimmed(note).count > 300 { throw DomainError.validation("Packing notes can be up to 300 characters.") }
        trip.lines[i].requiredQty = required
        trip.lines[i].packedQty = packed
        trip.lines[i].importance = importance
        trip.lines[i].packingNote = TextRules.optional(note)
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    static func setPacked(_ db: inout TBDatabase, tripID: UUID, lineID: UUID, packed: Int, now: Date) throws {
        var trip = try plannedTrip(db, tripID)
        guard let i = trip.lines.firstIndex(where: { $0.id == lineID }) else { throw DomainError.notFound("This row is no longer in the list.") }
        guard (0...trip.lines[i].requiredQty).contains(packed) else {
            throw DomainError.validation("Packed can be from 0 to \(trip.lines[i].requiredQty).")
        }
        if packed > 0 && !isLineAvailable(db, trip.lines[i]) {
            throw DomainError.validation("This gear is unavailable. Remove or replace it first.")
        }
        trip.lines[i].packedQty = packed
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    static func removeLine(_ db: inout TBDatabase, tripID: UUID, lineID: UUID, now: Date) throws {
        var trip = try plannedTrip(db, tripID)
        trip.lines.removeAll { $0.id == lineID }
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    /// Resolves an unavailable row by pointing it at another record; quantities and importance stay.
    static func replaceLine(_ db: inout TBDatabase, tripID: UUID, lineID: UUID, gearID: UUID, now: Date) throws {
        var trip = try plannedTrip(db, tripID)
        guard let i = trip.lines.firstIndex(where: { $0.id == lineID }) else { throw DomainError.notFound("This row is no longer in the list.") }
        try checkGearForTrip(db, trip: trip, gearID: gearID)
        if trip.lines.contains(where: { $0.gearID == gearID && $0.id != lineID }) {
            throw DomainError.validation("This gear is already in the list.")
        }
        trip.lines[i].gearID = gearID
        trip.lines[i].packedQty = 0
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    static func mergePreview(_ db: TBDatabase, tripID: UUID, kitID: UUID) -> KitMergePreview? {
        guard let trip = db.trips[tripID], let kit = db.kits[kitID] else { return nil }
        var rows: [KitMergeRow] = []
        var unavailable: [String] = []
        var newRows = 0
        for kl in kit.lines {
            guard KitUseCases.isAvailable(db, gearID: kl.gearID), let gear = db.gear[kl.gearID] else {
                unavailable.append(db.gear[kl.gearID]?.name ?? "Unavailable gear")
                continue
            }
            if let existing = trip.lines.first(where: { $0.gearID == kl.gearID }) {
                let sum = existing.requiredQty + kl.requiredQty
                let importance: Importance = (existing.importance == .required || kl.importance == .required) ? .required : .optional
                rows.append(KitMergeRow(gearID: gear.id, name: gear.name, existing: existing.requiredQty, added: kl.requiredQty,
                                        result: min(sum, StockRules.maxQuantity), importance: importance, capped: sum > StockRules.maxQuantity))
            } else {
                newRows += 1
                rows.append(KitMergeRow(gearID: gear.id, name: gear.name, existing: nil, added: kl.requiredQty,
                                        result: kl.requiredQty, importance: kl.importance, capped: false))
            }
        }
        return KitMergePreview(rows: rows, unavailable: unavailable, sampleMismatch: kit.isDemo != trip.isDemo,
                               overflow: trip.lines.count + newRows > maxLines)
    }

    /// Adds only available kit rows. Matching rows sum Required (capped at 9999); Packed never grows automatically.
    static func applyKit(_ db: inout TBDatabase, tripID: UUID, kitID: UUID, now: Date) throws {
        var trip = try plannedTrip(db, tripID)
        guard let kit = db.kits[kitID], let preview = mergePreview(db, tripID: tripID, kitID: kitID) else {
            throw DomainError.notFound("This kit is no longer available.")
        }
        if preview.sampleMismatch {
            throw DomainError.validation(trip.isDemo ? "The sample trip can only use the sample kit." : "Sample kits stay in the sample collection. Choose one of your kits.")
        }
        if preview.overflow { throw DomainError.validation("A packing list can hold up to \(maxLines) items.") }
        for row in preview.rows {
            if let i = trip.lines.firstIndex(where: { $0.gearID == row.gearID }) {
                trip.lines[i].requiredQty = row.result
                trip.lines[i].importance = row.importance
            } else if let kl = kit.lines.first(where: { $0.gearID == row.gearID }) {
                trip.lines.append(TripLine(id: UUID(), gearID: kl.gearID, requiredQty: kl.requiredQty, packedQty: 0,
                                           importance: kl.importance, packingNote: kl.note, snapshot: nil, takenQty: nil))
            }
        }
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    // MARK: Departure

    static func departureReview(_ db: TBDatabase, tripID: UUID) -> DepartureReview? {
        guard let trip = db.trips[tripID] else { return nil }
        var blockers: [String] = []
        if trip.status != .planned { blockers.append("This trip has already started.") }
        if let open = db.openTrip, open.id != trip.id { blockers.append("Finish “\(open.displayName)” before starting another trip.") }
        let packed = trip.lines.filter { $0.packedQty > 0 }
        if packed.isEmpty { blockers.append("Pack at least one item to start.") }
        for line in packed {
            guard let gear = db.gear[line.gearID], !gear.isArchived else {
                blockers.append("\(lineName(db, line)) is unavailable. Remove or replace it.")
                continue
            }
            if line.packedQty > gear.readyQty {
                blockers.append("Only \(gear.unit.format(gear.readyQty)) of \(gear.name) ready at home.")
            }
        }
        let missing = trip.lines.filter { $0.importance == .required && $0.packedQty < $0.requiredQty }
        return DepartureReview(progress: progress(trip), missingRequired: missing, packedLines: packed, blockers: blockers,
                               conflictTrips: dateConflicts(db, trip: trip).map(\.name))
    }

    /// Moves every packed unit Ready → Out in one transaction. Any shortage cancels the whole start.
    @discardableResult
    static func start(_ db: inout TBDatabase, tripID: UUID, expectedRevision: Int64, missingNote: String?,
                      operationID: UUID, now: Date) throws -> Trip {
        guard var trip = db.trips[tripID] else { throw DomainError.notFound("This trip is no longer available.") }
        if trip.startOperationID == operationID && trip.status != .planned { return trip }
        guard trip.status == .planned else { throw DomainError.blocked("This trip has already started.") }
        if trip.revision != expectedRevision {
            throw DomainError.conflict("The packing list changed. Review it again before starting.")
        }
        guard let review = departureReview(db, tripID: tripID) else { throw DomainError.notFound("This trip is no longer available.") }
        if let blocker = review.blockers.first { throw DomainError.blocked(blocker) }
        var note: String?
        if review.needsMissingNote {
            if let e = TextRules.check(missingNote, field: "A note about missing items", range: 1...300) { throw DomainError.validation(e) }
            note = TextRules.trimmed(missingNote)
        }
        for i in trip.lines.indices {
            let line = trip.lines[i]
            if let gear = db.gear[line.gearID] {
                trip.lines[i].snapshot = LineSnapshot(name: gear.name, category: gear.category, trackingType: gear.trackingType,
                                                      unit: gear.unit, storage: gear.storage)
            }
            trip.lines[i].takenQty = line.packedQty
            guard line.packedQty > 0 else { continue }
            try StockRules.record(&db, gearID: line.gearID, operationID: operationID, tripID: tripID, kind: .takenOnTrip,
                                  deltaReady: -line.packedQty, deltaCare: 0, deltaOut: line.packedQty,
                                  reason: nil, note: nil, now: now)
        }
        trip.status = .active
        trip.startedAt = now
        trip.startOperationID = operationID
        trip.startedName = trip.name
        trip.startedPlace = trip.place
        trip.missingItemsNote = note
        touch(&trip, now)
        db.trips[trip.id] = trip
        return trip
    }

    // MARK: Active trip

    static func addLiveNote(_ db: inout TBDatabase, tripID: UUID, text: String, now: Date) throws {
        guard var trip = db.trips[tripID] else { throw DomainError.notFound("This trip is no longer available.") }
        guard trip.isOpenTrip else { throw DomainError.blocked("Notes can be added while the trip is on.") }
        if let e = TextRules.check(text, field: "Note", range: 1...2000) { throw DomainError.validation(e) }
        trip.liveNotes.append(TripNote(id: UUID(), text: TextRules.trimmed(text), createdAt: now))
        trip.updatedAt = now
        db.trips[trip.id] = trip
    }

    // MARK: Return

    /// Switches to Returning and creates the single draft. Stock is untouched until Confirm Return.
    @discardableResult
    static func beginReturn(_ db: inout TBDatabase, tripID: UUID, now: Date) throws -> ReturnDraft {
        guard var trip = db.trips[tripID] else { throw DomainError.notFound("This trip is no longer available.") }
        if trip.status == .returning, let draft = db.draft(for: tripID) { return draft }
        guard trip.status == .active else { throw DomainError.blocked("Only an active trip can be returned.") }
        touch(&trip, now)
        trip.status = .returning
        db.trips[trip.id] = trip
        let entries = trip.lines.filter { ($0.takenQty ?? 0) > 0 }.map {
            ReturnEntry(tripLineID: $0.id, returnedQty: 0, careQty: 0, usedQty: 0, lostQty: 0, confirmed: false)
        }
        let draft = ReturnDraft(id: UUID(), tripID: tripID, operationID: UUID(), sourceTripRevision: trip.revision,
                                endAt: now, summaryNote: nil, lossNote: nil, entries: entries)
        db.returnDrafts[draft.id] = draft
        return draft
    }

    static func continueTrip(_ db: inout TBDatabase, tripID: UUID, now: Date) throws {
        guard var trip = db.trips[tripID], trip.status == .returning else { throw DomainError.blocked("This trip isn't being returned.") }
        if let draft = db.draft(for: tripID) { db.returnDrafts[draft.id] = nil }
        trip.status = .active
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    private static func returningContext(_ db: TBDatabase, tripID: UUID) throws -> (Trip, ReturnDraft) {
        guard let trip = db.trips[tripID] else { throw DomainError.notFound("This trip is no longer available.") }
        guard trip.status == .returning, let draft = db.draft(for: tripID) else { throw DomainError.blocked("Start Return Gear first.") }
        return (trip, draft)
    }

    static func validateEntry(_ entry: ReturnEntry, taken: Int, tracking: TrackingType) -> String? {
        let values = [entry.returnedQty, entry.careQty, entry.usedQty, entry.lostQty]
        if values.contains(where: { $0 < 0 || $0 > taken }) { return "Use whole numbers from 0 to \(taken)." }
        if tracking == .reusable && entry.usedQty != 0 { return "Reusable gear can't be marked as used." }
        if tracking == .consumable && entry.careQty != 0 { return "Consumable items don't use Needs Care." }
        if entry.resolved > taken { return "That's more than the \(taken) taken." }
        return nil
    }

    /// Any change to the numbers removes the row confirmation.
    static func updateEntry(_ db: inout TBDatabase, tripID: UUID, lineID: UUID, returned: Int, care: Int, used: Int, lost: Int) throws {
        let (trip, original) = try returningContext(db, tripID: tripID)
        var draft = original
        guard let line = trip.lines.first(where: { $0.id == lineID }), let taken = line.takenQty,
              let i = draft.entries.firstIndex(where: { $0.tripLineID == lineID }) else {
            throw DomainError.notFound("This row is no longer in the return.")
        }
        let tracking = line.snapshot?.trackingType ?? db.gear[line.gearID]?.trackingType ?? .reusable
        let entry = ReturnEntry(tripLineID: lineID, returnedQty: returned, careQty: care, usedQty: used, lostQty: lost, confirmed: false)
        if let e = validateEntry(entry, taken: taken, tracking: tracking) { throw DomainError.validation(e) }
        draft.entries[i] = entry
        db.returnDrafts[draft.id] = draft
    }

    static func confirmRow(_ db: inout TBDatabase, tripID: UUID, lineID: UUID) throws {
        let (trip, original) = try returningContext(db, tripID: tripID)
        var draft = original
        guard let line = trip.lines.first(where: { $0.id == lineID }), let taken = line.takenQty,
              let i = draft.entries.firstIndex(where: { $0.tripLineID == lineID }) else {
            throw DomainError.notFound("This row is no longer in the return.")
        }
        let remaining = taken - draft.entries[i].resolved
        guard remaining == 0 else { throw DomainError.validation("\(remaining) still need an outcome.") }
        draft.entries[i].confirmed = true
        db.returnDrafts[draft.id] = draft
    }

    static func updateReturnDetails(_ db: inout TBDatabase, tripID: UUID, endAt: Date, summaryNote: String?, lossNote: String?) throws {
        var draft = try returningContext(db, tripID: tripID).1
        draft.endAt = endAt
        draft.summaryNote = summaryNote
        draft.lossNote = lossNote
        db.returnDrafts[draft.id] = draft
    }

    static func remaining(_ db: TBDatabase, trip: Trip, draft: ReturnDraft) -> Int {
        trip.lines.reduce(0) { sum, line in
            guard let taken = line.takenQty, taken > 0 else { return sum }
            return sum + taken - (draft.entry(for: line.id)?.resolved ?? 0)
        }
    }

    static func returnProblems(_ db: TBDatabase, tripID: UUID, now: Date) -> [String] {
        guard let trip = db.trips[tripID], let draft = db.draft(for: tripID) else { return ["Start Return Gear first."] }
        var problems: [String] = []
        for line in trip.lines {
            guard let taken = line.takenQty, taken > 0 else { continue }
            let entry = draft.entry(for: line.id)
            if (entry?.resolved ?? 0) != taken || entry?.confirmed != true {
                problems.append("Account for every item before finishing.")
                break
            }
        }
        if let started = trip.startedAt {
            if draft.endAt < started { problems.append("End time can't be before the trip started.") }
            if draft.endAt > now.addingTimeInterval(60) { problems.append("End time can't be in the future.") }
        }
        let lost = draft.entries.reduce(0) { $0 + $1.lostQty }
        if lost > 0, let e = TextRules.check(draft.lossNote, field: "A note about lost items", range: 1...1000) { problems.append(e) }
        if TextRules.trimmed(draft.summaryNote).count > 2000 { problems.append("Summary note can be up to 2000 characters.") }
        return problems
    }

    /// Closes the trip and applies every distribution in one transaction, once per operationID.
    @discardableResult
    static func confirmReturn(_ db: inout TBDatabase, tripID: UUID, now: Date) throws -> TripReturnResult {
        if let done = db.result(for: tripID) { return done }
        let (trip, draft) = try returningContext(db, tripID: tripID)
        if let problem = returnProblems(db, tripID: tripID, now: now).first { throw DomainError.validation(problem) }
        var entries: [ReturnResultEntry] = []
        for line in trip.lines {
            guard let taken = line.takenQty, taken > 0, let entry = draft.entry(for: line.id) else { continue }
            guard let gear = db.gear[line.gearID] else { throw DomainError.notFound("Gear is no longer available.") }
            if gear.outQty < taken {
                throw DomainError.conflict("Stock changed for \(gear.name). Check the return again.")
            }
            let tracking = line.snapshot?.trackingType ?? gear.trackingType
            if let e = validateEntry(entry, taken: taken, tracking: tracking) { throw DomainError.validation(e) }
            try StockRules.record(&db, gearID: line.gearID, operationID: draft.operationID, tripID: tripID, kind: .returned,
                                  deltaReady: entry.returnedQty, deltaCare: entry.careQty, deltaOut: -taken,
                                  used: entry.usedQty, lost: entry.lostQty, reason: nil, note: nil, now: now)
            let snapshot = line.snapshot ?? LineSnapshot(name: gear.name, category: gear.category, trackingType: gear.trackingType,
                                                         unit: gear.unit, storage: gear.storage)
            entries.append(ReturnResultEntry(tripLineID: line.id, gearID: line.gearID, snapshot: snapshot, taken: taken,
                                             returned: entry.returnedQty, care: entry.careQty, used: entry.usedQty, lost: entry.lostQty))
        }
        let result = TripReturnResult(id: UUID(), tripID: tripID, operationID: draft.operationID, endedAt: draft.endAt,
                                      entries: entries, summaryNote: TextRules.optional(draft.summaryNote),
                                      lossNote: TextRules.optional(draft.lossNote))
        var closed = trip
        closed.status = .completed
        closed.endedAt = draft.endAt
        closed.returnOperationID = draft.operationID
        touch(&closed, now)
        db.trips[tripID] = closed
        db.returnResults[result.id] = result
        db.returnDrafts[draft.id] = nil
        return result
    }

    // MARK: History

    static func cancelPlan(_ db: inout TBDatabase, tripID: UUID, now: Date) throws {
        var trip = try plannedTrip(db, tripID)
        trip.status = .cancelled
        trip.cancelledAt = now
        touch(&trip, now)
        db.trips[trip.id] = trip
    }

    static func deleteBlockReason(_ db: TBDatabase, tripID: UUID) -> String? {
        guard let trip = db.trips[tripID] else { return "This trip is no longer available." }
        switch trip.status {
        case .planned, .cancelled:
            if db.movements.values.contains(where: { $0.tripID == tripID }) { return "This trip has stock history." }
            return nil
        case .completed: return "Completed trips keep their stock history. Hide it from History instead."
        case .active, .returning: return "Finish the trip first."
        }
    }

    static func deleteTrip(_ db: inout TBDatabase, tripID: UUID) throws {
        if let reason = deleteBlockReason(db, tripID: tripID) { throw DomainError.blocked(reason) }
        db.trips[tripID] = nil
    }

    static func setHidden(_ db: inout TBDatabase, tripID: UUID, hidden: Bool, now: Date) throws {
        guard var trip = db.trips[tripID], trip.status == .completed || trip.status == .cancelled else {
            throw DomainError.blocked("Only finished trips can be hidden.")
        }
        trip.isHidden = hidden
        trip.updatedAt = now
        db.trips[trip.id] = trip
    }

    static func setPersonalNote(_ db: inout TBDatabase, tripID: UUID, text: String, now: Date) throws {
        guard var trip = db.trips[tripID], trip.status == .completed || trip.status == .cancelled else {
            throw DomainError.blocked("Personal notes are for finished trips.")
        }
        if TextRules.trimmed(text).count > 2000 { throw DomainError.validation("Notes can be up to 2000 characters.") }
        trip.personalNote = TextRules.optional(text)
        trip.updatedAt = now
        db.trips[trip.id] = trip
    }

    /// New planned draft: same place, the rows that were actually taken (or planned) with their original Required, nothing packed.
    static func repeatDraft(_ db: TBDatabase, tripID: UUID, now: Date) -> TripDraft? {
        guard let trip = db.trips[tripID] else { return nil }
        var draft = TripDraft()
        draft.name = String((trip.displayName + " copy").prefix(80))
        draft.place = trip.displayPlace
        draft.plannedDepartureAt = now
        draft.isDemo = trip.isDemo
        let source = trip.status == .completed ? trip.lines.filter { ($0.takenQty ?? 0) > 0 } : trip.lines
        draft.lines = source.map {
            TripLine(id: UUID(), gearID: $0.gearID, requiredQty: $0.requiredQty, packedQty: 0, importance: $0.importance,
                     packingNote: $0.packingNote, snapshot: nil, takenQty: nil)
        }
        return draft
    }
}
