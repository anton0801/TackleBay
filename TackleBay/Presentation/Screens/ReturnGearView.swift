import SwiftUI

struct ReturnGearView: View {
    let tripID: UUID
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var expanded: UUID?
    @State private var didPickInitial = false

    var body: some View {
        if let trip = store.db.trips[tripID] {
            if trip.status == .returning, let draft = store.db.draft(for: tripID) {
                screen(trip, draft)
                    .onAppear {
                        guard !didPickInitial else { return }
                        didPickInitial = true
                        expanded = takenLines(trip).first { draft.entry(for: $0.id)?.confirmed != true }?.id
                        #if DEBUG
                        if DebugScenario.requested == "return_validation" {
                            expanded = takenLines(trip).first { store.db.gear[$0.gearID]?.name == "Hook packs" }?.id ?? expanded
                        }
                        #endif
                    }
            } else if trip.status == .completed {
                MissingRecordView(title: "This return is already confirmed")
            } else if trip.status == .active {
                VStack(spacing: 16) {
                    Spacer()
                    Text("Return isn't started").tbFont(26, .heavy).foregroundColor(.tbText)
                    Button { router.replaceTop(with: .activeTrip(trip.id)) } label: { ButtonLabel(title: "Open trip", chevron: true) }
                        .buttonStyle(GoldButtonStyle()).padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                MissingRecordView(title: "This trip isn't being returned")
            }
        } else {
            MissingRecordView(title: "This trip is no longer available")
        }
    }

    private func takenLines(_ trip: Trip) -> [TripLine] { trip.lines.filter { ($0.takenQty ?? 0) > 0 } }

    private func screen(_ trip: Trip, _ draft: ReturnDraft) -> some View {
        let lines = takenLines(trip)
        let checked = lines.filter { draft.entry(for: $0.id)?.confirmed == true }.count
        return HeroScreen(heroHeight: 196, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    ZStack {
                        TackleBayLogo(height: 36)
                        HStack {
                            CircleIconButton(systemName: "chevron.left", style: .light, size: 38, label: "Save and close") { router.pop() }
                            Spacer()
                            Button { saveAndClose() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0x1366C9))
                                    Text("Save & close").tbFont(13, .semibold).foregroundColor(.tbText)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(Capsule().fill(Color.white.opacity(0.94)))
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    Text("Return Gear").tbDisplay(28).foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.7), radius: 5)
                        .accessibilityAddTraits(.isHeader)
                    Text("Check and return your gear\nfrom the trip.").tbFont(13, .medium).foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.7), radius: 4)
                    Text("\(checked) of \(lines.count) items checked").tbFont(13, .bold).foregroundColor(.tbText).padding(.top, 2)
                        .shadow(color: .white.opacity(0.7), radius: 4)
                    TBProgressBar(fraction: lines.isEmpty ? 0 : Double(checked) / Double(lines.count), height: 9)
                        .frame(maxWidth: 230)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 8) {
                ForEach(lines) { line in
                    if expanded == line.id {
                        ReturnRowExpanded(trip: trip, line: line, draft: draft) {
                            withAnimation(.easeOut(duration: 0.2)) { expanded = nil }
                        } onConfirmed: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                expanded = takenLines(trip).first { $0.id != line.id && store.db.draft(for: tripID)?.entry(for: $0.id)?.confirmed != true }?.id
                            }
                        }
                    } else {
                        ReturnRowCollapsed(line: line, entry: draft.entry(for: line.id)) {
                            withAnimation(.easeOut(duration: 0.2)) { expanded = line.id }
                        }
                    }
                }
                if checked < lines.count {
                    InfoBanner(text: "Account for every item before finishing.", kind: .warning)
                }
                Button(action: continueTrip) {
                    Text("Still on the water? Continue trip").tbFont(14, .semibold).foregroundColor(Color(hex: 0x1366C9))
                        .frame(minHeight: 44)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { review() } label: { ButtonLabel(title: "Review return", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
            }
        }
    }

    private func saveAndClose() {
        ui.showToast("Return saved as a draft")
        router.pop()
    }

    private func continueTrip() {
        ui.confirm("Continue the trip?", message: "This return draft will be deleted and the trip stays on the water. Stock doesn't change.",
                   confirm: "Continue trip") {
            if ui.run({ try store.perform { db, now in try TripUseCases.continueTrip(&db, tripID: tripID, now: now) } }) {
                router.replaceTop(with: .activeTrip(tripID))
            }
        }
    }

    private func review() {
        ui.present {
            ReturnReviewSheet(tripID: tripID) { done in
                ui.dismissSheet()
                if done {
                    services.audio.play(.returnSaved)
                    services.haptics.success()
                    router.replaceTop(with: .tripSummary(tripID))
                }
            }
        }
    }
}

