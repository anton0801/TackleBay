import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var services: AppServices

    private var db: TBDatabase { store.db }
    private var activeGear: [Gear] { db.gear.values.filter { !$0.isArchived } }
    private var isEmpty: Bool { activeGear.isEmpty && TripUseCases.homeTrip(db) == nil }

    var body: some View {
        HeroScreen(heroHeight: isEmpty ? 262 : 232, overlap: 22, contentTopPadding: 14) {
            hero
        } content: {
            VStack(spacing: 12) {
                if isEmpty {
                    emptyCard
                } else {
                    tripCard
                    statsRow
                }
                if db.settings.showBonusOnHome {
                    BonusBanner(empty: isEmpty)
                }
                if !isEmpty { recentSection }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            heroCharacter
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, isEmpty ? 30 : 4)
                .padding(.bottom, 14)
            HStack(alignment: .top) {
                TackleBayLogo(height: 50)
                Spacer()
                CircleIconButton(systemName: "gearshape.fill", style: isEmpty ? .glass : .navy, size: 38, label: "Settings") {
                    router.push(.settings)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            if !isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready for the water?")
                        .tbFont(33, .heavy, style: .largeTitle, max: 44)
                        .foregroundColor(.tbText)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(color: .white.opacity(0.55), radius: 5)
                    Text("Your tackle, together.")
                        .tbFont(16, .semibold)
                        .foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.55), radius: 4)
                }
                .frame(width: 200, alignment: .leading)
                .padding(.leading, 18)
                .padding(.top, 92)
            }
        }
    }

    @ViewBuilder private var heroCharacter: some View {
        if let id = db.settings.selectedCollectibleID, db.ownerships[id] != nil, !isEmpty {
            Button { router.push(.showcase) } label: {
                Image(BonusRules.info(id).assetName).resizable().scaledToFit()
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 6)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(BonusRules.info(id).name) on My Bay. Opens My Showcase")
        } else {
            PelicanKeeper(height: isEmpty ? 250 : 222)
        }
    }

    // MARK: Empty database

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Text("Your bay starts with your gear")
                .tbFont(30, .heavy, style: .title1, max: 42)
                .foregroundColor(.tbText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .accessibilityAddTraits(.isHeader)
            Text("Add what you own. Build your first kit.")
                .tbFont(15, .regular)
                .foregroundColor(.tbText.opacity(0.85))
                .multilineTextAlignment(.center)
            EmptyTackleArt()
                .frame(height: 150)
                .padding(.vertical, 2)
            Button { router.push(.gearEditor(.new)) } label: { ButtonLabel(title: "Add your first gear", chevron: true) }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(.top, 8)
        .tbCard(padding: 12)
    }

    // MARK: Trip card

    @ViewBuilder private var tripCard: some View {
        if let trip = TripUseCases.homeTrip(db) {
            HomeTripCard(trip: trip)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    IconTile(systemName: "calendar", tint: .tbTeal, size: 30, circle: false)
                    Text("NEXT TRIP").tracking(0.8).tbFont(11, .semibold).foregroundColor(.tbSecondary)
                }
                Text("No trip planned").tbFont(21, .heavy).foregroundColor(.tbText)
                Text("Plan a trip, pack what you take and check what comes back.")
                    .tbFont(14).foregroundColor(.tbSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { router.push(.tripEditor(.new(kitID: nil))) } label: { ButtonLabel(title: "New trip", icon: "plus", iconStyle: .navyCircle) }
                    .buttonStyle(GoldButtonStyle(height: 48))
            }
            .tbCard(radius: 20, padding: 14)
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        let readyCount = activeGear.filter { $0.readyQty > 0 }.count
        let careCount = activeGear.filter { $0.careQty > 0 }.count
        return HStack(spacing: 10) {
            Button { router.select(.gear) } label: {
                StatTile(value: activeGear.count, title: "Gear records", subtitle: "\(readyCount) with ready stock",
                         icon: "briefcase.fill", tint: Color(hex: 0x18A7C9), tileColor: Color(hex: 0xDDF3F8))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(activeGear.count) gear records, \(readyCount) with ready stock")
            Button { router.push(.needsCare(tripID: nil)) } label: {
                StatTile(value: careCount, title: "Need care", subtitle: nil,
                         icon: "wrench.fill", tint: Color(hex: 0xF0623C), tileColor: .tbCoralSoft)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(careCount) records need care")
        }
    }

    // MARK: Recently updated

    @ViewBuilder private var recentSection: some View {
        let recent = activeGear.sorted { $0.updatedAt > $1.updatedAt }.prefix(3)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Recently updated", size: 18)
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, gear in
                        Button { router.push(.gearDetail(gear.id)) } label: {
                            HStack(spacing: 12) {
                                GearImage(gear: gear, width: 48, corner: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gear.name).tbFont(15, .bold).foregroundColor(.tbText).lineLimit(2)
                                    StockSummaryLine(gear: gear, compact: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        if index < recent.count - 1 { Divider().background(Color.tbBorder) }
                    }
                }
                .tbCard(radius: 18, padding: 10)
                Button { router.push(.gearEditor(.new)) } label: {
                    ButtonLabel(title: "Add gear", icon: "plus", iconStyle: .navyCircle)
                }
                .buttonStyle(OutlineButtonStyle(height: 46))
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Pieces

struct HomeTripCard: View {
    let trip: Trip
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router

    var body: some View {
        let db = store.db
        let progress = TripUseCases.progress(trip)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        IconTile(systemName: headerIcon, tint: .tbTeal, background: .tbIceTile, size: 30, circle: false)
                        Text(headerLabel).tracking(0.8).tbFont(11, .semibold).foregroundColor(.tbSecondary)
                    }
                    Text(trip.displayName).tbFont(22, .heavy).foregroundColor(.tbText).lineLimit(2).minimumScaleFactor(0.8)
                    detailLine
                }
                Spacer(minLength: 0)
                SeaTile(width: 96, height: 90, sample: trip.isDemo, corner: 14)
            }
            if trip.status == .planned {
                if trip.plannedDepartureAt < store.now {
                    Label("Plan date has passed", systemImage: "exclamationmark.circle.fill")
                        .tbFont(13, .semibold)
                        .foregroundColor(.tbCare)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.tbCareBackground))
                }
                Text(progress.text).tbFont(14, .bold).foregroundColor(.tbText)
                TBProgressBar(fraction: progress.fraction, height: 10)
                    .padding(.trailing, 40)
                if !trip.lines.isEmpty { thumbnails(db) }
                Button { router.push(.packing(trip.id, applyKit: nil)) } label: {
                    ButtonLabel(title: trip.lines.isEmpty ? "Start packing" : "Continue packing", chevron: true)
                }
                .buttonStyle(GoldButtonStyle(height: 48))
            } else if trip.status == .active {
                Text("\(Fmt.items(trip.lines.filter { ($0.takenQty ?? 0) > 0 }.count)) taken with you")
                    .tbFont(14, .bold).foregroundColor(.tbText)
                Button { router.push(.activeTrip(trip.id)) } label: { ButtonLabel(title: "Continue trip", chevron: true) }
                    .buttonStyle(GoldButtonStyle(height: 48))
            } else if trip.status == .returning {
                Text("Your return check is saved as a draft.").tbFont(14, .bold).foregroundColor(.tbText)
                Button { router.push(.returnGear(trip.id)) } label: { ButtonLabel(title: "Resume return", chevron: true) }
                    .buttonStyle(GoldButtonStyle(height: 48))
            }
        }
        .tbCard(radius: 20, padding: 12)
    }

    private var headerLabel: String {
        switch trip.status {
        case .active: return "ON THE WATER"
        case .returning: return "RETURNING"
        default: return "NEXT TRIP"
        }
    }

    private var headerIcon: String {
        switch trip.status {
        case .active, .returning: return "clock.fill"
        default: return "calendar"
        }
    }

    @ViewBuilder private var detailLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            if trip.status == .planned {
                iconText("mappin.circle.fill", Fmt.dayTime(trip.plannedDepartureAt, now: store.now))
                iconText("water.waves", trip.displayPlace)
            } else if let started = trip.startedAt {
                iconText("mappin.circle.fill", trip.displayPlace)
                TimelineView(.periodic(from: Date(), by: 30)) { _ in
                    iconText("clock", "Started \(Fmt.time(started)) · \(Fmt.duration(max(0, store.now.timeIntervalSince(started))))")
                }
            }
        }
    }

    private func iconText(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image.symbol(icon, fallback: "mappin.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: 0x8FA6B4)).frame(width: 16)
            Text(text).tbFont(14).foregroundColor(.tbSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func thumbnails(_ db: TBDatabase) -> some View {
        HStack(spacing: 8) {
            ForEach(trip.lines.prefix(6)) { line in
                let done = line.packedQty >= line.requiredQty
                ThumbTile(gear: db.gear[line.gearID], done: done)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

/// 44 pt thumbnail with packed check badge; unpacked items are dimmed.
struct ThumbTile: View {
    let gear: Gear?
    let done: Bool
    var size: CGFloat = 44

    var body: some View {
        GearImage(gear: gear, width: size, corner: 10)
            .saturation(done ? 1 : 0)
            .opacity(done ? 1 : 0.55)
            .overlay(alignment: .bottomTrailing) {
                if done { CheckBadge(size: 18).offset(x: 4, y: 4) }
            }
    }
}

struct StatTile: View {
    let value: Int
    let title: String
    var subtitle: String?
    let icon: String
    let tint: Color
    let tileColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tileColor))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").tbFont(24, .heavy).foregroundColor(.tbText)
                Text(title).tbFont(13, .medium).foregroundColor(.tbSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
        }
        .tbCard(radius: 18, padding: 10)
    }
}

/// Dark navy Bay Bonus banner with the reel symbol over the bay.
struct BonusBanner: View {
    var empty = false
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router

    var body: some View {
        let db = store.db
        VStack(spacing: 8) {
            Button { router.push(.bonus) } label: {
                ZStack(alignment: .leading) {
                    FillImage(name: "tb_bay_header", height: 76, alignment: .bottom)
                        .overlay(LinearGradient(colors: [Color.tbNavy.opacity(0.95), Color.tbNavy.opacity(0.75), Color.tbNavy.opacity(0.2)],
                                                startPoint: .leading, endPoint: .trailing))
                    HStack(spacing: 10) {
                        Image("tb_symbol_reel").resizable().scaledToFit().frame(width: 104, height: 92)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                            .padding(.leading, -18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(empty ? "Explore Bay Bonus" : "Bay Bonus").tbFont(21, .heavy).foregroundColor(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(subtitle(db)).tbFont(15, .bold).foregroundColor(Color(hex: 0xFFD54F))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(hex: 0x04284A)))
                            .padding(.trailing, 12)
                    }
                }
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.tbNavy.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Bay Bonus. \(subtitle(db))")
            if !empty {
                Button { router.push(.showcase) } label: {
                    HStack(spacing: 6) {
                        Image("tb_parts_token").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                        Text("My Showcase · \(Fmt.parts(db.wallet.parts)) · Built \(db.ownerships.count) of 4").tbFont(13, .semibold)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.tbText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().strokeBorder(Color.tbCardBorder, lineWidth: 1))
                    .frame(minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func subtitle(_ db: TBDatabase) -> String {
        if BonusUseCases.isCollectionComplete(db) { return "Collection complete" }
        if BonusUseCases.pendingReceipt(db) != nil { return "Your result is waiting" }
        if db.wallet.tickets > 0 { return db.wallet.tickets == 1 ? "1 free ticket" : "\(db.wallet.tickets) free tickets" }
        switch BonusUseCases.claimState(db, now: store.now) {
        case .available: return empty ? "Free virtual rewards" : "Free ticket ready"
        case .cooldown(let until): return "Next ticket in \(Fmt.duration(until.timeIntervalSince(store.now)))"
        default: return "Free virtual rewards"
        }
    }
}

/// Composition for the empty home: tackle box with a rod, spool and pliers around it.
struct EmptyTackleArt: View {
    var body: some View {
        ZStack {
            SparkLines().stroke(Color(hex: 0x3FD3E2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 280, height: 150)
            Image("tb_gear_rod").resizable().scaledToFit().frame(width: 130).rotationEffect(.degrees(-8)).offset(x: -92, y: 6)
            Image("tb_tackle_box").resizable().scaledToFit().frame(width: 170)
            Image("tb_gear_spool").resizable().scaledToFit().frame(width: 62).offset(x: 104, y: 22)
            Image("tb_gear_pliers").resizable().scaledToFit().frame(width: 92).offset(x: 78, y: 58)
        }
        .accessibilityHidden(true)
    }
}

struct SparkLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.18))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.32))
        p.move(to: CGPoint(x: r.minX + r.width * 0.04, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.47))
        p.move(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.minY + r.height * 0.18))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY + r.height * 0.32))
        p.move(to: CGPoint(x: r.maxX - r.width * 0.04, y: r.minY + r.height * 0.36))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.16, y: r.minY + r.height * 0.43))
        return p
    }
}

