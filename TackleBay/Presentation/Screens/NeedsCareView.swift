import SwiftUI

struct NeedsCareView: View {
    @State var tripFilter: UUID?
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var search = ""
    @State private var showArchived = false

    init(tripFilter: UUID?) {
        _tripFilter = State(initialValue: tripFilter)
    }

    private var careGear: [Gear] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return store.db.gear.values
            .filter { $0.careQty > 0 && !$0.isArchived && $0.trackingType == .reusable }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.storage.lowercased().contains(q) }
            .filter { g in
                guard let t = tripFilter else { return true }
                return store.db.movements.values.contains { $0.gearID == g.id && $0.tripID == t && $0.deltaCare > 0 }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var archivedCare: [Gear] {
        store.db.gear.values.filter { $0.careQty > 0 && $0.isArchived }.sorted { $0.name < $1.name }
    }

    private var totalActiveCare: Int { store.db.gear.values.filter { $0.careQty > 0 && !$0.isArchived }.count }

    var body: some View {
        let empty = totalActiveCare == 0
        return HeroScreen(heroHeight: empty ? 214 : 236, overlap: 20, contentTopPadding: 14) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: empty ? 190 : 196)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, empty ? -30 : -44)
                    .padding(.bottom, empty ? 14 : 34)
                if !empty {
                    Image("tb_care_tools").resizable().scaledToFit().frame(width: 150)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 96)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        CircleIconButton(systemName: "chevron.left", style: .light, size: 38, label: "Back") { router.pop() }
                        if empty {
                            Text("Needs Care").tbFont(28, .heavy).foregroundColor(.tbText)
                                .shadow(color: .white.opacity(0.7), radius: 5)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    if !empty {
                        Text("Needs Care").tbDisplay(32).foregroundColor(.tbText)
                            .shadow(color: .white.opacity(0.7), radius: 5)
                            .accessibilityAddTraits(.isHeader)
                        Text("Check it before\nthe next trip.").tbFont(16, .semibold).foregroundColor(.tbText)
                            .shadow(color: .white.opacity(0.7), radius: 4)
                    }
                }
                .padding(.horizontal, 14)
            }
        } content: {
            if empty {
                emptyState
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(spacing: 10) {
            if let t = tripFilter, let trip = store.db.trips[t] {
                HStack {
                    Text("From \(trip.displayName)").tbFont(16, .semibold).foregroundColor(.tbText)
                    Button { tripFilter = nil } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.tbSecondary) }
                        .accessibilityLabel("Show all trips")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.tbIceTile))
            }
            if totalActiveCare > 3 || !search.isEmpty {
                SearchField(text: $search, placeholder: "Search care items...")
            }
            let items = careGear
            if items.isEmpty {
                Text("Nothing matches.").tbFont(17, .semibold).foregroundColor(.tbSecondary).padding(.vertical, 20)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, gear in
                CareCard(gear: gear, prominent: index == 0)
            }
            archivedSection
            Text("Marking ready is your own check. It isn't a repair or safety confirmation.")
                .tbFont(12).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("tb_care_tools").resizable().scaledToFit().frame(width: 290, height: 230).accessibilityHidden(true)
            Text("Nothing needs care right now")
                .tbFont(30, .heavy, style: .title1, max: 42).foregroundColor(.tbText).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
            Text("Your active gear has no items marked for care.")
                .tbFont(16).foregroundColor(.tbText).multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            if !archivedCare.isEmpty {
                Button(showArchived ? "Hide archived gear" : "Show archived gear") { withAnimation { showArchived.toggle() } }
                    .tbFont(16, .bold).foregroundColor(Color(hex: 0x1366C9))
                    .overlay(Rectangle().fill(Color(hex: 0x1366C9)).frame(height: 1.2).offset(y: 10), alignment: .bottom)
                    .frame(minHeight: 44)
                archivedSection
            }
            Button { router.select(.home); router.popToRoot() } label: { ButtonLabel(title: "Back to my bay", chevron: true) }
                .buttonStyle(GoldButtonStyle())
                .padding(.top, 8)
        }
    }

    @ViewBuilder private var archivedSection: some View {
        if !archivedCare.isEmpty {
            if totalActiveCare > 0 {
                Button(showArchived ? "Hide archived gear" : "Show archived gear (\(archivedCare.count))") { withAnimation { showArchived.toggle() } }
                    .tbFont(17, .semibold).foregroundColor(Color(hex: 0x1366C9)).frame(minHeight: 44)
            }
            if showArchived {
                ForEach(archivedCare) { gear in
                    HStack(spacing: 12) {
                        GearImage(gear: gear, width: 56, corner: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gear.name).tbFont(18, .bold).foregroundColor(.tbText)
                            Text("Archived · \(gear.careQty) need care").tbFont(15).foregroundColor(.tbSecondary)
                        }
                        Spacer()
                        Button("Restore") {
                            ui.run { try store.perform { db, now in try GearUseCases.restore(&db, gearID: gear.id, now: now) } }
                        }
                        .buttonStyle(OutlineButtonStyle(height: 42, compact: true))
                        .fixedSize()
                    }
                    .tbCard(radius: 18, padding: 10)
                }
            }
        }
    }
}

