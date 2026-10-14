import SwiftUI

struct KitEditorView: View {
    let mode: KitEditorMode
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var draft = KitDraft()
    @State private var original = KitDraft()
    @State private var loaded = false
    @State private var editing = true
    @State private var showError = false

    private var existingKit: Kit? {
        switch mode {
        case .edit(let id, _): return store.db.kits[id]
        default: return nil
        }
    }

    private var isSaved: Bool { store.db.kits[draft.id] != nil }
    private var isDirty: Bool { draft != original }
    private var validation: String? { KitUseCases.validate(store.db, draft: draft) }

    var body: some View {
        Group {
            if case .edit = mode, existingKit == nil {
                MissingRecordView(title: "This kit is no longer available")
            } else {
                screen
            }
        }
        .onAppear(perform: load)
    }

    private var screen: some View {
        HeroScreen(heroHeight: 150, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 190)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, -28)
                    .padding(.bottom, 14)
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        TackleBayLogo(height: 44)
                        HStack {
                            if editing {
                                Button("Cancel", action: cancel).tbFont(16, .semibold).foregroundColor(Color(hex: 0x1366C9)).frame(minHeight: 44)
                            } else {
                                CircleIconButton(systemName: "chevron.left", style: .light, label: "Back") { router.pop() }
                            }
                            Spacer()
                            if editing {
                                GoldPillButton(title: "Save", action: save)
                            } else {
                                GoldPillButton(title: "Edit") { editing = true }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Text(draft.name.isEmpty ? "New kit" : draft.name)
                            .tbFont(24, .heavy, style: .title1, max: 34)
                            .foregroundColor(.tbText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .shadow(color: .white.opacity(0.7), radius: 5)
                            .accessibilityAddTraits(.isHeader)
                        if editing {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: 0x1366C9))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: 250, alignment: .leading)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 8) {
                if editing {
                    nameCard
                    noteCard
                } else if !draft.description.isEmpty {
                    Text(draft.description).tbFont(15).foregroundColor(.tbSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if draft.isDemo {
                    InfoBanner(text: "Sample kit — it can only hold sample gear.", kind: .info)
                }
                ForEach(Array(draft.lines.enumerated()), id: \.element.id) { index, line in
                    KitLineRow(line: binding(for: line.id), index: index, count: draft.lines.count, editing: editing,
                               onEdit: { editRow(line.id) }, onRemove: { removeRow(line.id) })
                }
                if editing {
                    Button(action: addGear) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .heavy)).foregroundColor(.white)
                                .frame(width: 26, height: 26).background(Circle().fill(Color(hex: 0x17A9BC)))
                            Text("Add gear").tbFont(16, .bold).foregroundColor(Color(hex: 0x1366C9))
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xF2FBFD)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(hex: 0x86D6E2), style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(draft.lines.count >= KitUseCases.maxLines)
                }
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: 0x7E93A1))
                    Text("Kits do not reserve stock.").tbFont(13).foregroundColor(.tbSecondary)
                }
                .padding(.top, 2)
                if showError, let v = validation {
                    InfoBanner(text: v, kind: .error)
                }
                if !editing, let kit = existingKit {
                    viewModeActions(kit)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editing {
                BottomActionBar {
                    Button(action: save) { Text("Save kit") }.buttonStyle(GoldButtonStyle())
                }
            }
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NAME").tracking(0.8).tbFont(10, .semibold).foregroundColor(.tbSecondary)
            HStack {
                TextField("e.g. Shore essentials", text: $draft.name)
                    .tbFont(16, .medium)
                    .foregroundColor(.tbText)
                    .onChange(of: draft.name) { if $0.count > 60 { draft.name = String($0.prefix(60)) } }
                    .accessibilityLabel("Kit name")
                Image(systemName: "pencil").foregroundColor(Color(hex: 0x1366C9)).accessibilityHidden(true)
            }
        }
        .tbCard(radius: 14, padding: 10)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NOTE").tracking(0.8).tbFont(10, .semibold).foregroundColor(.tbSecondary)
            HStack(alignment: .top) {
                TextField("Light setup for the pier.", text: $draft.description)
                    .tbFont(15)
                    .foregroundColor(.tbText)
                    .onChange(of: draft.description) { if $0.count > 1000 { draft.description = String($0.prefix(1000)) } }
                    .accessibilityLabel("Kit note")
                Image(systemName: "pencil").foregroundColor(Color(hex: 0x1366C9)).accessibilityHidden(true)
            }
        }
        .tbCard(radius: 14, padding: 10)
    }

    private func viewModeActions(_ kit: Kit) -> some View {
        let actions = KitActions(kit: kit)
        return VStack(spacing: 8) {
            if !kit.isArchived {
                Button { actions.useForTrip() } label: { ButtonLabel(title: "Use for trip", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
            }
            Button { router.push(.kitEditor(.duplicate(kit.id))) } label: { ButtonLabel(title: "Duplicate", icon: "plus.square.on.square") }
                .buttonStyle(OutlineButtonStyle(height: 46))
            HStack(spacing: 10) {
                Button { actions.setArchived(!kit.isArchived) } label: { Text(kit.isArchived ? "Restore" : "Archive") }
                    .buttonStyle(SoftButtonStyle(height: 44))
                Button { actions.delete() } label: { Text("Delete") }
                    .buttonStyle(SoftButtonStyle(height: 44, foreground: .tbError))
            }
        }
        .padding(.top, 6)
    }

    // MARK: Data

    private func binding(for id: UUID) -> Binding<KitLine> {
        Binding(get: { draft.lines.first { $0.id == id } ?? KitLine(id: id, gearID: UUID(), requiredQty: 1, importance: .required, note: nil) },
                set: { new in if let i = draft.lines.firstIndex(where: { $0.id == id }) { draft.lines[i] = new } })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .new(let addGear):
            var d = KitDraft()
            if let gearID = addGear, let gear = store.db.gear[gearID] {
                d.isDemo = gear.isDemo
                d.lines = [KitLine(id: UUID(), gearID: gearID, requiredQty: 1, importance: .required, note: nil)]
            }
            draft = d
            original = KitDraft()
            editing = true
        case .edit(let id, let addGear):
            guard let kit = store.db.kits[id] else { return }
            draft = KitDraft(kit: kit)
            original = draft
            editing = addGear != nil
            #if DEBUG
            if DebugScenario.requested == "kit_editor" { editing = true }
            #endif
            if let gearID = addGear {
                if let existing = draft.lines.first(where: { $0.gearID == gearID }) {
                    DispatchQueue.main.async { editRow(existing.id) }
                } else {
                    draft.lines.append(KitLine(id: UUID(), gearID: gearID, requiredQty: 1, importance: .required, note: nil))
                }
            }
        case .duplicate(let id):
            guard let kit = store.db.kits[id] else { return }
            draft = KitUseCases.duplicateDraft(kit)
            original = KitDraft()
            editing = true
        }
    }

    private func addGear() {
        let existing = Set(draft.lines.map(\.gearID))
        ui.present {
            GearPickerSheet(title: "Add gear", isDemo: draft.isDemo, existing: existing) { gearID in
                ui.dismissSheet()
                if let line = draft.lines.first(where: { $0.gearID == gearID }) {
                    editRow(line.id)
                } else {
                    draft.lines.append(KitLine(id: UUID(), gearID: gearID, requiredQty: 1, importance: .required, note: nil))
                }
            }
        }
    }

    private func editRow(_ id: UUID) {
        guard let line = draft.lines.first(where: { $0.id == id }) else { return }
        let name = store.db.gear[line.gearID]?.name ?? "Unavailable gear"
        ui.present {
            KitLineSheet(name: name, line: line, canMoveUp: draft.lines.first?.id != id, canMoveDown: draft.lines.last?.id != id,
                         available: KitUseCases.isAvailable(store.db, gearID: line.gearID), isDemo: draft.isDemo,
                         excluded: Set(draft.lines.map(\.gearID))) { action in
                ui.dismissSheet()
                switch action {
                case .save(let updated):
                    if let i = draft.lines.firstIndex(where: { $0.id == id }) { draft.lines[i] = updated }
                case .move(let delta):
                    if let i = draft.lines.firstIndex(where: { $0.id == id }) {
                        let j = min(max(i + delta, 0), draft.lines.count - 1)
                        draft.lines.swapAt(i, j)
                    }
                case .remove:
                    removeRow(id)
                }
                if !editing { editing = true }
            }
        }
    }

    private func removeRow(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) { draft.lines.removeAll { $0.id == id } }
        if !editing { editing = true }
    }

    private func save() {
        if validation != nil {
            showError = true
            services.haptics.warning()
            return
        }
        let ok = ui.run { try store.perform { db, now in try KitUseCases.save(&db, draft: draft, now: now) } }
        guard ok else { return }
        services.tapFeedback()
        original = draft
        ui.showToast("Kit saved")
        if case .edit = mode {
            editing = false
        } else {
            router.replaceTop(with: .kitEditor(.edit(draft.id, addGear: nil)))
        }
    }

    private func cancel() {
        let discard = {
            if case .edit = mode, isSaved {
                draft = original
                editing = false
            } else {
                router.pop()
            }
        }
        guard isDirty else { discard(); return }
        ui.alert = AlertItem(title: "Discard changes?", message: "Your kit changes haven't been saved.", actions: [
            AlertAction(title: "Keep Editing", role: .cancel),
            AlertAction(title: "Discard Changes", role: .destructive, action: discard)
        ])
    }
}

