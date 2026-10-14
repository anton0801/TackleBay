import Foundation

struct CollectibleInfo: Equatable {
    let id: CollectibleID
    let name: String
    let assetName: String
    let description: String
    let costParts: Int
}

/// Static, versioned bonus catalogue (rules v1). The Probabilities copy is derived from these numbers.
enum BonusRules {
    static let rulesVersion = 1
    static let reelCount = 3
    static let ticketCapacity = 3
    static let claimInterval: TimeInterval = 24 * 60 * 60
    static let clockRollbackTolerance: TimeInterval = 5 * 60
    static let collectibleCost = 8
    static let recordLimit = 10_000

    /// Fixed cyclic strip; also the order used for the decorative rows above and below the centre.
    static let strip: [SymbolID] = [.float, .lure, .reel, .shell, .fish, .anchor]

    static let collectibles: [CollectibleInfo] = [
        CollectibleInfo(id: .docksideNook, name: "Dockside Nook", assetName: "tb_collectible_dock",
                        description: "A tiny wooden pier with a bench, a little lantern and a coiled rope.", costParts: collectibleCost),
        CollectibleInfo(id: .beaconPoint, name: "Beacon Point", assetName: "tb_collectible_beacon",
                        description: "A cream lighthouse with a coral roof and a blue balcony on two rocks.", costParts: collectibleCost),
        CollectibleInfo(id: .tackleWorkshop, name: "Tackle Workshop", assetName: "tb_collectible_workshop",
                        description: "A small blue fishing shed with a turquoise door and a wooden porch.", costParts: collectibleCost),
        CollectibleInfo(id: .littleBlueBoat, name: "Little Blue Boat", assetName: "tb_collectible_boat",
                        description: "A round blue boat with a cream bench and two neatly stowed oars.", costParts: collectibleCost)
    ]

    static func info(_ id: CollectibleID) -> CollectibleInfo { collectibles.first { $0.id == id }! }

    enum Outcome: Equatable {
        case allSame, exactlyTwo, allDifferent

        var parts: Int {
            switch self {
            case .allSame: return 3
            case .exactlyTwo: return 2
            case .allDifferent: return 1
            }
        }

        var explanation: String {
            switch self {
            case .allSame: return "Three matching symbols."
            case .exactlyTwo: return "Two matching symbols."
            case .allDifferent: return "Three different symbols."
            }
        }
    }

    /// Only the three centre symbols count.
    static func outcome(_ symbols: [SymbolID]) -> Outcome {
        let distinct = Set(symbols).count
        switch distinct {
        case 1: return .allSame
        case 2: return .exactlyTwo
        default: return .allDifferent
        }
    }

    static func reward(_ symbols: [SymbolID]) -> Int { outcome(symbols).parts }

    /// Decorative neighbours around a centre symbol (previous above, next below). They never affect the reward.
    static func neighbours(of symbol: SymbolID) -> (above: SymbolID, below: SymbolID) {
        let i = strip.firstIndex(of: symbol)!
        return (strip[(i + strip.count - 1) % strip.count], strip[(i + 1) % strip.count])
    }

    static let howItWorksText = "Claim one free ticket every 24 hours. Tickets do not accumulate while you are away, and you can hold up to 3. Each cast uses one ticket and gives 1–3 Parts. Use 8 Parts to build a miniature of your choice. These are decorative virtual items, not real fishing gear."
    static let probabilitiesText = "Only the three centre symbols count. Three matching symbols: 3 Parts — 1 in 36. Exactly two matching symbols: 2 Parts — 5 in 12. Three different symbols: 1 Part — 5 in 9. Each symbol has the same chance on each reel."
    static let footerText = "Free tickets only. No purchases, cash prizes or withdrawals."
    static let fullText = "You have 3 tickets. Use one to make room."
    static let completedText = "Your bay collection is complete. Enjoy your miniatures on My Bay."
}

enum ClaimState: Equatable {
    case available
    case cooldown(until: Date)
    case storageFull
    case checkDeviceTime
    case collectionComplete
    case limitReached
}

enum BonusUseCases {
    static func isCollectionComplete(_ db: TBDatabase) -> Bool {
        CollectibleID.allCases.allSatisfy { db.ownerships[$0] != nil }
    }

    static func isLimitReached(_ db: TBDatabase) -> Bool {
        db.claims.count >= BonusRules.recordLimit || db.receipts.count >= BonusRules.recordLimit
    }