struct CareCard: View {
    let gear: Gear
    let prominent: Bool
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var quantity = 1

    var body: some View {
        let last = GearUseCases.lastCareMovement(store.db, gearID: gear.id)
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button { router.push(.gearDetail(gear.id)) } label: {
                    GearImage(gear: gear, width: 96, height: 96, corner: 14)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Open \(gear.name)")
                VStack(alignment: .leading, spacing: 5) {
                    Text(gear.name).tbFont(17, .heavy).foregroundColor(.tbText).lineLimit(2).minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill").font(.system(size: 11)).foregroundColor(Color(hex: 0xEB5A2E))
                        Text("\(gear.careQty) needs care").tbFont(12, .medium).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 11)).foregroundColor(Color(hex: 0x8FA6B4))
                        Text(gear.storage).tbFont(12).foregroundColor(.tbSecondary).lineLimit(1)
                    }
                    if let last = last {
                        Text("Since \(Fmt.day(last.timestamp, now: store.now))").tbFont(11).foregroundColor(.tbSecondary)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    CareStepper(value: $quantity, range: 1...max(1, gear.careQty))
                    if prominent {
                        Button(action: markReady) { ButtonLabel(title: "Mark ready", chevron: true) }
                            .buttonStyle(GoldButtonStyle(height: 38, compact: true))
                            .fixedSize()
                    } else {
                        Button(action: markReady) { ButtonLabel(title: "Mark ready", chevron: true) }
                            .buttonStyle(OutlineButtonStyle(height: 38, tint: Color(hex: 0x3D9BE0), compact: true))
                            .fixedSize()
                    }
                }
            }
            Button {
                router.push(.adjustStock(gear.id, operation: .removeStock, tripID: nil))
            } label: {
                Text("Remove damaged stock").tbFont(12, .semibold).foregroundColor(.tbError).frame(minHeight: 32)
            }
            .frame(minHeight: 44)
        }
        .tbCard(radius: 18, padding: 8)
        .onChange(of: gear.careQty) { q in quantity = min(max(1, quantity), max(1, q)) }
    }

    private func markReady() {
        let q = min(quantity, gear.careQty)
        let revision = gear.stockRevision
        ui.present {
            MarkReadySheet(gear: gear, quantity: q, expectedRevision: revision)
        }
    }
}

/// − n + segmented box used on care cards.
struct CareStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            segment("minus", enabled: value > range.lowerBound) { value -= 1 }
            Rectangle().fill(Color.tbCardBorder).frame(width: 1, height: 30)
            Text("\(value)").tbFont(16, .bold).foregroundColor(.tbText).frame(minWidth: 34)
            Rectangle().fill(Color.tbCardBorder).frame(width: 1, height: 30)
            segment("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quantity to mark ready")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func segment(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .foregroundColor(enabled ? (icon == "plus" ? Color(hex: 0x1366C9) : .tbText) : .tbDisabledText)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

struct MarkReadySheet: View {
    let gear: Gear
    let quantity: Int
    let expectedRevision: Int64
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var note = ""
    @State private var operationID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Mark \(quantity) ready", subtitle: gear.name) { ui.dismissSheet() }
            HStack(spacing: 12) {
                PreviewTile(title: "Ready", before: gear.readyQty, after: gear.readyQty + quantity, icon: "checkmark", tint: .tbReady)
                PreviewTile(title: "Care", before: gear.careQty, after: gear.careQty - quantity, icon: "wrench.fill", tint: .tbCoral)
            }
            Text("\(gear.unit.format(gear.ownedQty)) owned stays the same.").tbFont(15).foregroundColor(.tbSecondary)
            FieldLabel(text: "Note (optional)")
            TBTextField(label: nil, text: $note, placeholder: "Cleaned and checked", limit: 1000)
            Button(action: confirm) { ButtonLabel(title: "Confirm", icon: "checkmark.circle.fill") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func confirm() {
        do {
            try store.perform { db, now in
                try GearUseCases.markReady(&db, gearID: gear.id, quantity: quantity, note: note, expectedRevision: expectedRevision,
                                           operationID: operationID, now: now)
            }
            services.haptics.success()
            ui.dismissSheet()
            ui.showToast("\(quantity) marked ready")
        } catch {
            ui.dismissSheet()
            ui.show(error)
        }
    }
}
