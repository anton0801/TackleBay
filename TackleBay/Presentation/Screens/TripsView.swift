import SwiftUI

enum TripsTab: Hashable { case planned, current, history }

struct TripsView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var tab: TripsTab = .planned
    @State private var search = ""
    @State private var showHidden = false

    private func matches(_ t: Trip) -> Bool {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty || t.displayName.lowercased().contains(q) || t.displayPlace.lowercased().contains(q)
    }

    var body: some View {
        HeroScreen(heroHeight: 150, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 220)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, -16)
                    .padding(.bottom, 14)
                TackleBayLogo(height: 52)
                    .padding(.leading, 16)
                    .padding(.top, 2)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                TBSegmented(options: [(TripsTab.planned, "Planned", "calendar"), (TripsTab.current, "Current", "water.waves"),
                                      (TripsTab.history, "History", "clock")], selection: $tab, height: 42)
                if showSearch {
                    SearchField(text: $search, placeholder: "Search trips or places")
                }
                switch tab {
                case .planned: planned
                case .current: current
                case .history: history
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { router.push(.tripEditor(.new(kitID: nil))) } label: {
                    ButtonLabel(title: "New trip", icon: "plus", iconStyle: .navyCircle)
                }
                .buttonStyle(GoldButtonStyle())
            }
        }
        .onAppear { if store.db.openTrip != nil && tab == .planned && plannedTrips.isEmpty { tab = .current } }
    }

    /// Search appears once a tab has enough trips to need it (or while a query is active).
    private var showSearch: Bool {
        if !search.isEmpty { return true }
        let trips = store.db.trips.values
        switch tab {
        case .planned: return trips.filter { $0.status == .planned }.count > 3
        case .current: return false
        case .history: return trips.filter { $0.status == .completed || $0.status == .cancelled }.count > 3
        }
    }

    private var plannedTrips: [Trip] {
        store.db.trips.values.filter { $0.status == .planned && matches($0) }
            .sorted { ($0.plannedDepartureAt, $0.id.uuidString) < ($1.plannedDepartureAt, $1.id.uuidString) }
    }

    // MARK: Planned

    @ViewBuilder private var planned: some View {
        let trips = plannedTrips
        if trips.isEmpty {
            EmptyTripsBlock(image: "tb_tackle_box", size: CGSize(width: 136, height: 120),
                            title: search.isEmpty ? "No planned trips" : "No trips match",
                            message: "Plan a trip, then pack from your kits or single items.")
        } else {
            let now = store.now
            let calendar = Calendar.current
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
            let passed = trips.filter { $0.plannedDepartureAt < now }
            let week = trips.filter { $0.plannedDepartureAt >= now && $0.plannedDepartureAt < weekEnd }
            let later = trips.filter { $0.plannedDepartureAt >= weekEnd }
            if !passed.isEmpty { group("Plan date has passed", passed) }
            if !week.isEmpty { group("This week", week) }
            if !later.isEmpty { group("Later", later) }
        }
    }

    private func group(_ title: String, _ trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title, size: 21)
            ForEach(trips) { PlannedTripCard(trip: $0) }
        }
    }

    // MARK: Current

    @ViewBuilder private var current: some View {
        if let trip = store.db.openTrip, matches(trip) {
            CurrentTripCard(trip: trip)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "figure.wave")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(Color(hex: 0x18A7C9))
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(Color.tbIceTile))
                    .accessibilityHidden(true)
                Text("Nothing on the water right now").tbFont(23, .heavy).foregroundColor(.tbText).multilineTextAlignment(.center)
                Text("Start a planned trip from its packing list. Only one trip can be on at a time.")
                    .tbFont(16).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
    }

    // MARK: History

    @ViewBuilder private var history: some View {
        let finished = store.db.trips.values.filter { ($0.status == .completed || $0.status == .cancelled) && matches($0) }
        let hiddenCount = finished.filter(\.isHidden).count
        let visible = finished.filter { showHidden || !$0.isHidden }
            .sorted { a, b in
                let da = a.endedAt ?? a.cancelledAt ?? a.updatedAt
                let dbb = b.endedAt ?? b.cancelledAt ?? b.updatedAt
                return da == dbb ? a.id.uuidString > b.id.uuidString : da > dbb
            }
        if hiddenCount > 0 {
            Button(showHidden ? "Hide hidden trips" : "Show hidden (\(hiddenCount))") { showHidden.toggle() }
                .tbFont(16, .semibold).foregroundColor(Color(hex: 0x1366C9)).frame(minHeight: 44)
        }
        if visible.isEmpty {
            EmptyTripsBlock(image: "tb_trip_log", size: CGSize(width: 136, height: 116),
                            title: search.isEmpty ? "No finished trips yet" : "No trips match",
                            message: "Completed returns and cancelled plans appear here with what was used, lost or needs care.")
        } else {
            ForEach(visible) { HistoryTripCard(trip: $0) }
        }
    }
}

