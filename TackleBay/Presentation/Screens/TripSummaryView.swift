import SwiftUI

struct TripSummaryView: View {
    let tripID: UUID
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        if let trip = store.db.trips[tripID], trip.status == .completed || trip.status == .cancelled {
            screen(trip)
        } else {
            MissingRecordView(title: "This trip summary isn't available")
        }
    }

    private func screen(_ trip: Trip) -> some View {
        let result = store.db.result(for: trip.id)
        let corrections = store.db.movements.values.filter { $0.tripID == trip.id && $0.reason == .countCorrection }
            .sorted { $0.sequence < $1.sequence }
        let anyCare = result?.entries.contains { $0.care > 0 } ?? false
        return HeroScreen(heroHeight: 214, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 210)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 30)
                    .padding(.bottom, 52)
                Image("tb_trip_log").resizable().scaledToFit().frame(width: 96, height: 90)
                    .rotationEffect(.degrees(8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 2)
                    .padding(.bottom, 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        CircleIconButton(systemName: "chevron.left", style: .navy, size: 38, label: "Back") { router.pop() }
                        TackleBayLogo(height: 44)
                        Spacer()
                        Menu {
                            Button { setHidden(trip, !trip.isHidden) } label: {
                                Label(trip.isHidden ? "Show in History" : "Hide from History", systemImage: trip.isHidden ? "eye" : "eye.slash")
                            }
                            if trip.status == .cancelled {
                                Button(role: .destructive) { delete(trip) } label: { Label("Delete", systemImage: "trash") }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 15, weight: .heavy)).foregroundColor(.white)
                                .frame(width: 38, height: 38).background(Circle().fill(Color.tbNavy))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("More actions")
                        CircleIconButton(systemName: "square.and.arrow.up", style: .navy, size: 38, label: "Share summary") { share(trip) }
                    }
                    Spacer(minLength: 0)
                    Text("Trip Summary").tbDisplay(31).foregroundColor(.tbText).shadow(color: .white.opacity(0.7), radius: 6)
                        .padding(.bottom, 88)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                headerCard(trip, result)
                    .padding(.top, -72)
                if trip.status == .completed, let result = result {
                    SectionTitle(text: "Back at the bay", size: 21)
                    ForEach(result.entries, id: \.tripLineID) { entry in
                        ResultRow(entry: entry, tripID: trip.id)
                    }
                    if let loss = result.lossNote { NoteCard(title: "About lost items", text: loss) }
                    if let summary = result.summaryNote { NoteCard(title: "Summary", text: summary) }
                } else {
                    SectionTitle(text: "Cancelled plan", size: 26)
                    Text("This plan never started, so no gear left your stock.").tbFont(17).foregroundColor(.tbSecondary)
                    ForEach(trip.lines) { line in
                        HStack {
                            Text(TripUseCases.lineName(store.db, line)).tbFont(17, .semibold).foregroundColor(.tbText)
                            Spacer()
                            Text("\(line.requiredQty) planned").tbFont(16).foregroundColor(.tbSecondary)
                        }
                        .tbCard(radius: 16, padding: 12)
                    }
                }
                missingSection(trip)
                if !corrections.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Related corrections").tbFont(18, .bold).foregroundColor(.tbText)
                        ForEach(corrections) { m in
                            let delta = m.deltaReady + m.deltaCare
                            Text("\(m.gearNameSnapshot): \(delta >= 0 ? "+" : "−")\(m.unitSnapshot.format(abs(delta))) · \(Fmt.fullDate(m.timestamp))")
                                .tbFont(15).foregroundColor(.tbSecondary)
                        }
                    }
                    .tbCard(radius: 18, padding: 14)
                }
                if anyCare {
                    Button { router.push(.needsCare(tripID: trip.id)) } label: { ButtonLabel(title: "Open care list", chevron: true) }
                        .buttonStyle(OutlineButtonStyle(height: 44, tint: .tbNavy))
                }
                Button { editNote(trip) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image("tb_trip_log").resizable().scaledToFit().frame(width: 52, height: 46).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My note").tbFont(15, .bold).foregroundColor(.tbText)
                            Text(trip.personalNote ?? "Add a personal note to this trip.")
                                .tbFont(13).foregroundColor(trip.personalNote == nil ? .tbSecondary : .tbText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText).padding(.top, 14)
                    }
                    .tbCard(radius: 16, fill: Color(hex: 0xE6F4FA), padding: 10)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { router.push(.tripEditor(.repeatTrip(trip.id))) } label: { ButtonLabel(title: "Repeat trip", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
            }
        }
    }

    private func headerCard(_ trip: Trip, _ result: TripReturnResult?) -> some View {
        HStack(spacing: 12) {
            SeaTile(width: 82, height: 74, sample: trip.isDemo, corner: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.displayName).tbFont(19, .heavy).foregroundColor(.tbText).lineLimit(2)
                iconLine("mappin.circle.fill", trip.displayPlace)
                if let s = trip.startedAt, let e = trip.endedAt {
                    iconLine("clock.fill", "\(Fmt.time(s)) – \(Fmt.time(e)) · \(Fmt.duration(e.timeIntervalSince(s)))")
                    Text(Fmt.fullDate(s)).tbFont(11).foregroundColor(.tbSecondary)
                } else if let c = trip.cancelledAt {
                    iconLine("xmark.circle.fill", "Cancelled \(Fmt.fullDateTime(c))")
                    Text("Planned for \(Fmt.fullDateTime(trip.plannedDepartureAt))").tbFont(11).foregroundColor(.tbSecondary)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .tbCard(radius: 18, padding: 8)
        .frame(maxWidth: 300, alignment: .leading)
    }

    private func iconLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(Color(hex: 0x8FA6B4))
            Text(text).tbFont(13).foregroundColor(.tbSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder private func missingSection(_ trip: Trip) -> some View {
        let missing = trip.status == .completed ? trip.lines.filter { $0.importance == .required && ($0.takenQty ?? 0) < $0.requiredQty } : []
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Left at home").tbFont(15, .bold).foregroundColor(.tbText)
                ForEach(missing) { line in
                    Text("\(TripUseCases.lineName(store.db, line)) — \(line.takenQty ?? 0) of \(line.requiredQty) taken")
                        .tbFont(13).foregroundColor(.tbSecondary)
                }
                if let note = trip.missingItemsNote { Text("“\(note)”").italic().tbFont(13).foregroundColor(.tbSecondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tbCard(radius: 16, fill: Color(hex: 0xFFF8E8), padding: 10)
        }
    }

    // MARK: Actions

    private func editNote(_ trip: Trip) {
        ui.present {
            NoteSheet(title: "My note", placeholder: "Anything to remember about this trip", limit: 2000, initial: trip.personalNote ?? "") { text in
                if ui.run({ try store.perform { db, now in try TripUseCases.setPersonalNote(&db, tripID: trip.id, text: text, now: now) } }) {
                    ui.dismissSheet()
                }
            }
        }
    }

    private func setHidden(_ trip: Trip, _ hidden: Bool) {
        ui.run { try store.perform { db, now in try TripUseCases.setHidden(&db, tripID: trip.id, hidden: hidden, now: now) } }
    }

    private func delete(_ trip: Trip) {
        ui.confirm("Delete \(trip.name)?", message: "This cancelled plan has no stock history.", confirm: "Delete", destructive: true) {
            if ui.run({ try store.perform { db, _ in try TripUseCases.deleteTrip(&db, tripID: trip.id) } }) { router.pop() }
        }
    }

    private func share(_ trip: Trip) {
        ui.present {
            ShareSummarySheet(trip: trip, result: store.db.result(for: trip.id))
        }
    }
}

struct ResultRow: View {
    let entry: ReturnResultEntry
    let tripID: UUID
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router

    var body: some View {
        let gear = store.db.gear[entry.gearID]
        Button { if gear != nil { router.push(.gearDetail(entry.gearID)) } } label: {
            HStack(spacing: 12) {
                GearImage(gear: gear, category: entry.snapshot.category, width: 76, height: 50, corner: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot.name).tbFont(16, .heavy).foregroundColor(.tbText).lineLimit(1)
                    HStack(spacing: 6) {
                        statusIcon
                        Text(statusText).tbFont(13).foregroundColor(.tbText).lineLimit(2)
                    }
                    Text("Taken \(entry.snapshot.unit.format(entry.taken))").tbFont(11).foregroundColor(.tbSecondary)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(radius: 14, padding: 6)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if gear != nil {
                Button { router.push(.adjustStock(entry.gearID, operation: nil, tripID: tripID)) } label: {
                    Label("Correct stock", systemImage: "plusminus.circle")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusIcon: some View {
        if entry.lost > 0 {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundColor(.tbError)
        } else if entry.care > 0 {
            Image(systemName: "wrench.fill").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color(hex: 0xEB5A2E)))
        } else {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.tbTeal))
        }
    }

    private var statusText: String {
        var parts: [String] = []
        let tracking = entry.snapshot.trackingType
        if entry.returned > 0 { parts.append(tracking == .reusable ? "\(entry.returned) returned ready" : "\(entry.returned) returned") }
        if entry.care > 0 { parts.append("\(entry.care) needs care") }
        if entry.used > 0 { parts.append("\(entry.used) used") }
        if entry.lost > 0 { parts.append("\(entry.lost) lost") }
        return parts.joined(separator: " · ")
    }
}

struct ShareSummarySheet: View {
    let trip: Trip
    let result: TripReturnResult?
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var store: TackleStore
    @State private var includeNotes = false
    @State private var sharing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Share summary", subtitle: "Storage places and personal notes are left out unless you include notes.") { ui.dismissSheet() }
            ScrollView {
                Text(text)
                    .tbFont(15, design: .default)
                    .foregroundColor(.tbText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            }
            .frame(maxHeight: 260)
            Toggle("Include notes", isOn: $includeNotes)
                .tbFont(18, .semibold)
                .foregroundColor(.tbText)
                .tint(.tbTeal)
            Button { sharing = true } label: { ButtonLabel(title: "Share", icon: "square.and.arrow.up") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .sheet(isPresented: $sharing) {
            ShareSheet(items: [text])
        }
    }

    private var text: String {
        var lines: [String] = ["\(trip.displayName) — \(trip.displayPlace)"]
        if let s = trip.startedAt, let e = trip.endedAt {
            lines.append("\(Fmt.fullDateTime(s)) – \(Fmt.time(e)) (\(Fmt.duration(e.timeIntervalSince(s))))")
        } else if let c = trip.cancelledAt {
            lines.append("Cancelled \(Fmt.fullDate(c))")
        }
        lines.append("")
        if let result = result {
            for e in result.entries {
                var parts: [String] = []
                if e.returned > 0 { parts.append("\(e.returned) returned") }
                if e.care > 0 { parts.append("\(e.care) needs care") }
                if e.used > 0 { parts.append("\(e.used) used") }
                if e.lost > 0 { parts.append("\(e.lost) lost") }
                lines.append("• \(e.snapshot.name): took \(e.snapshot.unit.format(e.taken)) — \(parts.joined(separator: ", "))")
            }
        }
        if includeNotes {
            if let n = result?.summaryNote { lines.append(""); lines.append("Summary: \(n)") }
            if let n = result?.lossNote { lines.append("Lost items: \(n)") }
            if let n = trip.personalNote { lines.append("My note: \(n)") }
        }
        lines.append("")
        lines.append("Shared from Tackle Bay")
        return lines.joined(separator: "\n")
    }
}
