import XCTest
@testable import TackleBay

final class PersistenceAndBackupTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TBTest-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func populated() throws -> TBDatabase {
        var db = TBDatabase()
        db.settings.onboardingCompleted = true
        let rod = try Fixture.gear(&db, "Rod", ready: 2, care: 1)
        let hooks = try Fixture.gear(&db, "Hooks", tracking: .consumable, ready: 10)
        let trip = try Fixture.plan(&db, lines: [(rod.id, 1, .required), (hooks.id, 4, .required)])
        try Fixture.pack(&db, trip: trip.id, gear: rod.id, qty: 1)
        try Fixture.pack(&db, trip: trip.id, gear: hooks.id, qty: 4)
        try Fixture.start(&db, trip: trip.id)
        try TripUseCases.beginReturn(&db, tripID: trip.id, now: Fixture.t0)
        let line = Fixture.line(db, trip: trip.id, gear: hooks.id)
        try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: line.id, returned: 1, care: 0, used: 3, lost: 0)
        try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: line.id)
        try BonusUseCases.claim(&db, operationID: UUID(), now: Fixture.t0)
        let r = try BonusUseCases.cast(&db, operationID: UUID(), random: ScriptedRandomSource([0, 1, 2]), now: Fixture.t0)
        BonusUseCases.markPresented(&db, receiptID: r.id, now: Fixture.t0)
        return db
    }

    // AC 08: a restart in Returning restores stock and the draft.
    @MainActor
    func testCoreDataRoundTripKeepsEverything() throws {
        let db = try populated()
        let store = TackleStore(rootURL: root, clock: FixedTimeProvider(Fixture.t0), random: ScriptedRandomSource([0]))
        store.load()
        try store.replaceDatabase(db)
        let reopened = TackleStore(rootURL: root, clock: FixedTimeProvider(Fixture.t0), random: ScriptedRandomSource([0]))
        reopened.load()
        XCTAssertEqual(reopened.db, db)
        XCTAssertEqual(reopened.db.openTrip?.status, .returning)
        XCTAssertNotNil(reopened.db.draft(for: reopened.db.openTrip!.id))
        // Incremental commit persists too.
        try reopened.perform { db, now in db.settings.haptics = false }
        let third = TackleStore(rootURL: root, clock: FixedTimeProvider(Fixture.t0), random: ScriptedRandomSource([0]))
        third.load()
        XCTAssertFalse(third.db.settings.haptics)
    }

    // AC 19: export → validate → identical database, including the return draft.
    func testBackupRoundTripAndValidation() throws {
        let db = try populated()
        let file = BackupFile(db: db, photos: [], createdAt: Fixture.t0)
        let data = try BackupCoding.makeEncoder().encode(file)
        let decoded = try BackupCoding.makeDecoder().decode(BackupFile.self, from: data)
        let (restored, summary) = try BackupValidator.validate(decoded)
        XCTAssertEqual(restored.gear, db.gear)
        XCTAssertEqual(restored.movements, db.movements)
        XCTAssertEqual(restored.returnDrafts, db.returnDrafts)
        XCTAssertEqual(restored.wallet, db.wallet)
        XCTAssertTrue(summary.hasOpenTrip)
        XCTAssertEqual(summary.parts, db.wallet.parts)
    }

    func testBackupRejectsBrokenStockAndLedger() throws {
        let db = try populated()
        var file = BackupFile(db: db, photos: [], createdAt: Fixture.t0)
        file.gear[0].readyQty += 5
        XCTAssertThrowsError(try BackupValidator.validate(file))

        file = BackupFile(db: db, photos: [], createdAt: Fixture.t0)
        file.wallet.parts += 8
        XCTAssertThrowsError(try BackupValidator.validate(file))

        file = BackupFile(db: db, photos: [], createdAt: Fixture.t0)
        file.receipts[0].rewardParts = 3
        XCTAssertThrowsError(try BackupValidator.validate(file))

        file = BackupFile(db: db, photos: [], createdAt: Fixture.t0)
        file.schemaVersion = 2
        XCTAssertThrowsError(try BackupValidator.validate(file))

        file = BackupFile(db: db, photos: [], createdAt: Fixture.t0)
        file.settings.selectedCollectibleID = .littleBlueBoat
        XCTAssertThrowsError(try BackupValidator.validate(file))
    }

    func testBackupPhotoChecksumIsVerified() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let ref = PhotoRef(id: UUID(), fileName: "a.jpg", thumbFileName: "a_t.jpg", mime: "image/jpeg", width: 8, height: 8,
                           sha256: PhotoStore.sha256(image))
        XCTAssertNoThrow(try PhotoStore.validateBackupPhoto(BackupPhoto(ref: ref, data: image.base64EncodedString())))
        var bad = ref
        bad.sha256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try PhotoStore.validateBackupPhoto(BackupPhoto(ref: bad, data: image.base64EncodedString())))
        XCTAssertThrowsError(try PhotoStore.validateBackupPhoto(BackupPhoto(ref: ref, data: Data("not an image".utf8).base64EncodedString())))
    }

    func testPhotoImportStripsMetadataAndDownsizes() throws {
        let store = PhotoStore(directory: root.appendingPathComponent("Photos"))
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = 1
            return f
        }()).jpegData(withCompressionQuality: 0.7) { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let ref = try store.importPhoto(data: big)
        XCTAssertEqual(max(ref.width, ref.height), 1600)
        let saved = try XCTUnwrap(store.data(ref))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(saved as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertNil(props?[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(PhotoStore.sha256(saved), ref.sha256)
    }
}
