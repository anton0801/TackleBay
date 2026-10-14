import XCTest
@testable import TackleBay

final class StockTests: XCTestCase {
    // AC 02: creating gear writes exactly one Initial movement; saving again doesn't add stock twice.
    func testCreateGearWritesSingleInitialMovementAndIsIdempotent() throws {
        var db = TBDatabase()
        let draft = Fixture.draft("Tide reel", ready: 3, care: 1)
        let gear = try GearUseCases.create(&db, draft: draft, now: Fixture.t0)
        try GearUseCases.create(&db, draft: draft, now: Fixture.t0)
        XCTAssertEqual(db.gear.count, 1)
        XCTAssertEqual(db.movements.count, 1)
        let m = try XCTUnwrap(db.movements.values.first)
        XCTAssertEqual(m.kind, .added)
        XCTAssertEqual(m.deltaReady, 3)
        XCTAssertEqual(m.deltaCare, 1)
        XCTAssertEqual(db.gear[gear.id]?.ownedQty, 4)
        Fixture.assertInvariants(db)
    }

    func testGearValidation() {
        var d = Fixture.draft("", ready: 0)
        XCTAssertNotNil(GearUseCases.validate(d, isNew: true)[.name])
        XCTAssertNotNil(GearUseCases.validate(d, isNew: true)[.total], "Total must be at least 1")
        d.name = "Rod"
        d.readyQty = nil
        XCTAssertNotNil(GearUseCases.validate(d, isNew: true)[.ready], "Ready starts empty and is required")
        d.readyQty = 9999
        d.careQty = 1
        XCTAssertNotNil(GearUseCases.validate(d, isNew: true)[.total], "Sum can't exceed 9999")
        d.careQty = 0
        d.countingUnit = .other
        d.customUnit = ""
        XCTAssertNotNil(GearUseCases.validate(d, isNew: true)[.customUnit])
    }

    func testConsumableNeverHasCare() throws {
        var db = TBDatabase()
        var d = Fixture.draft("Hooks", tracking: .consumable, unit: .pack, ready: 5, care: 3)
        let g = try GearUseCases.create(&db, draft: d, now: Fixture.t0)
        XCTAssertEqual(db.gear[g.id]?.careQty, 0)
        d = GearDraft(gear: db.gear[g.id]!)
        XCTAssertThrowsError(try GearUseCases.adjust(&db, gearID: g.id, operation: .sendToCare, quantity: 1, source: .ready,
                                                     reason: .damaged, note: nil, expectedRevision: db.gear[g.id]!.stockRevision,
                                                     operationID: UUID(), now: Fixture.t0))
    }