struct KitLineRow: View {
    @Binding var line: KitLine
    let index: Int
    let count: Int
    let editing: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    @EnvironmentObject private var store: TackleStore

    var body: some View {
        let gear = store.db.gear[line.gearID]
        let available = KitUseCases.isAvailable(store.db, gearID: line.gearID)
        HStack(spacing: 8) {
            GearImage(gear: gear, width: 70, height: 64, corner: 12)
                .opacity(available ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 6) {
                Text(gear?.name ?? "Unavailable gear").tbFont(15, .heavy).foregroundColor(.tbText).lineLimit(2)
                if !available {
                    Badge(text: "Unavailable", color: .tbError)
                }
                HStack(spacing: 6) {
                    if editing {
                        MiniStepper(value: $line.requiredQty, range: 1...StockRules.maxQuantity, name: "Required quantity")
                    } else {
                        Text("× \(line.requiredQty)").tbFont(15, .bold).foregroundColor(.tbText)
                    }
                    Button {
                        if editing { line.importance = line.importance == .required ? .optional : .required }
                    } label: {
                        Text(line.importance.title)
                            .tbFont(11, .bold)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundColor(line.importance == .required ? Color(hex: 0x157A5C) : .tbSecondary)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 22)
                            .background(Capsule().fill(line.importance == .required ? Color(hex: 0xD5F2E6) : Color(hex: 0xE6ECEF)))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!editing)
                    .accessibilityLabel("\(line.importance.title). \(editing ? "Double tap to switch" : "")")
                }
                .frame(height: 30)
                if let gear = gear, available, gear.readyQty < line.requiredQty {
                    Text("Only \(gear.unit.format(gear.readyQty)) ready now").tbFont(11, .medium).foregroundColor(.tbCare)
                }
            }
            Spacer(minLength: 0)
            Rectangle().fill(Color.tbBorder).frame(width: 1, height: 40)
            Button(action: onEdit) {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.tbText)
                    .frame(width: 28, height: 44)
            }
            .accessibilityLabel("Edit row")
            if editing {
                Rectangle().fill(Color.tbBorder).frame(width: 1, height: 40)
                Button(action: onRemove) {
                    Image(systemName: "trash.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: 0xE5484D))
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("Remove \(gear?.name ?? "row")")
            }
        }
        .tbCard(radius: 16, padding: 6)
    }
}

