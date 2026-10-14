#if DEBUG
import SwiftUI

/// Debug-only visual harness: `-tbScenario <name>` opens a screen on an in-memory store with sample data.
/// Never compiled into Release builds and never touches the user's database.
enum DebugScenario {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tbScenario"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func services(for scenario: String) -> AppServices {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TBScenario", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let store = TackleStore(rootURL: root, clock: SystemTimeProvider(), random: SecureRandomSource(), inMemory: true)
        store.load()
        seed(store, scenario: scenario)
        return AppServices(store: store)
    }

    private static func gearID(_ db: TBDatabase, _ name: String) -> UUID? {
        db.gear.values.first { $0.name == name }?.id
    }

    private static func tripID(_ db: TBDatabase) -> UUID? { db.trips.values.first?.id }

    @MainActor
    private static func seed(_ store: TackleStore, scenario: String) {
        let empty = ["home_empty", "gear_empty", "onboarding"].contains(scenario)
        try? store.perform { db, now in
            db.settings.onboardingCompleted = scenario != "onboarding"
            if empty { return }
            try SampleCollection.load(&db, now: now.addingTimeInterval(-3600))
            if scenario == "care_empty", let reel = gearID(db, "Tide reel"), let g = db.gear[reel] {
                try GearUseCases.markReady(&db, gearID: reel, quantity: g.careQty, note: nil, expectedRevision: g.stockRevision,
                                           operationID: UUID(), now: now)
            }
            seedBonus(&db, scenario: scenario, now: now)
            guard let trip = tripID(db) else { return }
            if ["home", "packing", "departure", "trips", "active", "return", "return_validation", "summary", "care"].contains(scenario) {
                for name in ["Shore rod", "Tide reel", "Tackle box"] {
                    if let line = db.trips[trip]?.lines.first(where: { $0.gearID == gearID(db, name) }) {
                        try TripUseCases.setPacked(&db, tripID: trip, lineID: line.id, packed: line.requiredQty, now: now)
                    }
                }
                if let line = db.trips[trip]?.lines.first(where: { $0.gearID == gearID(db, "Hook packs") }) {
                    try TripUseCases.setPacked(&db, tripID: trip, lineID: line.id, packed: 2, now: now)
                }
            }
            if ["active", "return", "return_validation", "summary", "care"].contains(scenario), let t = db.trips[trip] {
                // Hook packs: 5 taken for the return validation mock.
                if let line = t.lines.first(where: { $0.gearID == gearID(db, "Hook packs") }) {
                    try TripUseCases.updateLine(&db, tripID: trip, lineID: line.id, required: 5, packed: 5, importance: .required, note: nil, now: now)
                }
                let rev = db.trips[trip]!.revision
                try TripUseCases.start(&db, tripID: trip, expectedRevision: rev, missingNote: "Short pier session", operationID: UUID(),
                                       now: now.addingTimeInterval(-2 * 3600 - 14 * 60))
            }
            if ["return", "return_validation", "summary", "care"].contains(scenario) {
                try TripUseCases.beginReturn(&db, tripID: trip, now: now)
                let t = db.trips[trip]!
                for line in t.lines where (line.takenQty ?? 0) > 0 {
                    let name = db.gear[line.gearID]!.name
                    let taken = line.takenQty!
                    switch name {
                    case "Hook packs":
                        if scenario == "return_validation" {
                            try TripUseCases.updateEntry(&db, tripID: trip, lineID: line.id, returned: 2, care: 0, used: 1, lost: 0)
                        } else if scenario != "return" {
                            try TripUseCases.updateEntry(&db, tripID: trip, lineID: line.id, returned: 2, care: 0, used: 3, lost: 0)
                            try TripUseCases.confirmRow(&db, tripID: trip, lineID: line.id)
                        }
                    case "Tide reel":
                        if scenario != "return_validation" {
                            try TripUseCases.updateEntry(&db, tripID: trip, lineID: line.id, returned: 0, care: taken, used: 0, lost: 0)
                            try TripUseCases.confirmRow(&db, tripID: trip, lineID: line.id)
                        }
                    default:
                        if scenario != "return_validation" && !(scenario == "return" && name == "Tackle box") {
                            try TripUseCases.updateEntry(&db, tripID: trip, lineID: line.id, returned: taken, care: 0, used: 0, lost: 0)
                            try TripUseCases.confirmRow(&db, tripID: trip, lineID: line.id)
                        }
                    }
                }
            }
            if ["summary", "care"].contains(scenario) {
                try TripUseCases.confirmReturn(&db, tripID: trip, now: now)
            }
        }
    }

    private static func seedBonus(_ db: inout TBDatabase, scenario: String, now: Date) {
        let random = ScriptedRandomSource([0, 2, 0, 3, 3, 1, 4, 4, 4, 0, 1, 2, 5, 5, 2, 1, 1, 3, 2, 2, 2, 4, 0, 4, 3, 1, 3, 0, 0, 5])
        var t = now.addingTimeInterval(-40 * 24 * 3600)
        let casts: Int
        switch scenario {
        case "bonus": casts = 3
        case "bonus_result": casts = 4
        case "showcase": casts = 6
        case "build": casts = 11
        case "complete": casts = 20
        default: casts = 2
        }
        for i in 0..<casts {
            _ = try? BonusUseCases.claim(&db, operationID: UUID(), now: t)
            t = t.addingTimeInterval(25 * 3600)
            if let r = try? BonusUseCases.cast(&db, operationID: UUID(), random: random, now: t), !(scenario == "bonus_result" && i == casts - 1) {
                BonusUseCases.markPresented(&db, receiptID: r.id, now: t)
            }
            if scenario == "showcase" || scenario == "build", db.wallet.parts >= 8, db.ownerships.isEmpty {
                _ = try? BonusUseCases.build(&db, collectibleID: .docksideNook, operationID: UUID(), now: t)
            }
            if scenario == "complete" {
                for c in CollectibleID.allCases where db.ownerships[c] == nil && db.wallet.parts >= 8 {
                    _ = try? BonusUseCases.build(&db, collectibleID: c, operationID: UUID(), now: t)
                }
            }
        }
        if scenario == "complete" {
            try? BonusUseCases.display(&db, collectibleID: .beaconPoint)
        }
        if scenario == "bonus" {
            // Leave the wallet empty with the cooldown running, like the cooldown mock.
            _ = try? BonusUseCases.claim(&db, operationID: UUID(), now: now.addingTimeInterval(-15 * 3600))
            if let r = try? BonusUseCases.cast(&db, operationID: UUID(), random: random, now: now.addingTimeInterval(-15 * 3600)) {
                BonusUseCases.markPresented(&db, receiptID: r.id, now: now)
            }
        }
        BonusUseCases.observe(&db, now: now)
    }

    @MainActor
    static func present(router: Router, ui: AppUI, store: TackleStore) {
        guard let scenario = requested else { return }
        let db = store.db
        let trip = tripID(db)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            switch scenario {
            case "gear", "gear_empty": router.tab = .gear
            case "trips": router.tab = .trips
            case "kits": router.tab = .kits
            case "gear_editor": router.tab = .gear; router.push(.gearEditor(.new))
            case "gear_detail": router.tab = .gear; gearID(db, "Tide reel").map { router.push(.gearDetail($0)) }
            case "adjust": router.tab = .gear; gearID(db, "Tide reel").map { router.push(.adjustStock($0, operation: .markReady, tripID: nil)) }
            case "kit_editor": router.tab = .kits; db.kits.values.first.map { router.push(.kitEditor(.edit($0.id, addGear: nil))) }
            case "trip_editor": router.tab = .trips; router.push(.tripEditor(.new(kitID: nil)))
            case "packing", "departure": router.tab = .trips; trip.map { router.push(.packing($0, applyKit: nil)) }
            case "active": router.tab = .trips; trip.map { router.push(.activeTrip($0)) }
            case "return", "return_validation": router.tab = .trips; trip.map { router.push(.returnGear($0)) }
            case "summary": router.tab = .trips; trip.map { router.push(.tripSummary($0)) }
            case "care", "care_empty": router.push(.needsCare(tripID: nil))
            case "bonus", "bonus_result", "complete": router.push(.bonus)
            case "showcase": router.push(.showcase)
            case "build": router.push(.showcase)
            case "settings": router.push(.settings)
            case "backup", "import_error": router.push(.settings); router.push(.backup)
            case "privacy": router.push(.settings); router.push(.privacy)
            default: break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            switch scenario {
            case "departure":
                if let trip = trip, let rev = store.db.trips[trip]?.revision {
                    ui.present { DepartureReviewSheet(tripID: trip, expectedRevision: rev) { _ in ui.dismissSheet() } }
                }
            case "build":
                ui.present { BuildSheet(info: BonusRules.info(.beaconPoint)) }
            default: break
            }
        }
    }

    static var showImportError: Bool { requested == "import_error" }
}
#endif