    // AC 04: Reusable 3/1 → take 2 → 1/1/2 → return 1 ready, 1 care → 2/2/0 → mark ready 1 → 3/1.
    func testReusableScenarioFromSpec() throws {
        var db = TBDatabase()
        let g = try Fixture.gear(&db, "Tide reel", ready: 3, care: 1)
        let trip = try Fixture.plan(&db, lines: [(g.id, 2, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: g.id, qty: 2)
        try Fixture.start(&db, trip: trip.id)
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 1, care: 1, out: 2))
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0.addingTimeInterval(3600))
        let line = Fixture.line(db, trip: trip.id, gear: g.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: line.id, returned: 1, care: 1, used: 0, lost: 0)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: line.id)
        try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0.addingTimeInterval(3600))
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 2, care: 2, out: 0))
        XCTAssertEqual(db.gear[g.id]!.ownedQty, 4)
        let gear = db.gear[g.id]!
        try GearUseCases.markReady(&db, gearID: g.id, quantity: 1, note: "Cleaned", expectedRevision: gear.stockRevision,
                                   operationID: UUID(), now: Fixture.t0.addingTimeInterval(7200))
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 3, care: 1, out: 0))
        Fixture.assertInvariants(db)
    }

    // AC 04 + AC 08: Consumable 12 → take 5 → 7/5 → 2 back, 2 used, 1 lost → 9; a second confirm changes nothing.
    func testConsumableScenarioFromSpecAndIdempotentConfirm() throws {
        var db = TBDatabase()
        let g = try Fixture.gear(&db, "Hook packs", tracking: .consumable, ready: 12)
        let trip = try Fixture.plan(&db, lines: [(g.id, 5, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: g.id, qty: 5)
        try Fixture.start(&db, trip: trip.id)
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 7, care: 0, out: 5))
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0.addingTimeInterval(60))
        let line = Fixture.line(db, trip: trip.id, gear: g.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: line.id, returned: 2, care: 0, used: 2, lost: 1)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: line.id)
        try TripUseCases.updateReturnDetails(&db, tripID: trip.id, endAt: Fixture.t0.addingTimeInterval(60), summaryNote: nil, lossNote: "Snagged")
        try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0.addingTimeInterval(60))
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 9, care: 0, out: 0))
        let movementCount = db.movements.count
        try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0.addingTimeInterval(120))
        XCTAssertEqual(db.movements.count, movementCount)
        XCTAssertEqual(db.gear[g.id]!.readyQty, 9)
        Fixture.assertInvariants(db)
    }

    // AC 03: plans, kits and packed values never touch stock.
    func testPlansKitsAndPackingDontChangeStock() throws {
        var db = TBDatabase()
        let g = try Fixture.gear(&db, "Rod", ready: 2)
        var kit = KitDraft()
        kit.name = "Shore"
        kit.lines = [KitLine(id: UUID(), gearID: g.id, requiredQty: 5, importance: .required, note: nil)]
        try KitUseCases.save(&db, draft: kit, now: Fixture.t0)
        let trip = try Fixture.plan(&db, lines: [(g.id, 2, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: g.id, qty: 2)
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 2, care: 0, out: 0))
        XCTAssertEqual(db.movements.count, 1)
    }

    // AC 09: Adjust Stock can't edit Out, can't overdraw, and needs a fresh revision.
    func testAdjustStockRules() throws {
        var db = TBDatabase()
        let g = try Fixture.gear(&db, "Net", ready: 2, care: 1)
        let rev = db.gear[g.id]!.stockRevision
        XCTAssertThrowsError(try GearUseCases.adjust(&db, gearID: g.id, operation: .removeStock, quantity: 3, source: .ready,
                                                     reason: .lostAtHome, note: nil, expectedRevision: rev, operationID: UUID(), now: Fixture.t0))
        try GearUseCases.adjust(&db, gearID: g.id, operation: .sendToCare, quantity: 1, source: .ready, reason: .damaged,
                                note: nil, expectedRevision: rev, operationID: UUID(), now: Fixture.t0)
        XCTAssertEqual(StockRules.buckets(db.gear[g.id]!), .init(ready: 1, care: 2, out: 0))
        // stale revision → conflict, nothing written
        let count = db.movements.count
        XCTAssertThrowsError(try GearUseCases.adjust(&db, gearID: g.id, operation: .addStock, quantity: 1, source: .ready, reason: .purchase,
                                                     note: nil, expectedRevision: rev, operationID: UUID(), now: Fixture.t0)) { error in
            XCTAssertTrue((error as? DomainError)?.isConflict == true)
        }
        XCTAssertEqual(db.movements.count, count)
        // same operation twice → one movement
        let op = UUID()
        let fresh = db.gear[g.id]!.stockRevision
        try GearUseCases.adjust(&db, gearID: g.id, operation: .addStock, quantity: 1, source: .ready, reason: .purchase,
                                note: nil, expectedRevision: fresh, operationID: op, now: Fixture.t0)
        try GearUseCases.adjust(&db, gearID: g.id, operation: .addStock, quantity: 1, source: .ready, reason: .purchase,
                                note: nil, expectedRevision: fresh, operationID: op, now: Fixture.t0)
        XCTAssertEqual(db.gear[g.id]!.readyQty, 2)
        // total can't go above 9999
        XCTAssertThrowsError(try GearUseCases.preview(db.gear[g.id]!, operation: .addStock, quantity: 9999, source: .ready))
        Fixture.assertInvariants(db)
    }

    func testArchiveAndDeleteRules() throws {
        var db = TBDatabase()
        let g = try Fixture.gear(&db, "Rod", ready: 1)
        XCTAssertNil(GearUseCases.deleteBlockReason(db, gearID: g.id))
        let trip = try Fixture.plan(&db, lines: [(g.id, 1, .required)])
        XCTAssertNotNil(GearUseCases.archiveBlockReason(db, gearID: g.id), "Planned trip reference blocks archive")
        XCTAssertNotNil(GearUseCases.deleteBlockReason(db, gearID: g.id))
        try TripUseCases.removeLine(&db, tripID: trip.id, lineID: db.trips[trip.id]!.lines[0].id, now: Fixture.t0)
        try GearUseCases.archive(&db, gearID: g.id, now: Fixture.t0)
        XCTAssertTrue(db.gear[g.id]!.isArchived)
    }
}
