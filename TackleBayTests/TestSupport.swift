import XCTest
@testable import TackleBay

/// Builders shared by the domain tests. Everything runs on value-type databases, no UI.
enum Fixture {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func draft(_ name: String, tracking: TrackingType = .reusable, unit: CountingUnit = .piece,
                      ready: Int, care: Int = 0, category: GearCategory = .reels) -> GearDraft {
        var d = GearDraft()
        d.name = name
        d.category = category
        d.trackingType = tracking
        d.countingUnit = unit
        d.storage = "Shelf A"
        d.readyQty = ready
        d.careQty = care
        return d
    }

    @discardableResult
    static func gear(_ db: inout TBDatabase, _ name: String, tracking: TrackingType = .reusable, ready: Int, care: Int = 0,
                     now: Date = t0) throws -> Gear {
        try GearUseCases.create(&db, draft: draft(name, tracking: tracking, unit: tracking == .consumable ? .pack : .piece,
                                                  ready: ready, care: care), now: now)
    }

    @discardableResult
    static func plan(_ db: inout TBDatabase, name: String = "Harbor morning", lines: [(UUID, Int, Importance)], now: Date = t0) throws -> Trip {
        var d = TripDraft()
        d.name = name
        d.place = "Harbor pier"
        d.plannedDepartureAt = now
        d.lines = lines.map { TripLine(id: UUID(), gearID: $0.0, requiredQty: $0.1, packedQty: 0, importance: $0.2,
                                       packingNote: nil, snapshot: nil, takenQty: nil) }
        return try TripUseCases.create(&db, draft: d, now: now)
    }

    static func pack(_ db: inout TBDatabase, trip: UUID, gear: UUID, qty: Int, now: Date = t0) throws {
        let line = db.trips[trip]!.lines.first { $0.gearID == gear }!
        try TripUseCases.setPacked(&db, tripID: trip, lineID: line.id, packed: qty, now: now)
    }

    @discardableResult
    static func start(_ db: inout TBDatabase, trip: UUID, note: String? = nil, op: UUID = UUID(), now: Date = t0) throws -> Trip {
        try TripUseCases.start(&db, tripID: trip, expectedRevision: db.trips[trip]!.revision, missingNote: note, operationID: op, now: now)
    }

    static func line(_ db: TBDatabase, trip: UUID, gear: UUID) -> TripLine {
        db.trips[trip]!.lines.first { $0.gearID == gear }!
    }

    static func assertInvariants(_ db: TBDatabase, file: StaticString = #filePath, line: UInt = #line) {
        let problems = StockRules.invariantProblems(db) + BonusUseCases.ledgerProblems(db)
        XCTAssertTrue(problems.isEmpty, "Invariant problems: \(problems)", file: file, line: line)
    }
}