/// "✓ Ready 2 · 🔧 Care 1 · ◉ Out 0" — every non-zero state shown, colour always paired with text and symbol.
struct StockSummaryLine: View {
    let gear: Gear
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if gear.ownedQty == 0 {
                status("xmark.circle.fill", "Out of stock", .tbError)
            } else {
                if gear.readyQty > 0 || (gear.careQty == 0 && gear.outQty == 0) {
                    status("checkmark.circle.fill", "Ready \(gear.readyQty)", .tbReady)
                }
                if gear.careQty > 0 {
                    status("wrench.fill", "Care \(gear.careQty)", .tbCoral, textColor: .tbCare)
                }
                if gear.outQty > 0 || (!compact && gear.trackingType == .reusable && gear.careQty == 0) {
                    status("circle.inset.filled", "Out \(gear.outQty)", Color(hex: 0x6C8494))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ready \(gear.unit.format(gear.readyQty)), Needs care \(gear.careQty), Out \(gear.outQty)")
    }

    private func status(_ icon: String, _ text: String, _ color: Color, textColor: Color = .tbText) -> some View {
        HStack(spacing: 4) {
            Image.symbol(icon, fallback: "circle.fill").font(.system(size: compact ? 12 : 13, weight: .semibold)).foregroundColor(color)
            Text(text).tbFont(compact ? 13 : 13, .medium).foregroundColor(textColor).lineLimit(1)
        }
    }
}