/// Compact − n + used inside list rows (26 pt circles, 44 pt hit areas).
struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let name: String

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)").tbFont(15, .bold).foregroundColor(.tbText).frame(minWidth: 22)
            button("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? .tbText : .tbDisabledText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.tbIceTile))
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

enum KitLineAction {
    case save(KitLine)
    case move(Int)
    case remove
}

struct KitLineSheet: View {
    let name: String
    @State var line: KitLine
    let canMoveUp: Bool
    let canMoveDown: Bool
    let available: Bool
    let isDemo: Bool
    let excluded: Set<UUID>
    let onDone: (KitLineAction) -> Void
    @State private var note = ""
    @EnvironmentObject private var ui: AppUI

    init(name: String, line: KitLine, canMoveUp: Bool, canMoveDown: Bool, available: Bool, isDemo: Bool, excluded: Set<UUID>, onDone: @escaping (KitLineAction) -> Void) {
        self.name = name
        _line = State(initialValue: line)
        _note = State(initialValue: line.note ?? "")
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.available = available
        self.isDemo = isDemo
        self.excluded = excluded
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: name, subtitle: "Kit row") { ui.dismissSheet() }
            if !available {
                InfoBanner(text: "This gear is unavailable. Remove the row or keep it until you replace it.", kind: .warning)
            }
            FieldLabel(text: "Required quantity")
            IntStepper(value: $line.requiredQty, range: 1...StockRules.maxQuantity, size: 50, accessibilityName: "Required quantity")
            FieldLabel(text: "Importance")
            TBSegmented(options: [(Importance.required, "Required", nil), (Importance.optional, "Optional", nil)], selection: $line.importance, height: 48)
            FieldLabel(text: "Packing note (optional)")
            TBTextField(label: nil, text: $note, placeholder: "e.g. Check the drag", limit: 300)
            HStack(spacing: 10) {
                Button { onDone(.move(-1)) } label: { Label("Move up", systemImage: "arrow.up") }
                    .buttonStyle(SoftButtonStyle(height: 46)).disabled(!canMoveUp)
                Button { onDone(.move(1)) } label: { Label("Move down", systemImage: "arrow.down") }
                    .buttonStyle(SoftButtonStyle(height: 46)).disabled(!canMoveDown)
            }
            Button {
                var updated = line
                updated.note = TextRules.optional(note)
                onDone(.save(updated))
            } label: { Text("Done") }
            .buttonStyle(GoldButtonStyle())
            Button(role: .destructive) { onDone(.remove) } label: { Text("Remove row") }
                .buttonStyle(SoftButtonStyle(height: 48, foreground: .tbError))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}
