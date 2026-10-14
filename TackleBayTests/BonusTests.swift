import XCTest
@testable import TackleBay

final class BonusTests: XCTestCase {
    // AC 13: all 216 ordered triples.
    func testOutcomeTable() {
        var counts = [3: 0, 2: 0, 1: 0]
        var total = 0
        for a in SymbolID.allCases {
            for b in SymbolID.allCases {
                for c in SymbolID.allCases {
                    let reward = BonusRules.reward([a, b, c])
                    counts[reward, default: 0] += 1
                    total += reward
                }
            }
        }
        XCTAssertEqual(counts[3], 6)
        XCTAssertEqual(counts[2], 90)
        XCTAssertEqual(counts[1], 120)
        XCTAssertEqual(counts.values.reduce(0, +), 216)
        XCTAssertEqual(total, 318, "Mean reward 318/216 = 53/36, test-only")
        XCTAssertTrue(BonusRules.probabilitiesText.contains("1 in 36"))
        XCTAssertTrue(BonusRules.probabilitiesText.contains("5 in 12"))
        XCTAssertTrue(BonusRules.probabilitiesText.contains("5 in 9"))
    }

    func testSecureRandomIsUniformAndInRange() {
        let source = SecureRandomSource()
        var histogram = [Int](repeating: 0, count: 6)
        for _ in 0..<60_000 { histogram[source.nextInt(upperBound: 6)] += 1 }
        for count in histogram { XCTAssertEqual(Double(count), 10_000, accuracy: 600) }
    }

