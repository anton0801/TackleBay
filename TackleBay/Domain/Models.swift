import Foundation

// MARK: - Gear

enum GearCategory: String, Codable, CaseIterable, Identifiable {
    case rods, reels, terminalTackle, lures, tools, clothing, containers, supplies, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rods: return "Rods"
        case .reels: return "Reels"
        case .terminalTackle: return "Terminal Tackle"
        case .lures: return "Lures"
        case .tools: return "Tools"
        case .clothing: return "Clothing"
        case .containers: return "Containers"
        case .supplies: return "Supplies"
        case .other: return "Other"
        }
    }

    var singular: String {
        switch self {
        case .rods: return "Rod"
        case .reels: return "Reel"
        case .terminalTackle: return "Terminal Tackle"
        case .lures: return "Lure"
        case .tools: return "Tool"
        case .clothing: return "Clothing"
        case .containers: return "Container"
        case .supplies: return "Supplies"
        case .other: return "Other"
        }
    }
}

enum TrackingType: String, Codable, CaseIterable, Identifiable {
    case reusable, consumable
    var id: String { rawValue }
    var title: String { self == .reusable ? "Reusable" : "Consumable" }
}

enum CountingUnit: String, Codable, CaseIterable, Identifiable {
    case piece, pack, spool, bag, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .piece: return "Pieces"
        case .pack: return "Packs"
        case .spool: return "Spools"
        case .bag: return "Bags"
        case .other: return "Other"
        }
    }
}

/// Text form of a counting unit, frozen into snapshots so history survives later edits.
struct UnitLabel: Codable, Equatable, Hashable {
    var singular: String
    var plural: String

    init(singular: String, plural: String) {
        self.singular = singular
        self.plural = plural
    }

    init(unit: CountingUnit, custom: String?) {
        switch unit {
        case .piece: self.init(singular: "piece", plural: "pieces")
        case .pack: self.init(singular: "pack", plural: "packs")
        case .spool: self.init(singular: "spool", plural: "spools")
        case .bag: self.init(singular: "bag", plural: "bags")
        case .other:
            let text = (custom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(singular: text.isEmpty ? "unit" : text, plural: text.isEmpty ? "units" : text)
        }
    }

    func text(for qty: Int) -> String { qty == 1 ? singular : plural }
    func format(_ qty: Int) -> String { "\(qty) \(text(for: qty))" }
}

struct Gear: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var category: GearCategory
    var trackingType: TrackingType
    var countingUnit: CountingUnit
    var customUnit: String?
    var storage: String
    var note: String?
    var photoID: UUID?
    /// Illustrative artwork for Sample Collection records only. Never set for user records.
    var sampleArt: String?
    var readyQty: Int
    var careQty: Int
    var outQty: Int
    var stockRevision: Int64
    var isArchived: Bool
    var isDemo: Bool
    var createdAt: Date
    var updatedAt: Date

    var ownedQty: Int { readyQty + careQty + outQty }
    var unit: UnitLabel { UnitLabel(unit: countingUnit, custom: customUnit) }
    var isAvailable: Bool { !isArchived }
}

// MARK: - Stock journal

enum MovementKind: String, Codable, CaseIterable {
    case added, adjusted, takenOnTrip, returned, used, lost, sentToCare, markedReady

    var title: String {
        switch self {
        case .added: return "Added"
        case .adjusted: return "Adjusted"
        case .takenOnTrip: return "Taken on Trip"
        case .returned: return "Returned"
        case .used: return "Used"
        case .lost: return "Lost"
        case .sentToCare: return "Sent to Care"
        case .markedReady: return "Marked Ready"
        }
    }
}

enum StockReason: String, Codable, CaseIterable, Identifiable {
    case purchase, found, usedAtHome, lostAtHome, countCorrection, damaged, careCompleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purchase: return "Purchase"
        case .found: return "Found"
        case .usedAtHome: return "Used at Home"
        case .lostAtHome: return "Lost at Home"
        case .countCorrection: return "Count Correction"
        case .damaged: return "Damaged"
        case .careCompleted: return "Care Completed"
        }
    }
}

struct StockMovement: Codable, Identifiable, Equatable {
    var id: UUID
    var operationID: UUID
    var sequence: Int64
    var gearID: UUID
    var tripID: UUID?
    var kind: MovementKind
    var deltaReady: Int
    var deltaCare: Int
    var deltaOut: Int
    var usedQty: Int
    var lostQty: Int
    var reason: StockReason?
    var note: String?
    var timestamp: Date
    var gearNameSnapshot: String
    var unitSnapshot: UnitLabel
}

// MARK: - Kits

enum Importance: String, Codable, CaseIterable, Identifiable {
    case required, optional
    var id: String { rawValue }
    var title: String { self == .required ? "Required" : "Optional" }
}

struct KitLine: Codable, Identifiable, Equatable {
    var id: UUID
    var gearID: UUID
    var requiredQty: Int
    var importance: Importance
    var note: String?
}

struct Kit: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var description: String?
    var lines: [KitLine]
    var isArchived: Bool
    var isDemo: Bool
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Trips

enum TripStatus: String, Codable, CaseIterable {
    case planned, active, returning, completed, cancelled

