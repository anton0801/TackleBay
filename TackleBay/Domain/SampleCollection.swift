import Foundation

/// Optional, clearly marked demo space. Never created automatically and never touches the bonus.
enum SampleCollection {
    struct Item {
        let name: String
        let category: GearCategory
        let tracking: TrackingType
        let unit: CountingUnit
        let storage: String
        let ready: Int
        let care: Int
        let art: String
        let note: String?
    }

    static let items: [Item] = [
        Item(name: "Shore rod", category: .rods, tracking: .reusable, unit: .piece, storage: "Blue rack", ready: 1, care: 0, art: "tb_gear_rod", note: nil),
        Item(name: "Tide reel", category: .reels, tracking: .reusable, unit: .piece, storage: "Shelf A", ready: 2, care: 1, art: "tb_symbol_reel",
             note: "Smooth, reliable and ready for bay adventures."),
        Item(name: "Tackle box", category: .containers, tracking: .reusable, unit: .piece, storage: "By the door", ready: 1, care: 0, art: "tb_tackle_box", note: nil),
        Item(name: "Hook packs", category: .terminalTackle, tracking: .consumable, unit: .pack, storage: "Drawer 2", ready: 12, care: 0, art: "tb_hook_packs", note: nil),
        Item(name: "Landing net", category: .tools, tracking: .reusable, unit: .piece, storage: "By the door", ready: 1, care: 0, art: "tb_gear_net", note: nil),
        Item(name: "Rain jacket", category: .clothing, tracking: .reusable, unit: .piece, storage: "Hall closet", ready: 1, care: 0, art: "tb_rain_jacket", note: nil),
        Item(name: "Line spool", category: .supplies, tracking: .consumable, unit: .spool, storage: "Drawer 1", ready: 3, care: 0, art: "tb_gear_spool", note: nil),
        Item(name: "Pliers", category: .tools, tracking: .reusable, unit: .piece, storage: "Shelf A", ready: 1, care: 0, art: "tb_gear_pliers", note: nil),
        Item(name: "Fishing vest", category: .clothing, tracking: .reusable, unit: .piece, storage: "Hall closet", ready: 1, care: 0, art: "tb_gear_vest", note: nil)
    ]

    static func isLoaded(_ db: TBDatabase) -> Bool {
        db.gear.values.contains { $0.isDemo } || db.kits.values.contains { $0.isDemo } || db.trips.values.contains { $0.isDemo }
    }

    static func load(_ db: inout TBDatabase, now: Date, calendar: Calendar = .current) throws {
        guard !isLoaded(db) else { return }
        var ids: [String: UUID] = [:]
        for (offset, item) in items.enumerated() {
            var draft = GearDraft()
            draft.name = item.name
            draft.category = item.category
            draft.trackingType = item.tracking
            draft.countingUnit = item.unit
            draft.storage = item.storage
            draft.note = item.note ?? ""
            draft.readyQty = item.ready
            draft.careQty = item.care
            // Spread creation times so "Recently Added" lists the collection in catalogue order.
            let gear = try GearUseCases.create(&db, draft: draft, isDemo: true, sampleArt: item.art,
                                               now: now.addingTimeInterval(-Double(offset)))
            ids[item.name] = gear.id
        }
        func line(_ name: String, _ qty: Int, _ importance: Importance) -> KitLine {
            KitLine(id: UUID(), gearID: ids[name]!, requiredQty: qty, importance: importance, note: nil)
        }
        var kit = KitDraft()
        kit.name = "Shore essentials"
        kit.description = "Light setup for the pier."
        kit.isDemo = true
        kit.lines = [line("Shore rod", 1, .required), line("Tide reel", 1, .required), line("Hook packs", 2, .required), line("Rain jacket", 1, .optional)]
        try KitUseCases.save(&db, draft: kit, now: now)

        var trip = TripDraft()
        trip.name = "Harbor morning"
        trip.place = "Harbor pier"
        trip.isDemo = true
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        trip.plannedDepartureAt = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        trip.lines = ["Shore rod", "Tide reel", "Tackle box", "Landing net", "Rain jacket"].map {
            TripLine(id: UUID(), gearID: ids[$0]!, requiredQty: 1, packedQty: 0, importance: .required, packingNote: nil, snapshot: nil, takenQty: nil)
        } + [TripLine(id: UUID(), gearID: ids["Hook packs"]!, requiredQty: 2, packedQty: 0, importance: .required, packingNote: nil, snapshot: nil, takenQty: nil)]
        try TripUseCases.create(&db, draft: trip, now: now)
    }

    static func removeBlockReason(_ db: TBDatabase) -> String? {
        if db.trips.values.contains(where: { $0.isDemo && $0.isOpenTrip }) {
            return "Return the sample trip before removing the sample collection."
        }
        return nil
    }

    /// Removes only demo records with their history. Real records and the bonus stay exactly as they were.
    static func remove(_ db: inout TBDatabase) throws {
        if let reason = removeBlockReason(db) { throw DomainError.blocked(reason) }
        let gearIDs = Set(db.gear.values.filter { $0.isDemo }.map(\.id))
        let tripIDs = Set(db.trips.values.filter { $0.isDemo }.map(\.id))
        for id in gearIDs { db.gear[id] = nil }
        for m in db.movements.values where gearIDs.contains(m.gearID) { db.movements[m.id] = nil }
        for k in db.kits.values where k.isDemo { db.kits[k.id] = nil }
        for id in tripIDs { db.trips[id] = nil }
        for d in db.returnDrafts.values where tripIDs.contains(d.tripID) { db.returnDrafts[d.id] = nil }
        for r in db.returnResults.values where tripIDs.contains(r.tripID) { db.returnResults[r.id] = nil }
    }
}