struct ReturnRowCollapsed: View {
    let line: TripLine
    let entry: ReturnEntry?
    let onTap: () -> Void
    @EnvironmentObject private var store: TackleStore

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                GearImage(gear: store.db.gear[line.gearID], width: 74, height: 52, corner: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TripUseCases.lineName(store.db, line)).tbFont(18, .heavy).foregroundColor(.tbText).lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let entry = entry, entry.confirmed {
                        Text(ReturnText.summary(entry, unit: TripUseCases.lineUnit(store.db, line), tracking: line.snapshot?.trackingType ?? .reusable))
                            .tbFont(13, .semibold).foregroundColor(Color(hex: 0x157A5C)).lineLimit(2)
                    } else {
                        Text("Needs review").tbFont(13, .semibold).foregroundColor(Color(hex: 0xE2701B))
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(radius: 16, padding: 7)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

enum ReturnText {
    static func summary(_ e: ReturnEntry, unit: UnitLabel, tracking: TrackingType) -> String {
        var parts: [String] = []
        if e.returnedQty > 0 { parts.append(tracking == .reusable ? "\(e.returnedQty) returned ready" : "\(e.returnedQty) returned") }
        if e.careQty > 0 { parts.append("\(e.careQty) needs care") }
        if e.usedQty > 0 { parts.append("\(e.usedQty) used") }
        if e.lostQty > 0 { parts.append("\(e.lostQty) lost") }
        return parts.joined(separator: " · ")
    }
}

struct ReturnRowExpanded: View {
    let trip: Trip
    let line: TripLine
    let draft: ReturnDraft
    let onCollapse: () -> Void
    let onConfirmed: () -> Void
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices

    private var entry: ReturnEntry {
        draft.entry(for: line.id) ?? ReturnEntry(tripLineID: line.id, returnedQty: 0, careQty: 0, usedQty: 0, lostQty: 0, confirmed: false)
    }

    var body: some View {
        let taken = line.takenQty ?? 0
        let tracking = line.snapshot?.trackingType ?? store.db.gear[line.gearID]?.trackingType ?? .reusable
        let unit = TripUseCases.lineUnit(store.db, line)
        let remaining = taken - entry.resolved
        VStack(spacing: 6) {
            Button(action: onCollapse) {
                HStack(spacing: 12) {
                    GearImage(gear: store.db.gear[line.gearID], width: 80, height: 64, corner: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TripUseCases.lineName(store.db, line)).tbFont(19, .heavy).foregroundColor(.tbText).lineLimit(2)
                        Text("Taken \(unit.format(taken))").tbFont(13).foregroundColor(.tbSecondary)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 15, weight: .bold)).foregroundColor(.tbText)
                        .frame(width: 32, height: 44)
                }
            }
            .buttonStyle(PressableStyle())

            if tracking == .reusable {
                OutcomeRow(title: "Returned ready", subtitle: "In good condition", icon: "checkmark", tint: Color(hex: 0x1E9A6A),
                           background: Color(hex: 0xF2FBF8), value: entry.returnedQty, maxValue: entry.returnedQty + remaining) { set(returned: $0) }
                OutcomeRow(title: "Needs care", subtitle: "Needs cleaning or minor repair", icon: "wrench.fill", tint: .tbCoral,
                           background: Color(hex: 0xFFF3EF), value: entry.careQty, maxValue: entry.careQty + remaining) { set(care: $0) }
            } else {
                OutcomeRow(title: "Returned unused", subtitle: "In good condition", icon: "checkmark", tint: Color(hex: 0x1E9A6A),
                           background: Color(hex: 0xF2FBF8), value: entry.returnedQty, maxValue: entry.returnedQty + remaining) { set(returned: $0) }
                OutcomeRow(title: "Used", subtitle: "Consumed during trip", icon: "drop.fill", tint: Color(hex: 0x1592C7),
                           background: Color(hex: 0xF0F8FC), value: entry.usedQty, maxValue: entry.usedQty + remaining) { set(used: $0) }
            }
            OutcomeRow(title: "Lost", subtitle: tracking == .reusable ? "Not returned from trip" : "Didn't come back", icon: "exclamationmark.triangle.fill",
                       tint: Color(hex: 0x4F6676), background: Color(hex: 0xF3F6F8), value: entry.lostQty, maxValue: entry.lostQty + remaining) { set(lost: $0) }

            if remaining == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: 0x1E9A6A))
                    Text("All \(taken) accounted for").tbFont(13, .bold).foregroundColor(Color(hex: 0x1E9A6A))
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            } else {
                InfoBanner(text: "\(remaining) still need\(remaining == 1 ? "s" : "") an outcome.",
                           detail: "Update the counts so all \(taken) items are accounted for.", kind: .warning)
            }
            if entry.confirmed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(Color(hex: 0x1E9A6A))
                    Text("Confirmed").tbFont(15, .bold).foregroundColor(Color(hex: 0x1E9A6A))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Color(hex: 0xE2F6EE)))
            } else if remaining == 0 {
                Button(action: confirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: 0x17A9BC))
                        Text("Confirm item")
                    }
                }
                .buttonStyle(OutlineButtonStyle(height: 44))
            } else {
                Text("Confirm item")
                    .tbFont(17, .bold)
                    .foregroundColor(Color(hex: 0x9AA9B2))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(Color(hex: 0xD3DCE1)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Account for every item first")
                InfoBanner(text: "Account for every item before finishing.", kind: .warning)
            }
        }
        .tbCard(radius: 18, padding: 8)
    }

    private func set(returned: Int? = nil, care: Int? = nil, used: Int? = nil, lost: Int? = nil) {
        let e = entry
        ui.run {
            try store.perform { db, _ in
                try TripUseCases.updateEntry(&db, tripID: trip.id, lineID: line.id,
                                             returned: returned ?? e.returnedQty, care: care ?? e.careQty,
                                             used: used ?? e.usedQty, lost: lost ?? e.lostQty)
            }
        }
    }

    private func confirm() {
        if ui.run({ try store.perform { db, _ in try TripUseCases.confirmRow(&db, tripID: trip.id, lineID: line.id) } }) {
            services.audio.play(.itemChecked)
            services.haptics.success()
            onConfirmed()
        }
    }
}

