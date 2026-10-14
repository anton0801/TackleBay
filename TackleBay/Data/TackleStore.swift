import Combine
import Foundation

/// Repository facade: owns the in-memory snapshot and commits each domain operation atomically.
/// All mutations run on the main actor one after another, so stock transactions are serialized.
@MainActor
final class TackleStore: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var db = TBDatabase()
    @Published private(set) var loadState: LoadState = .loading
    /// Import, restore and reset block every other mutation while they run.
    @Published private(set) var isLocked = false

    let photos: PhotoStore
    let clock: TimeProvider
    let random: RandomSource
    let rootURL: URL
    private let inMemory: Bool
    private var persistence: CoreDataPersistence?

    init(rootURL: URL, clock: TimeProvider, random: RandomSource, inMemory: Bool = false) {
        self.rootURL = rootURL
        self.clock = clock
        self.random = random
        self.inMemory = inMemory
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        photos = PhotoStore(directory: rootURL.appendingPathComponent("Photos", isDirectory: true))
    }

    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TackleBay", isDirectory: true)
    }

    var now: Date { clock.now() }
    var storeURL: URL { rootURL.appendingPathComponent("TackleBay.sqlite") }

    /// A read failure is reported as an error state; an empty database is never created silently over it.
    func load() {
        loadState = .loading
        do {
            if persistence == nil { persistence = try CoreDataPersistence(storeURL: inMemory ? nil : storeURL) }
            db = try persistence!.loadAll()
            photos.removeOrphans(keeping: Array(db.photos.values))
            loadState = .ready
            #if DEBUG
            Self.debugCatalogueCheck()
            let problems = StockRules.invariantProblems(db) + BonusUseCases.ledgerProblems(db)
            if !problems.isEmpty { print("[TackleBay] invariant warnings: \(problems.count)") }
            #endif
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Runs a domain operation on a copy and commits it in one transaction. On any error nothing changes.
    @discardableResult
    func perform<T>(_ body: (inout TBDatabase, Date) throws -> T) throws -> T {
        guard loadState == .ready, let persistence = persistence else {
            throw DomainError.blocked("Your data isn't available right now.")
        }
        guard !isLocked else { throw DomainError.blocked("Please wait until the current data operation finishes.") }
        var copy = db
        let result = try body(&copy, clock.now())
        if copy != db {
            try persistence.commit(from: db, to: copy)
            db = copy
        }
        return result
    }

    // MARK: Whole-database replacement

    func replaceDatabase(_ newDB: TBDatabase) throws {
        guard let persistence = persistence else { throw DomainError.blocked("Your data isn't available right now.") }
        try persistence.replaceAll(with: newDB)
        db = newDB
        loadState = .ready
    }

    var canReplaceDatabase: Bool { persistence != nil }

    func lock(_ locked: Bool) { isLocked = locked }

    #if DEBUG
    /// Debug-launch completeness check of the static catalogue (six symbols, four collectibles).
    static func debugCatalogueCheck() {
        assert(BonusRules.strip.count == 6 && Set(BonusRules.strip).count == 6, "Symbol catalogue incomplete")
        assert(BonusRules.collectibles.count == 4 && Set(BonusRules.collectibles.map(\.id)).count == 4, "Collectible catalogue incomplete")
    }
    #endif
}
