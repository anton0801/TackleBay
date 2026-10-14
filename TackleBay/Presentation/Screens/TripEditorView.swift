import SwiftUI

struct TripEditorView: View {
    let mode: TripEditorMode
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var draft = TripDraft()
    @State private var original = TripDraft()
    @State private var loaded = false
    @State private var showErrors = false

    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }
    private var editID: UUID? { if case .edit(let id) = mode { return id } else { return nil } }
    private var isDirty: Bool { draft != original }
    private var validation: String? { TripUseCases.validate(draft) }

    var body: some View {
        Group {
            if let id = editID, store.db.trips[id]?.status != .planned {
                MissingRecordView(title: store.db.trips[id] == nil ? "This trip is no longer available" : "Only planned trips can be edited")
            } else {
                screen
            }
        }
        .onAppear(perform: load)
    }

    private var screen: some View {
        HeroScreen(heroHeight: 150, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 210)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, -24)
                    .padding(.bottom, 14)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        HeroTextButton(title: "Cancel", action: cancel)
                        TackleBayLogo(height: 44)
                        Spacer()
                    }
                    Text(title)
                        .tbDisplay(31)
                        .foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.7), radius: 5)
                        .padding(.leading, 58)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 8) {
                FieldCard(icon: "pencil", label: "Trip name") {
                    TBTextField(label: nil, text: $draft.name, placeholder: "e.g. Harbor morning",
                                error: showErrors ? TextRules.check(draft.name, field: "Trip name", range: 1...80) : nil, limit: 80)
                }
                FieldCard(icon: "mappin.and.ellipse", label: "Place") {
                    TBTextField(label: nil, text: $draft.place, placeholder: "e.g. Harbor pier",
                                error: showErrors ? TextRules.check(draft.place, field: "Place", range: 1...100) : nil, limit: 100)
                }
                FieldCard(icon: "calendar", label: "Departure") {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: pickDate) {
                            HStack {
                                Text(Fmt.dayTimeComma(draft.plannedDepartureAt, now: store.now)).tbFont(17, .semibold).foregroundColor(.tbText)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).strokeBorder(Color.tbBorder, lineWidth: 1.2))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Departure, \(Fmt.fullDateTime(draft.plannedDepartureAt))")
                        if draft.plannedDepartureAt < store.now.addingTimeInterval(-60) {
                            Label("This plan date has passed", systemImage: "exclamationmark.circle.fill")
                                .tbFont(14, .semibold).foregroundColor(.tbCare)
                        }
                    }
                }
                if !isEdit && draft.lines.isEmpty {
                    FieldCard(icon: "briefcase.fill", label: "Initial kit") {
                        Button(action: pickKit) {
                            HStack {
                                Text(kitName ?? "No kit").tbFont(17, .semibold).foregroundColor(kitName == nil ? .tbSecondary : .tbText)
                                Spacer()
                                if draft.initialKitID != nil {
                                    Button { draft.initialKitID = nil } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.tbSecondary)
                                    }
                                    .accessibilityLabel("Remove kit")
                                }
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous).strokeBorder(Color.tbBorder, lineWidth: 1.2))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                if !draft.lines.isEmpty && !isEdit {
                    let unavailable = draft.lines.filter { !KitUseCases.isAvailable(store.db, gearID: $0.gearID) }.count
                    InfoBanner(text: "\(Fmt.items(draft.lines.count)) copied from the previous trip. Nothing is packed yet.",
                               detail: unavailable > 0 ? "\(unavailable) unavailable — resolve them in the packing list." : nil, kind: .info)
                }
                FieldCard(icon: "doc.text.fill", label: "Notes") {
                    TBTextEditor(text: $draft.note, placeholder: "Add a note", minHeight: 64, limit: 2000)
                }
                InfoBanner(text: "Your stock changes only when you start.", kind: .info)
                if showErrors, let v = validation { InfoBanner(text: v, kind: .error) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: save) { Text(isEdit ? "Save changes" : "Save trip") }.buttonStyle(GoldButtonStyle())
            }
        }
    }

    private var title: String {
        switch mode {
        case .new: return "New Trip"
        case .edit: return "Edit Trip"
        case .repeatTrip: return "Repeat Trip"
        }
    }

    private var kitName: String? { draft.initialKitID.flatMap { store.db.kits[$0]?.name } }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .new(let kitID):
            var d = TripDraft()
            d.plannedDepartureAt = store.now
            if let kitID = kitID, let kit = store.db.kits[kitID] {
                d.initialKitID = kitID
                d.isDemo = kit.isDemo
            }
            draft = d
            original = d
        case .edit(let id):
            if let trip = store.db.trips[id] { draft = TripDraft(trip: trip) }
            original = draft
        case .repeatTrip(let id):
            draft = TripUseCases.repeatDraft(store.db, tripID: id, now: store.now) ?? TripDraft()
            original = draft
        }
    }

    private func pickDate() {
        ui.present {
            DateSheet(date: draft.plannedDepartureAt) { date in
                draft.plannedDepartureAt = date
                ui.dismissSheet()
            }
        }
    }

    private func pickKit() {
        ui.present {
            KitPickerSheet(title: "Initial kit", isDemo: draft.isDemo, allowNew: false) { kitID in
                draft.initialKitID = kitID
                ui.dismissSheet()
                if let kitID = kitID, let kit = store.db.kits[kitID] {
                    let unavailable = KitUseCases.unavailableCount(store.db, kit: kit)
                    if unavailable > 0 {
                        ui.info("Some kit items are unavailable", "\(unavailable) archived item(s) won't be added. Only available gear goes into the packing list.")
                    }
                }
            }
        }
    }

    private func save() {
        guard validation == nil else {
            showErrors = true
            services.haptics.warning()
            return
        }
        if isEdit {
            guard ui.run({ try store.perform { db, now in try TripUseCases.updatePlan(&db, draft: draft, now: now) } }) else { return }
            original = draft
            router.pop()
        } else {
            guard ui.run({ try store.perform { db, now in try TripUseCases.create(&db, draft: draft, now: now) } }) else { return }
            services.tapFeedback()
            original = draft
            router.replaceTop(with: .packing(draft.id, applyKit: nil))
        }
    }

    private func cancel() {
        guard isDirty else { router.pop(); return }
        ui.alert = AlertItem(title: "Discard this trip?", message: "Your changes haven't been saved.", actions: [
            AlertAction(title: "Keep Editing", role: .cancel),
            AlertAction(title: "Discard Changes", role: .destructive) { router.pop() }
        ])
    }
}

/// Field block with a square icon tile, uppercase label and the control.
struct FieldCard<Content: View>: View {
    let icon: String
    let label: String
    let content: Content

    init(icon: String, label: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: 0x14A6B8))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xDDF3F8)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).tracking(0.8).tbFont(10, .semibold).foregroundColor(.tbSecondary)
                content
            }
        }
        .tbCard(radius: 16, padding: 10)
    }
}

struct DateSheet: View {
    @State var date: Date
    let onDone: (Date) -> Void
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Departure", subtitle: "Planned date and time. It doesn't start the trip.") { ui.dismissSheet() }
            DatePicker("Date", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .tint(.tbTeal)
            DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute])
                .tbFont(18, .semibold)
                .foregroundColor(.tbText)
            Button { onDone(date) } label: { Text("Done") }.buttonStyle(GoldButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