struct OutcomeRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let background: Color
    let value: Int
    let maxValue: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).tbFont(14, .bold).foregroundColor(.tbText)
                Text(subtitle).tbFont(11).foregroundColor(.tbSecondary).lineLimit(2).minimumScaleFactor(0.85)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > 0) { onChange(value - 1) }
                Text("\(value)").tbFont(19, .heavy).foregroundColor(.tbText).frame(minWidth: 30)
                stepButton("plus", enabled: value < maxValue) { onChange(value + 1) }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < maxValue { onChange(value + 1) }
            case .decrement: if value > 0 { onChange(value - 1) }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(enabled ? (icon == "plus" ? Color(hex: 0x17A9BC) : Color(hex: 0x6A8494)) : .tbDisabledText)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(icon == "plus" ? Color(hex: 0xDDF5F8) : Color(hex: 0xEDF3F6)))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

// MARK: - Review & confirm

struct ReturnReviewSheet: View {
    let tripID: UUID
    let onFinish: (Bool) -> Void
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @State private var endAt = Date()
    @State private var summaryNote = ""
    @State private var lossNote = ""
    @State private var loaded = false

    var body: some View {
        if let trip = store.db.trips[tripID], let draft = store.db.draft(for: tripID) {
            content(trip, draft)
                .onAppear {
                    guard !loaded else { return }
                    loaded = true
                    endAt = min(draft.endAt, store.now)
                    summaryNote = draft.summaryNote ?? ""
                    lossNote = draft.lossNote ?? ""
                }
        } else {
            Text("This return is no longer available.").padding(30)
        }
    }