    static func clockRolledBack(_ db: TBDatabase, now: Date) -> Bool {
        guard let last = db.wallet.lastObservedAt else { return false }
        return now < last.addingTimeInterval(-BonusRules.clockRollbackTolerance)
    }

    static func effectiveNow(_ db: TBDatabase, now: Date) -> Date {
        max(now, db.wallet.lastObservedAt ?? now)
    }

    static func claimState(_ db: TBDatabase, now: Date) -> ClaimState {
        if isCollectionComplete(db) { return .collectionComplete }
        if isLimitReached(db) { return .limitReached }
        if clockRolledBack(db, now: now) { return .checkDeviceTime }
        if db.wallet.tickets >= BonusRules.ticketCapacity { return .storageFull }
        if let next = db.wallet.nextClaimAt, effectiveNow(db, now: now) < next { return .cooldown(until: next) }
        return .available
    }

    /// lastObservedAt = max(previous, now); never moves backwards.
    static func observe(_ db: inout TBDatabase, now: Date) {
        let observed = max(db.wallet.lastObservedAt ?? now, now)
        if db.wallet.lastObservedAt != observed { db.wallet.lastObservedAt = observed }
    }

    private static func nextBonusSequence(_ db: inout TBDatabase) -> Int64 {
        defer { db.counters.nextBonusSequence += 1 }
        return db.counters.nextBonusSequence
    }

    @discardableResult
    static func claim(_ db: inout TBDatabase, operationID: UUID, now: Date) throws -> BonusClaim {
        if let done = db.claims.values.first(where: { $0.operationID == operationID }) { return done }
        switch claimState(db, now: now) {
        case .available: break
        case .cooldown: throw DomainError.blocked("Your next free ticket isn't ready yet.")
        case .storageFull: throw DomainError.blocked("Ticket storage is full. \(BonusRules.fullText)")
        case .checkDeviceTime: throw DomainError.blocked("Check your device date and time.")
        case .collectionComplete: throw DomainError.blocked(BonusRules.completedText)
        case .limitReached: throw DomainError.blocked("Bonus limit reached.")
        }
        let claimedAt = effectiveNow(db, now: now)
        let claim = BonusClaim(id: UUID(), operationID: operationID, sequence: nextBonusSequence(&db), claimedAt: claimedAt,
                               nextClaimAt: claimedAt.addingTimeInterval(BonusRules.claimInterval), ticketDelta: 1)
        db.claims[claim.id] = claim
        db.wallet.tickets += 1
        db.wallet.nextClaimAt = claim.nextClaimAt
        db.wallet.revision += 1
        observe(&db, now: now)
        return claim
    }

    static func pendingReceipt(_ db: TBDatabase) -> CastReceipt? {
        db.receipts.values.filter { $0.presentedAt == nil }.sorted { $0.sequence < $1.sequence }.first
    }

    static func castBlockReason(_ db: TBDatabase) -> String? {
        if db.wallet.rulesVersion != BonusRules.rulesVersion { return "Bonus rules changed. Update the app." }
        if isCollectionComplete(db) { return BonusRules.completedText }
        if isLimitReached(db) { return "Bonus limit reached." }
        if pendingReceipt(db) != nil { return "Open your last result first." }
        if db.wallet.tickets < 1 { return "You need a free ticket to cast." }
        return nil
    }

    /// Chooses the three centre symbols exactly once, then stores receipt, ticket −1 and Parts +reward together.
    @discardableResult
    static func cast(_ db: inout TBDatabase, operationID: UUID, random: RandomSource, now: Date) throws -> CastReceipt {
        if let done = db.receipts.values.first(where: { $0.operationID == operationID }) { return done }
        if let reason = castBlockReason(db) { throw DomainError.blocked(reason) }
        let symbols = (0..<BonusRules.reelCount).map { _ in BonusRules.strip[random.nextInt(upperBound: BonusRules.strip.count)] }
        let reward = BonusRules.reward(symbols)
        let receipt = CastReceipt(id: UUID(), operationID: operationID, sequence: nextBonusSequence(&db),
                                  rulesVersion: BonusRules.rulesVersion, symbols: symbols, rewardParts: reward,
                                  ticketDelta: -1, createdAt: now, presentedAt: nil)
        db.receipts[receipt.id] = receipt
        db.wallet.tickets -= 1
        db.wallet.parts += reward
        db.wallet.revision += 1
        observe(&db, now: now)
        return receipt
    }

