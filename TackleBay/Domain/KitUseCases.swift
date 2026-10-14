import Foundation

struct KitDraft: Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var description: String = ""
    var lines: [KitLine] = []
    var isDemo = false

    init() {}

    init(kit: Kit) {
        id = kit.id
        name = kit.name
        description = kit.description ?? ""
        lines = kit.lines
        isDemo = kit.isDemo
    }
}

enum KitUseCases {
    static let maxLines = 100

    static func isAvailable(_ db: TBDatabase, gearID: UUID) -> Bool {
        guard let gear = db.gear[gearID] else { return false }
        return !gear.isArchived
    }

    static func unavailableCount(_ db: TBDatabase, kit: Kit) -> Int {
        kit.lines.filter { !isAvailable(db, gearID: $0.gearID) }.count
    }

    /// Lines whose gear has fewer ready units than the template wants. Informational only.
    static func shortLines(_ db: TBDatabase, kit: Kit) -> [KitLine] {
        kit.lines.filter { line in
            guard let gear = db.gear[line.gearID], !gear.isArchived else { return false }
            return gear.readyQty < line.requiredQty
        }
    }

    static func validate(_ db: TBDatabase, draft: KitDraft) -> String? {
        if let e = TextRules.check(draft.name, field: "Kit name", range: 1...60) { return e }
        if TextRules.trimmed(draft.description).count > 1000 { return "Description can be up to 1000 characters." }
        if draft.lines.isEmpty { return "Add at least one item to the kit." }
        if draft.lines.count > maxLines { return "A kit can hold up to \(maxLines) items." }
        if Set(draft.lines.map(\.gearID)).count != draft.lines.count { return "Each gear record can appear once per kit." }
        let original = db.kits[draft.id]
        for line in draft.lines {
            if !(1...StockRules.maxQuantity).contains(line.requiredQty) { return "Quantities must be from 1 to 9999." }
            if TextRules.trimmed(line.note).count > 300 { return "Packing notes can be up to 300 characters." }
            let historical = original?.lines.contains { $0.gearID == line.gearID } ?? false
            if !isAvailable(db, gearID: line.gearID) && !historical {
                return "Unavailable gear can't be added to a kit."
            }
            if let gear = db.gear[line.gearID], gear.isDemo != draft.isDemo {
                return draft.isDemo ? "The sample kit can only hold sample gear." : "Sample gear stays in the sample collection. Pick your own gear."
            }
        }
        return nil
    }

    @discardableResult
    static func save(_ db: inout TBDatabase, draft: KitDraft, now: Date) throws -> Kit {
        if let e = validate(db, draft: draft) { throw DomainError.validation(e) }
        var lines = draft.lines
        for i in lines.indices { lines[i].note = TextRules.optional(lines[i].note) }
        if var kit = db.kits[draft.id] {
            kit.name = TextRules.trimmed(draft.name)
            kit.description = TextRules.optional(draft.description)
            kit.lines = lines
            kit.revision += 1
            kit.updatedAt = now
            db.kits[kit.id] = kit
            return kit
        }
        let kit = Kit(id: draft.id, name: TextRules.trimmed(draft.name), description: TextRules.optional(draft.description),
                      lines: lines, isArchived: false, isDemo: draft.isDemo, revision: 1, createdAt: now, updatedAt: now)
        db.kits[kit.id] = kit
        return kit
    }

    static func setArchived(_ db: inout TBDatabase, kitID: UUID, archived: Bool, now: Date) throws {
        guard db.kits[kitID] != nil else { throw DomainError.notFound("This kit is no longer available.") }
        db.kits[kitID]?.isArchived = archived
        db.kits[kitID]?.updatedAt = now
        db.kits[kitID]?.revision += 1
    }

    /// Deleting a template never touches gear, trips or packing lists created from it.
    static func delete(_ db: inout TBDatabase, kitID: UUID) throws {
        guard db.kits[kitID] != nil else { throw DomainError.notFound("This kit is no longer available.") }
        db.kits[kitID] = nil
    }

    /// Copy of the template for the editor; nothing is saved until Save Kit.
    static func duplicateDraft(_ kit: Kit) -> KitDraft {
        var draft = KitDraft(kit: kit)
        draft.id = UUID()
        draft.name = String((kit.name + " copy").prefix(60))
        draft.lines = kit.lines.map { KitLine(id: UUID(), gearID: $0.gearID, requiredQty: $0.requiredQty, importance: $0.importance, note: $0.note) }
        return draft
    }
}