    private func content(_ trip: Trip, _ draft: ReturnDraft) -> some View {
        let anyLost = draft.entries.contains { $0.lostQty > 0 }
        let lines = trip.lines.filter { ($0.takenQty ?? 0) > 0 }
        let start = trip.startedAt ?? store.now
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: "Review return", subtitle: "Confirming applies everything at once and closes the trip.") { onFinish(false) }
                ForEach(lines) { line in
                    let e = draft.entry(for: line.id)
                    let gear = store.db.gear[line.gearID]
                    let taken = line.takenQty ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(TripUseCases.lineName(store.db, line)).tbFont(18, .bold).foregroundColor(.tbText)
                            Spacer()
                            if e?.confirmed == true {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: 0x1E9A6A))
                            } else {
                                Text("Needs review").tbFont(14, .semibold).foregroundColor(Color(hex: 0xE2701B))
                            }
                        }
                        if let e = e {
                            Text(ReturnText.summary(e, unit: TripUseCases.lineUnit(store.db, line), tracking: line.snapshot?.trackingType ?? .reusable))
                                .tbFont(15).foregroundColor(.tbSecondary)
                            if let g = gear {
                                Text("Ready \(g.readyQty) → \(g.readyQty + e.returnedQty) · Care \(g.careQty) → \(g.careQty + e.careQty) · Out \(g.outQty) → \(g.outQty - taken)")
                                    .tbFont(13, .medium).foregroundColor(.tbSecondary)
                            }
                        }
                    }
                    .tbCard(radius: 16, padding: 12)
                    .accessibilityElement(children: .combine)
                }
                FieldLabel(text: "End time")
                DatePicker("End time", selection: $endAt, in: start...max(start, store.now), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(.tbTeal)
                FieldLabel(text: "Summary note (optional)")
                TBTextEditor(text: $summaryNote, placeholder: "How did it go?", minHeight: 70, limit: 2000)
                if anyLost {
                    FieldLabel(text: "What happened to the lost items?")
                    TBTextEditor(text: $lossNote, placeholder: "Required when something was lost", minHeight: 70, limit: 1000,
                                 error: TextRules.trimmed(lossNote).isEmpty ? "A note is required for lost items." : nil)
                }
                ForEach(problems(trip), id: \.self) { InfoBanner(text: $0, kind: .warning) }
                Button(action: confirm) { ButtonLabel(title: "Confirm return", icon: "checkmark.circle.fill") }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(!problems(trip).isEmpty)
                Button("Back to items") { saveDetails(); onFinish(false) }.buttonStyle(SoftButtonStyle(height: 50))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.86)
    }

    private func problems(_ trip: Trip) -> [String] {
        var db = store.db
        try? TripUseCases.updateReturnDetails(&db, tripID: tripID, endAt: endAt, summaryNote: summaryNote, lossNote: lossNote)
        return TripUseCases.returnProblems(db, tripID: tripID, now: store.now)
    }

    private func saveDetails() {
        ui.run {
            try store.perform { db, _ in
                try TripUseCases.updateReturnDetails(&db, tripID: tripID, endAt: endAt, summaryNote: summaryNote, lossNote: lossNote)
            }
        }
    }

    private func confirm() {
        do {
            try store.perform { db, now in
                try TripUseCases.updateReturnDetails(&db, tripID: tripID, endAt: endAt, summaryNote: summaryNote, lossNote: lossNote)
                try TripUseCases.confirmReturn(&db, tripID: tripID, now: now)
            }
            onFinish(true)
        } catch {
            ui.show(error, title: "Couldn't confirm")
        }
    }
}