    static func markPresented(_ db: inout TBDatabase, receiptID: UUID, now: Date) {
        guard var receipt = db.receipts[receiptID], receipt.presentedAt == nil else { return }
        receipt.presentedAt = now
        db.receipts[receiptID] = receipt
    }

    @discardableResult
    static func build(_ db: inout TBDatabase, collectibleID: CollectibleID, operationID: UUID, now: Date) throws -> CollectibleOwnership {
        if let done = db.ownerships.values.first(where: { $0.operationID == operationID }) { return done }
        if db.ownerships[collectibleID] != nil { throw DomainError.blocked("You already built this miniature.") }
        let cost = BonusRules.collectibleCost
        guard db.wallet.parts >= cost else {
            throw DomainError.blocked("\(cost - db.wallet.parts) more Parts needed.")
        }
        let ownership = CollectibleOwnership(collectibleID: collectibleID, acquiredAt: now, operationID: operationID,
                                             sequence: nextBonusSequence(&db), costParts: cost)
        db.ownerships[collectibleID] = ownership
        db.wallet.parts -= cost
        db.wallet.revision += 1
        return ownership
    }

    /// Choosing the Home decoration never spends Parts.
    static func display(_ db: inout TBDatabase, collectibleID: CollectibleID?) throws {
        if let id = collectibleID, db.ownerships[id] == nil { throw DomainError.blocked("Build this miniature first.") }
        db.settings.selectedCollectibleID = collectibleID
    }

    /// Bonus ledger reconciliation used by backup import and tests.
    static func ledgerProblems(_ db: TBDatabase) -> [String] {
        var problems: [String] = []
        let tickets = db.claims.count - db.receipts.count
        if tickets != db.wallet.tickets || !(0...BonusRules.ticketCapacity).contains(tickets) {
            problems.append("Tickets don't match the bonus history.")
        }
        let parts = db.receipts.values.reduce(0) { $0 + $1.rewardParts } - BonusRules.collectibleCost * db.ownerships.count
        if parts != db.wallet.parts || parts < 0 { problems.append("Parts don't match the bonus history.") }
        for r in db.receipts.values {
            if r.symbols.count != BonusRules.reelCount || r.rulesVersion != BonusRules.rulesVersion
                || r.rewardParts != BonusRules.reward(r.symbols) || r.ticketDelta != -1 {
                problems.append("A bonus result doesn't follow the rules.")
                break
            }
        }
        if db.claims.values.contains(where: { $0.ticketDelta != 1 }) { problems.append("A ticket claim is invalid.") }
        if db.ownerships.values.contains(where: { $0.costParts != BonusRules.collectibleCost }) { problems.append("A miniature cost is invalid.") }
        if let selected = db.settings.selectedCollectibleID, db.ownerships[selected] == nil {
            problems.append("The displayed miniature isn't built.")
        }
        if db.claims.count > BonusRules.recordLimit || db.receipts.count > BonusRules.recordLimit {
            problems.append("Bonus history is over the limit.")
        }
        // Replay in bonusSequence order: no negative intermediate balance, no overflow of the ticket storage.
        enum Event { case claim, cast(Int), build }
        var events: [(Int64, Event)] = db.claims.values.map { ($0.sequence, .claim) }
        events += db.receipts.values.map { ($0.sequence, .cast($0.rewardParts)) }
        events += db.ownerships.values.map { ($0.sequence, .build) }
        let seqs = events.map(\.0)
        if Set(seqs).count != seqs.count { problems.append("Bonus history order is ambiguous.") }
        if let maxSeq = seqs.max(), maxSeq >= db.counters.nextBonusSequence { problems.append("Bonus counter is behind the history.") }
        var t = 0, p = 0
        for (_, e) in events.sorted(by: { $0.0 < $1.0 }) {
            switch e {
            case .claim: t += 1
            case .cast(let reward): t -= 1; p += reward
            case .build: p -= BonusRules.collectibleCost
            }
            if t < 0 || t > BonusRules.ticketCapacity || p < 0 {
                problems.append("Bonus history has an invalid intermediate balance.")
                break
            }
        }
        let pending = db.receipts.values.filter { $0.presentedAt == nil }
        if pending.count > 1 { problems.append("More than one bonus result is waiting.") }
        return problems
    }
}