struct EmptyTripsBlock: View {
    let image: String
    let size: CGSize
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(image).resizable().scaledToFit().frame(width: size.width, height: size.height).accessibilityHidden(true)
            Text(title).tbFont(24, .heavy).foregroundColor(.tbText).multilineTextAlignment(.center)
            Text(message).tbFont(16).foregroundColor(.tbSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct PlannedTripCard: View {
    let trip: Trip
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let db = store.db
        let progress = TripUseCases.progress(trip)
        let anyPacked = trip.lines.contains { $0.packedQty > 0 }
        Button { router.push(.packing(trip.id, applyKit: nil)) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    SeaTile(width: 120, height: 112, sample: trip.isDemo, corner: 14)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top, spacing: 4) {
                            Text(trip.name).tbFont(18, .heavy).foregroundColor(.tbText).lineLimit(2).multilineTextAlignment(.leading)
                                .layoutPriority(1)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(.tbText)
                                .frame(width: 30, height: 30).background(Circle().fill(Color(hex: 0xEDF6FA)))
                        }
                        iconLine("calendar", Fmt.dayTime(trip.plannedDepartureAt, now: store.now),
                                 color: trip.plannedDepartureAt < store.now ? .tbCare : .tbSecondary)
                        iconLine("mappin.circle.fill", trip.place)
                        if trip.lines.isEmpty || !anyPacked {
                            iconLine("briefcase.fill", trip.lines.isEmpty ? "Empty packing list" : "Not packed")
                        } else {
                            Text(progress.text).tbFont(13, .bold).foregroundColor(.tbText).padding(.top, 2)
                            TBProgressBar(fraction: progress.fraction, height: 9)
                        }
                    }
                }
                if !trip.lines.isEmpty && anyPacked {
                    HStack(spacing: 8) {
                        ForEach(trip.lines.prefix(6)) { line in
                            ThumbTile(gear: db.gear[line.gearID], done: line.packedQty >= line.requiredQty, size: 42)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityHidden(true)
                }
            }
            .tbCard(radius: 18, padding: 10)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button { router.push(.tripEditor(.edit(trip.id))) } label: { Label("Edit plan", systemImage: "pencil") }
            Button { cancelPlan() } label: { Label("Cancel plan", systemImage: "xmark.circle") }
            if TripUseCases.deleteBlockReason(store.db, tripID: trip.id) == nil {
                Button(role: .destructive) { deletePlan() } label: { Label("Delete plan", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func iconLine(_ icon: String, _ text: String, color: Color = .tbSecondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(Color(hex: 0x8FA6B4)).frame(width: 16)
            Text(text).tbFont(14).foregroundColor(color).lineLimit(1)
        }
    }

    private func cancelPlan() {
        ui.confirm("Cancel \(trip.name)?", message: "The plan moves to History as cancelled. Your stock doesn't change.", confirm: "Cancel plan",
                   destructive: true, cancel: "Keep plan") {
            ui.run { try store.perform { db, now in try TripUseCases.cancelPlan(&db, tripID: trip.id, now: now) } }
        }
    }

    private func deletePlan() {
        ui.confirm("Delete \(trip.name)?", message: "The plan and its packing list are removed. Your stock doesn't change.", confirm: "Delete plan",
                   destructive: true) {
            ui.run { try store.perform { db, _ in try TripUseCases.deleteTrip(&db, tripID: trip.id) } }
        }
    }
}

struct CurrentTripCard: View {
    let trip: Trip
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router

    var body: some View {
        Button { router.push(trip.status == .returning ? .returnGear(trip.id) : .activeTrip(trip.id)) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    SeaTile(width: 110, height: 110, sample: trip.isDemo)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.status == .returning ? "RETURNING" : "ON THE WATER").tracking(0.8).tbFont(14, .semibold).foregroundColor(.tbTeal)
                        Text(trip.displayName).tbFont(23, .heavy).foregroundColor(.tbText).lineLimit(2)
                        Text(trip.displayPlace).tbFont(17).foregroundColor(.tbSecondary)
                        if let started = trip.startedAt {
                            TimelineView(.periodic(from: Date(), by: 30)) { _ in
                                Text("Started \(Fmt.time(started)) · \(Fmt.duration(max(0, store.now.timeIntervalSince(started))))")
                                    .tbFont(16, .medium).foregroundColor(.tbText)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(trip.status == .returning ? "Resume return" : "Open trip")
                    .tbFont(18, .bold).foregroundColor(.tbText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(LinearGradient(colors: [.tbGoldTop, .tbGoldBottom], startPoint: .top, endPoint: .bottom)))
            }
            .tbCard(radius: 24, padding: 12)
        }
        .buttonStyle(PressableStyle())
    }
}

struct HistoryTripCard: View {
    let trip: Trip
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let result = store.db.result(for: trip.id)
        Button { router.push(.tripSummary(trip.id)) } label: {
            HStack(spacing: 14) {
                Image(trip.status == .completed ? "tb_trip_log" : "tb_tackle_box").resizable().scaledToFit()
                    .frame(width: 64, height: 56)
                    .opacity(trip.status == .completed ? 1 : 0.6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(trip.displayName).tbFont(20, .heavy).foregroundColor(.tbText).lineLimit(2)
                        if trip.isHidden { Badge(text: "Hidden", color: .tbSecondary) }
                    }
                    Text(dateLine).tbFont(15).foregroundColor(.tbSecondary)
                    if let result = result {
                        Text(consequences(result)).tbFont(15, .semibold).foregroundColor(.tbText).lineLimit(2)
                    } else if trip.status == .cancelled {
                        Text("Cancelled · stock unchanged").tbFont(15, .semibold).foregroundColor(.tbSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(radius: 20, padding: 12)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button { router.push(.tripEditor(.repeatTrip(trip.id))) } label: { Label("Repeat trip", systemImage: "repeat") }
            Button {
                ui.run { try store.perform { db, now in try TripUseCases.setHidden(&db, tripID: trip.id, hidden: !trip.isHidden, now: now) } }
            } label: { Label(trip.isHidden ? "Show in History" : "Hide from History", systemImage: trip.isHidden ? "eye" : "eye.slash") }
            if trip.status == .cancelled {
                Button(role: .destructive) {
                    ui.confirm("Delete \(trip.name)?", message: "This cancelled plan has no stock history.", confirm: "Delete", destructive: true) {
                        ui.run { try store.perform { db, _ in try TripUseCases.deleteTrip(&db, tripID: trip.id) } }
                    }
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dateLine: String {
        if trip.status == .cancelled, let c = trip.cancelledAt { return "Cancelled \(Fmt.fullDate(c)) · \(trip.displayPlace)" }
        if let s = trip.startedAt, let e = trip.endedAt { return "\(Fmt.fullDate(s)) · \(Fmt.duration(e.timeIntervalSince(s))) · \(trip.displayPlace)" }
        return trip.displayPlace
    }

    /// Counts of records with each outcome — units of different records are never added together.
    private func consequences(_ r: TripReturnResult) -> String {
        let used = r.entries.filter { $0.used > 0 }.count
        let lost = r.entries.filter { $0.lost > 0 }.count
        let care = r.entries.filter { $0.care > 0 }.count
        var parts: [String] = []
        if used > 0 { parts.append("\(used) used") }
        if care > 0 { parts.append("\(care) needs care") }
        if lost > 0 { parts.append("\(lost) lost") }
        return parts.isEmpty ? "Everything returned ready" : parts.joined(separator: " · ")
    }
}
