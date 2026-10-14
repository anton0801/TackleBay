import Foundation

/// Stock invariants and the single place where buckets change together with the journal.
enum StockRules {
    static let maxQuantity = 9999

    struct Buckets: Equatable {
        var ready: Int
        var care: Int
        var out: Int
        var owned: Int { ready + care + out }
    }

    static func buckets(_ gear: Gear) -> Buckets {
        Buckets(ready: gear.readyQty, care: gear.careQty, out: gear.outQty)
    }

    static func validate(_ b: Buckets, tracking: TrackingType) -> String? {
        if b.ready < 0 || b.care < 0 || b.out < 0 { return "Quantities can't go below zero." }
        if b.owned > maxQuantity { return "A record can hold up to \(maxQuantity) units in total." }
        if tracking == .consumable && b.care != 0 { return "Consumable items don't use Needs Care." }
        return nil
    }

    /// Appends one immutable movement and applies its deltas in the same mutation.
    /// Callers run inside a store transaction, so either everything commits or nothing does.
    @discardableResult
    static func record(_ db: inout TBDatabase,
                       gearID: UUID,
                       operationID: UUID,
                       tripID: UUID?,
                       kind: MovementKind,
                       deltaReady: Int,
                       deltaCare: Int,
                       deltaOut: Int,
                       used: Int = 0,
                       lost: Int = 0,
                       reason: StockReason?,
                       note: String?,
                       now: Date) throws -> StockMovement {
        guard var gear = db.gear[gearID] else { throw DomainError.notFound("Gear is no longer available.") }
        if db.movements.values.contains(where: { $0.operationID == operationID && $0.gearID == gearID }) {
            throw DomainError.conflict("This change was already saved.")
        }
        let after = Buckets(ready: gear.readyQty + deltaReady, care: gear.careQty + deltaCare, out: gear.outQty + deltaOut)
        if let problem = validate(after, tracking: gear.trackingType) { throw DomainError.validation(problem) }

        gear.readyQty = after.ready
        gear.careQty = after.care
        gear.outQty = after.out
        gear.stockRevision += 1
        gear.updatedAt = now
        db.gear[gearID] = gear

        let movement = StockMovement(id: UUID(),
                                     operationID: operationID,
                                     sequence: db.counters.nextMovementSequence,
                                     gearID: gearID,
                                     tripID: tripID,
                                     kind: kind,
                                     deltaReady: deltaReady,
                                     deltaCare: deltaCare,
                                     deltaOut: deltaOut,
                                     usedQty: used,
                                     lostQty: lost,
                                     reason: reason,
                                     note: note,
                                     timestamp: now,
                                     gearNameSnapshot: gear.name,
                                     unitSnapshot: gear.unit)
        db.counters.nextMovementSequence += 1
        db.movements[movement.id] = movement
        return movement
    }

    /// Replays the journal of one gear strictly by sequence. Returns nil when an intermediate state is invalid.
    static func replay(_ movements: [StockMovement], tracking: TrackingType) -> Buckets? {
        var b = Buckets(ready: 0, care: 0, out: 0)
        for m in movements.sorted(by: { $0.sequence < $1.sequence }) {
            b.ready += m.deltaReady
            b.care += m.deltaCare
            b.out += m.deltaOut
            if validate(b, tracking: tracking) != nil { return nil }
        }
        return b
    }

    /// Full invariant check used by tests, debug launches and backup import.
    static func invariantProblems(_ db: TBDatabase) -> [String] {
        var problems: [String] = []
        var byGear: [UUID: [StockMovement]] = [:]
        for m in db.movements.values { byGear[m.gearID, default: []].append(m) }
        for m in db.movements.values where db.gear[m.gearID] == nil {
            problems.append("Movement \(m.id) points to a missing gear record.")
        }
        let open = db.trips.values.filter { $0.isOpenTrip }
        if open.count > 1 { problems.append("More than one trip is active or returning.") }
        for gear in db.gear.values {
            if let p = validate(buckets(gear), tracking: gear.trackingType) { problems.append("\(gear.name): \(p)") }
            guard let replayed = replay(byGear[gear.id] ?? [], tracking: gear.trackingType) else {
                problems.append("\(gear.name): journal has an invalid intermediate state.")
                continue
            }
            if replayed != buckets(gear) { problems.append("\(gear.name): journal does not match stock.") }
            let expectedOut = open.reduce(0) { sum, trip in
                sum + trip.lines.filter { $0.gearID == gear.id }.reduce(0) { $0 + ($1.takenQty ?? 0) }
            }
            if expectedOut != gear.outQty { problems.append("\(gear.name): Out does not match the active trip.") }
        }
        let sequences = db.movements.values.map(\.sequence)
        if Set(sequences).count != sequences.count { problems.append("Movement sequence numbers repeat.") }
        if let maxSeq = sequences.max(), maxSeq >= db.counters.nextMovementSequence {
            problems.append("Movement counter is behind the journal.")
        }
        var pairs = Set<String>()
        for m in db.movements.values {
            let key = "\(m.operationID)-\(m.gearID)"
            if !pairs.insert(key).inserted { problems.append("Operation \(m.operationID) touches one gear twice.") }
        }
        return problems
    }
}