    var title: String {
        switch self {
        case .planned: return "Planned"
        case .active: return "Active"
        case .returning: return "Returning"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Frozen at Start Trip so later edits of the gear never rewrite the trip history.
struct LineSnapshot: Codable, Equatable {
    var name: String
    var category: GearCategory
    var trackingType: TrackingType
    var unit: UnitLabel
    var storage: String
}

struct TripLine: Codable, Identifiable, Equatable {
    var id: UUID
    var gearID: UUID
    var requiredQty: Int
    var packedQty: Int
    var importance: Importance
    var packingNote: String?
    var snapshot: LineSnapshot?
    var takenQty: Int?
}

struct TripNote: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
}

struct Trip: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var place: String
    var plannedDepartureAt: Date
    var status: TripStatus
    var note: String?
    var isDemo: Bool
    var isHidden: Bool
    var revision: Int64
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var cancelledAt: Date?
    var startOperationID: UUID?
    var returnOperationID: UUID?
    var startedName: String?
    var startedPlace: String?
    var missingItemsNote: String?
    var lines: [TripLine]
    var liveNotes: [TripNote]
    var personalNote: String?

    var displayName: String { startedName ?? name }
    var displayPlace: String { startedPlace ?? place }
    var isOpenTrip: Bool { status == .active || status == .returning }
}

struct ReturnEntry: Codable, Equatable {
    var tripLineID: UUID
    var returnedQty: Int
    var careQty: Int
    var usedQty: Int
    var lostQty: Int
    var confirmed: Bool

    var resolved: Int { returnedQty + careQty + usedQty + lostQty }
}

struct ReturnDraft: Codable, Identifiable, Equatable {
    var id: UUID
    var tripID: UUID
    var operationID: UUID
    var sourceTripRevision: Int64
    var endAt: Date
    var summaryNote: String?
    var lossNote: String?
    var entries: [ReturnEntry]

    func entry(for lineID: UUID) -> ReturnEntry? { entries.first { $0.tripLineID == lineID } }
}

struct ReturnResultEntry: Codable, Equatable {
    var tripLineID: UUID
    var gearID: UUID
    var snapshot: LineSnapshot
    var taken: Int
    var returned: Int
    var care: Int
    var used: Int
    var lost: Int
}

struct TripReturnResult: Codable, Identifiable, Equatable {
    var id: UUID
    var tripID: UUID
    var operationID: UUID
    var endedAt: Date
    var entries: [ReturnResultEntry]
    var summaryNote: String?
    var lossNote: String?
}

// MARK: - Photos

struct PhotoRef: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var thumbFileName: String
    var mime: String
    var width: Int
    var height: Int
    var sha256: String
}

// MARK: - Bonus

enum SymbolID: String, Codable, CaseIterable, Identifiable {
    case float, lure, reel, shell, fish, anchor

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var assetName: String { "tb_symbol_\(rawValue)" }
}

enum CollectibleID: String, Codable, CaseIterable, Identifiable {
    case docksideNook = "dockside_nook"
    case beaconPoint = "beacon_point"
    case tackleWorkshop = "tackle_workshop"
    case littleBlueBoat = "little_blue_boat"

    var id: String { rawValue }
}

struct BonusWallet: Codable, Equatable {
    var tickets: Int = 0
    var parts: Int = 0
    var nextClaimAt: Date?
    var lastObservedAt: Date?
    var rulesVersion: Int = BonusRules.rulesVersion
    var revision: Int64 = 0
}

struct BonusClaim: Codable, Identifiable, Equatable {
    var id: UUID
    var operationID: UUID
    var sequence: Int64
    var claimedAt: Date
    var nextClaimAt: Date
    var ticketDelta: Int
}

struct CastReceipt: Codable, Identifiable, Equatable {
    var id: UUID
    var operationID: UUID
    var sequence: Int64
    var rulesVersion: Int
    var symbols: [SymbolID]
    var rewardParts: Int
    var ticketDelta: Int
    var createdAt: Date
    var presentedAt: Date?
}

struct CollectibleOwnership: Codable, Identifiable, Equatable {
    var collectibleID: CollectibleID
    var acquiredAt: Date
    var operationID: UUID
    var sequence: Int64
    var costParts: Int

    var id: CollectibleID { collectibleID }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    var onboardingCompleted = false
    var haptics = true
    var soundEffects = false
    var bonusAmbience = false
    var showBonusOnHome = true
    var selectedCollectibleID: CollectibleID?
    var lastExportAt: Date?
}

struct Counters: Codable, Equatable {
    var nextMovementSequence: Int64 = 1
    var nextBonusSequence: Int64 = 1
}

// MARK: - Database snapshot

/// Whole local database as value types. Domain use cases mutate a copy; the store commits it atomically.
struct TBDatabase: Equatable {
    var gear: [UUID: Gear] = [:]
    var movements: [UUID: StockMovement] = [:]
    var kits: [UUID: Kit] = [:]
    var trips: [UUID: Trip] = [:]
    var returnDrafts: [UUID: ReturnDraft] = [:]
    var returnResults: [UUID: TripReturnResult] = [:]
    var photos: [UUID: PhotoRef] = [:]
    var claims: [UUID: BonusClaim] = [:]
    var receipts: [UUID: CastReceipt] = [:]
    var ownerships: [CollectibleID: CollectibleOwnership] = [:]
    var wallet = BonusWallet()
    var settings = AppSettings()
    var counters = Counters()

    var openTrip: Trip? { trips.values.first { $0.isOpenTrip } }

    func movements(for gearID: UUID) -> [StockMovement] {
        movements.values.filter { $0.gearID == gearID }.sorted { $0.sequence > $1.sequence }
    }

    func draft(for tripID: UUID) -> ReturnDraft? { returnDrafts.values.first { $0.tripID == tripID } }
    func result(for tripID: UUID) -> TripReturnResult? { returnResults.values.first { $0.tripID == tripID } }
}