    // AC 01 + AC 14: first claim is immediate, then exactly one ticket per 24 h, capped at 3, no accumulation.
    func testClaimClock() throws {
        var db = TBDatabase()
        XCTAssertEqual(db.wallet.tickets, 0)
        XCTAssertEqual(BonusUseCases.claimState(db, now: Fixture.t0), .available)
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0)
        XCTAssertEqual(db.wallet.tickets, 1)
        XCTAssertThrowsError(try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0.addingTimeInterval(3600)))
        // Three days away still gives one ticket.
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(db.wallet.tickets, 2)
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(db.wallet.tickets, 3)
        XCTAssertEqual(BonusUseCases.claimState(db, now: Fixture.t0.addingTimeInterval(9 * 86_400)), .storageFull)
        // Same operation twice → one ticket.
        var db2 = TBDatabase()
        let op = UUID()
        try BonusUseCases.claim(&db2, operationID: op, now: Fixture.t0)
        try BonusUseCases.claim(&db2, operationID: op, now: Fixture.t0)
        XCTAssertEqual(db2.wallet.tickets, 1)
        Fixture.assertInvariants(db)
    }

    // AC 15: rolling the clock back more than 5 minutes blocks only Claim.
    func testClockRollbackBlocksClaimOnly() throws {
        var db = TBDatabase()
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0)
        BonusUseCases.observe(&db, now: Fixture.t0.addingTimeInterval(2 * 86_400))
        let rolledBack = Fixture.t0.addingTimeInterval(2 * 86_400 - 600)
        XCTAssertEqual(BonusUseCases.claimState(db, now: rolledBack), .checkDeviceTime)
        XCTAssertNoThrow(try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([0]), now: rolledBack))
        // A small rollback uses effectiveNow and doesn't grant an extra ticket.
        var db2 = TBDatabase()
        try BonusUseCases.claim(&db2, operationID: UUID(), now: Fixture.t0)
        BonusUseCases.observe(&db2, now: Fixture.t0.addingTimeInterval(86_400 - 60))
        XCTAssertEqual(BonusUseCases.claimState(db2, now: Fixture.t0.addingTimeInterval(86_400 - 120)), .cooldown(until: Fixture.t0.addingTimeInterval(86_400)))
    }

    // AC 16 + AC 17: the receipt is stored first, can't be re-drawn and blocks another cast until presented.
    func testCastReceiptLifecycle() throws {
        var db = TBDatabase()
        XCTAssertThrowsError(try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([0]), now: Fixture.t0))
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0)
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0.addingTimeInterval(86_400))
        let op = UUID()
        let receipt = try BonusUseCases.cast(&db, operationID: op, random: ScriptedRandomSource([0, 0, 2]), now: Fixture.t0.addingTimeInterval(86_400))
        XCTAssertEqual(receipt.symbols, [.float, .float, .reel])
        XCTAssertEqual(receipt.rewardParts, 2)
        XCTAssertEqual(db.wallet.tickets, 1)
        XCTAssertEqual(db.wallet.parts, 2)
        // Retry with the same operation returns the stored result without a new draw.
        let again = try BonusUseCases.cast(&db, operationID: op, random: ScriptedRandomSource([5, 5, 5]), now: Fixture.t0)
        XCTAssertEqual(again, receipt)
        XCTAssertEqual(db.wallet.parts, 2)
        // Pending result blocks another cast.
        XCTAssertThrowsError(try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([1]), now: Fixture.t0))
        XCTAssertEqual(BonusUseCases.pendingReceipt(db)?.id, receipt.id)
        BonusUseCases.markPresented(&db, receiptID: receipt.id, now: Fixture.t0)
        XCTAssertNil(BonusUseCases.pendingReceipt(db))
        XCTAssertNoThrow(try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([1, 2, 3]), now: Fixture.t0))
        Fixture.assertInvariants(db)
    }

    // AC 16: a cold start restores the committed receipt from the store.
    @MainActor
    func testPendingReceiptSurvivesRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TBTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = FixedTimeProvider(Fixture.t0)
        let store = TackleStore(rootURL: root, clock: clock, random: ScriptedRandomSource([3, 3, 3]))
        store.load()
        try store.perform { db, now in _ = try BonusUseCases.claim(&db, operationID: UUID(), now: now) }
        let receipt = try store.perform { db, now in try BonusUseCases.cast(&db, operationID: UUID(), random: store.random, now: now) }
        let reopened = TackleStore(rootURL: root, clock: clock, random: ScriptedRandomSource([0]))
        reopened.load()
        XCTAssertEqual(reopened.loadState, .ready)
        XCTAssertEqual(BonusUseCases.pendingReceipt(reopened.db), receipt)
        XCTAssertEqual(reopened.db.wallet.parts, 3)
        XCTAssertEqual(reopened.db.wallet.tickets, 0)
    }

    // AC 18: Build costs exactly 8 and each miniature can be built once.
    func testBuildUniqueness() throws {
        var db = TBDatabase()
        var t = Fixture.t0
        for _ in 0..<3 {
            try BonusUseCases.claim(&db, operationID: UUID(), now: t)
            let r = try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([4, 4, 4]), now: t)
            BonusUseCases.markPresented(&db, receiptID: r.id, now: t)
            t = t.addingTimeInterval(86_400)
        }
        XCTAssertEqual(db.wallet.parts, 9)
        let op = UUID()
        try BonusUseCases.build(&db, collectibleID: .beaconPoint, operationID: op, now: t)
        try BonusUseCases.build(&db, collectibleID: .beaconPoint, operationID: op, now: t)
        XCTAssertEqual(db.wallet.parts, 1)
        XCTAssertThrowsError(try BonusUseCases.build(&db, collectibleID: .beaconPoint, operationID: UUID(), now: t))
        XCTAssertThrowsError(try BonusUseCases.build(&db, collectibleID: .littleBlueBoat, operationID: UUID(), now: t)) { error in
            XCTAssertEqual((error as? DomainError)?.message, "7 more Parts needed.")
        }
        XCTAssertTrue(db.gear.isEmpty, "Miniatures never create gear")
        try BonusUseCases.display(&db, collectibleID: .beaconPoint)
        XCTAssertThrowsError(try BonusUseCases.display(&db, collectibleID: .docksideNook))
        Fixture.assertInvariants(db)
    }

    func testCollectionCompleteStopsClaimAndCast() throws {
        var db = TBDatabase()
        var t = Fixture.t0
        for _ in 0..<11 {
            if db.wallet.tickets == 0 { try BonusUseCases.claim(&db, operationID: UUID(), now: t) }
            let r = try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([1, 1, 1]), now: t)
            BonusUseCases.markPresented(&db, receiptID: r.id, now: t)
            for c in CollectibleID.allCases where db.ownerships[c] == nil && db.wallet.parts >= 8 {
                try BonusUseCases.build(&db, collectibleID: c, operationID: UUID(), now: t)
            }
            t = t.addingTimeInterval(86_400)
        }
        XCTAssertTrue(BonusUseCases.isCollectionComplete(db))
        XCTAssertEqual(BonusUseCases.claimState(db, now: t), .collectionComplete)
        XCTAssertNotNil(BonusUseCases.castBlockReason(db))
        Fixture.assertInvariants(db)
    }
}
