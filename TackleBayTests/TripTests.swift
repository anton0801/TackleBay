import XCTest
@testable import TackleBay

final class TripTests: XCTestCase {
    // AC 05: a shortage on one row cancels the whole start; nothing leaves partially.
    func testStartIsAllOrNothing() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 1)
        let reel = try Fixture.gear(&db, "Reel", ready: 2)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .required), (reel.id, 2, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 1)
        try Fixture.pack(&db, trip: trip.id, gear: reel.id, qty: 2)
        // Someone removed a reel at home after packing.
        try GearUseCases.adjust(&db, gearID: reel.id, operation: .removeStock, quantity: 1, source: .ready, reason: .lostAtHome,
                                note: nil, expectedRevision: db.gear[reel.id]!.stockRevision, operationID: UUID(), now: Fixture.t0)
        let before = db
        XCTAssertThrowsError(try Fixture.start(&db, trip: trip.id))
        XCTAssertEqual(db, before)
        XCTAssertEqual(db.gear[rod.id]!.outQty, 0)
    }

    func testOnlyOneOpenTrip() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 2)
        let a = try Fixture.plan(&db, name: "A", lines: [(rod.id, 1, .required)])
        let b = try Fixture.plan(&db, name: "B", lines: [(rod.id, 1, .required)])
        try Fixture.pack(&db, trip: a.id, gear: rod.id, qty: 1)
        try Fixture.pack(&db, trip: b.id, gear: rod.id, qty: 1)
        try Fixture.start(&db, trip: a.id)
        XCTAssertThrowsError(try Fixture.start(&db, trip: b.id))
        try TripUseCases.beginReturn(&db, tripID: a.id, now: Fixture.t0)
        XCTAssertThrowsError(try Fixture.start(&db, trip: b.id), "Returning also blocks a second start")
        Fixture.assertInvariants(db)
    }

    // AC 06: missing Required needs an explicit note; an unavailable packed row blocks start.
    func testMissingItemsNeedNoteAndUnavailableBlocks() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 1)
        let net = try Fixture.gear(&db, "Net", ready: 1)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .required), (net.id, 1, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 1)
        XCTAssertThrowsError(try Fixture.start(&db, trip: trip.id, note: nil))
        XCTAssertThrowsError(try Fixture.start(&db, trip: trip.id, note: "   "))
        let review = try XCTUnwrap(TripUseCases.departureReview(db, tripID: trip.id))
        XCTAssertTrue(review.needsMissingNote)
        XCTAssertEqual(review.progress.text, "1 of 2 essentials packed")

        // Pack the net, then archive it through a hack path: unavailable rows with Packed > 0 must block.
        try Fixture.pack(&db, trip: trip.id, gear: net.id, qty: 1)
        db.gear[net.id]?.isArchived = true
        XCTAssertFalse(TripUseCases.departureReview(db, tripID: trip.id)!.canStart)
        db.gear[net.id]?.isArchived = false
        try Fixture.start(&db, trip: trip.id)
        Fixture.assertInvariants(db)
    }

    func testStartWithMissingNoteStoresSnapshotAndZeroTakenRows() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 1)
        let net = try Fixture.gear(&db, "Net", ready: 1)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .required), (net.id, 1, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 1)
        let started = try Fixture.start(&db, trip: trip.id, note: "Short pier session")
        XCTAssertEqual(started.status, .active)
        XCTAssertEqual(started.missingItemsNote, "Short pier session")
        XCTAssertEqual(Fixture.line(db, trip: trip.id, gear: net.id).takenQty, 0)
        XCTAssertEqual(db.gear[net.id]!.outQty, 0)
        // Repeat Start with the same operation returns the stored trip.
        let again = try TripUseCases.start(&db, tripID: trip.id, expectedRevision: 0, missingNote: nil,
                                           operationID: started.startOperationID!, now: Fixture.t0)
        XCTAssertEqual(again.id, trip.id)
    }

    // AC 07: unresolved rows can't finish; Used for reusable and Care for consumable are rejected by the domain.
    func testReturnValidation() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 2)
        let hooks = try Fixture.gear(&db, "Hooks", tracking: .consumable, ready: 5)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 2, .required), (hooks.id, 5, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 2)
        try Fixture.pack(&db, trip: trip.id, gear: hooks.id, qty: 5)
        try Fixture.start(&db, trip: trip.id)
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0)
        let rodLine = Fixture.line(db, trip: trip.id, gear: rod.id)
        let hookLine = Fixture.line(db, trip: trip.id, gear: hooks.id)
        XCTAssertThrowsError(try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: rodLine.id, returned: 1, care: 0, used: 1, lost: 0))
        XCTAssertThrowsError(try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: hookLine.id, returned: 1, care: 1, used: 0, lost: 0))
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: hookLine.id, returned: 2, care: 0, used: 1, lost: 0)
        XCTAssertThrowsError(try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: hookLine.id), "2 still need an outcome")
        XCTAssertThrowsError(try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0))
        // Draft never changes stock.
        XCTAssertEqual(db.gear[hooks.id]!.outQty, 5)
        // Changing a value removes confirmation.
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: hookLine.id, returned: 2, care: 0, used: 3, lost: 0)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: hookLine.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: hookLine.id, returned: 2, care: 0, used: 2, lost: 1)
        XCTAssertEqual(db.draft(for: trip.id)?.entry(for: hookLine.id)?.confirmed, false)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: hookLine.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: rodLine.id, returned: 2, care: 0, used: 0, lost: 0)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: rodLine.id)
        // A loss requires the loss note.
        XCTAssertThrowsError(try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0))
        try TripUseCases.updateReturnDetails(&db, tripID: trip.id, endAt: Fixture.t0, summaryNote: nil, lossNote: "Lost one in the reeds")
        // End time before start is rejected, not silently corrected.
        try TripUseCases.updateReturnDetails(&db, tripID: trip.id, endAt: Fixture.t0.addingTimeInterval(-60), summaryNote: nil, lossNote: "Lost")
        XCTAssertThrowsError(try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0))
        try TripUseCases.updateReturnDetails(&db, tripID: trip.id, endAt: Fixture.t0, summaryNote: nil, lossNote: "Lost")
        try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0)
        XCTAssertEqual(db.trips[trip.id]?.status, .completed)
        XCTAssertNil(db.draft(for: trip.id))
        Fixture.assertInvariants(db)
    }

    func testContinueTripDropsDraftWithoutStockChanges() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 1)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 1)
        try Fixture.start(&db, trip: trip.id)
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0)
        try TripUseCases.continueTrip(&db, tripID: trip.id, now: Fixture.t0)
        XCTAssertEqual(db.trips[trip.id]?.status, .active)
        XCTAssertNil(db.draft(for: trip.id))
        XCTAssertEqual(db.gear[rod.id]!.outQty, 1)
    }

    // AC 10: snapshots survive later edits; a correction is a new movement.
    func testCompletedTripKeepsSnapshots() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 1)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 1)
        try Fixture.start(&db, trip: trip.id)
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0)
        let line = Fixture.line(db, trip: trip.id, gear: rod.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: line.id, returned: 1, care: 0, used: 0, lost: 0)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: line.id)
        try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0)
        var edit = GearDraft(gear: db.gear[rod.id]!)
        edit.name = "Old rod"
        try GearUseCases.update(&db, draft: edit, now: Fixture.t0)
        XCTAssertEqual(db.result(for: trip.id)?.entries.first?.snapshot.name, "Rod")
        try GearUseCases.adjust(&db, gearID: rod.id, operation: .addStock, quantity: 1, source: .ready, reason: .countCorrection,
                                note: "Found it", expectedRevision: db.gear[rod.id]!.stockRevision, operationID: UUID(),
                                tripID: trip.id, now: Fixture.t0)
        XCTAssertEqual(db.result(for: trip.id)?.entries.first?.returned, 1)
        XCTAssertNotNil(TripUseCases.deleteBlockReason(db, tripID: trip.id), "Completed trips can't be deleted")
        Fixture.assertInvariants(db)
    }

    // AC 11: Repeat and kit merges don't carry packed values; merge preview shows the sums.
    func testRepeatAndKitMerge() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 3)
        let hooks = try Fixture.gear(&db, "Hooks", tracking: .consumable, ready: 10)
        var kit = KitDraft()
        kit.name = "Shore"
        kit.lines = [KitLine(id: UUID(), gearID: rod.id, requiredQty: 1, importance: .optional, note: nil),
                     KitLine(id: UUID(), gearID: hooks.id, requiredQty: 2, importance: .required, note: nil)]
        let k = try KitUseCases.save(&db, draft: kit, now: Fixture.t0)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 2, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 2)
        let preview = try XCTUnwrap(TripUseCases.mergePreview(db, tripID: trip.id, kitID: k.id))
        let rodRow = try XCTUnwrap(preview.rows.first { $0.gearID == rod.id })
        XCTAssertEqual(rodRow.existing, 2)
        XCTAssertEqual(rodRow.added, 1)
        XCTAssertEqual(rodRow.result, 3)
        XCTAssertEqual(rodRow.importance, .required)
        try TripUseCases.applyKit(&db, tripID: trip.id, kitID: k.id, now: Fixture.t0)
        XCTAssertEqual(Fixture.line(db, trip: trip.id, gear: rod.id).packedQty, 2, "Packed stays as it was")
        XCTAssertEqual(Fixture.line(db, trip: trip.id, gear: rod.id).requiredQty, 3)
        XCTAssertEqual(Fixture.line(db, trip: trip.id, gear: hooks.id).packedQty, 0)

        try Fixture.start(&db, trip: trip.id, note: "Hooks later")
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0)
        let line = Fixture.line(db, trip: trip.id, gear: rod.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: line.id, returned: 2, care: 0, used: 0, lost: 0)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: line.id)
        try TripUseCases.confirmReturn(&db, tripID: trip.id, now: Fixture.t0)
        let draft = try XCTUnwrap(TripUseCases.repeatDraft(db, tripID: trip.id, now: Fixture.t0))
        XCTAssertEqual(draft.lines.count, 1, "Only taken rows are repeated")
        XCTAssertEqual(draft.lines.first?.packedQty, 0)
        XCTAssertTrue(draft.name.hasSuffix("copy"))
    }

    func testPackingProgressWithoutRequiredRows() throws {
        var db = TBDatabase()
        let rod = try Fixture.gear(&db, "Rod", ready: 1)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .optional)])
        XCTAssertEqual(TripUseCases.progress(db.trips[trip.id]!).text, "No required items")
    }

    // AC 12: sample data never mixes with personal records.
    func testSampleCollectionIsolation() throws {
        var db = TBDatabase()
        let own = try Fixture.gear(&db, "My rod", ready: 2)
        try SampleCollection.load(&db, now: Fixture.t0)
        try SampleCollection.load(&db, now: Fixture.t0)
        XCTAssertEqual(db.gear.values.filter(\.isDemo).count, SampleCollection.items.count, "Second load doesn't duplicate")
        let sampleTrip = try XCTUnwrap(db.trips.values.first { $0.isDemo })
        XCTAssertThrowsError(try TripUseCases.addGear(&db, tripID: sampleTrip.id, gearID: own.id, now: Fixture.t0))
        try SampleCollection.remove(&db)
        XCTAssertTrue(db.gear.values.allSatisfy { !$0.isDemo })
        XCTAssertEqual(db.gear[own.id]?.readyQty, 2)
        XCTAssertTrue(db.kits.isEmpty)
        XCTAssertTrue(db.trips.isEmpty)
        Fixture.assertInvariants(db)
    }
}
