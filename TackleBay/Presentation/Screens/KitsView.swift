import SwiftUI

struct KitsView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var search = ""
    @State private var archived = false

    private var kits: [Kit] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return store.db.kits.values
            .filter { $0.isArchived == archived && (q.isEmpty || $0.name.lowercased().contains(q)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasArchived: Bool { store.db.kits.values.contains { $0.isArchived } }

    var body: some View {
        HeroScreen(heroHeight: 168, overlap: 20, contentTopPadding: 14) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 200, mirrored: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, -30)
                    .padding(.bottom, 14)
                Image("tb_tackle_box").resizable().scaledToFit().frame(width: 112)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 4)
                    .padding(.bottom, 10)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    TackleBayLogo(height: 46)
                    Text("Your tackle,\nalways ready.")
                        .tbFont(14, .bold)
                        .foregroundColor(.tbText)
                        .multilineTextAlignment(.center)
                        .shadow(color: .white.opacity(0.8), radius: 4)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 70)
                .padding(.top, 0)
                Text("My Kits").font(.system(size: 1)).opacity(0).accessibilityAddTraits(.isHeader)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                SearchField(text: $search, placeholder: "Search your kits...")
                if hasArchived || archived {
                    TBSegmented(options: [(false, "Active", nil), (true, "Archived", nil)], selection: $archived, height: 38)
                }
                list
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { router.push(.kitEditor(.new(addGear: nil))) } label: {
                    ButtonLabel(title: "New kit", icon: "plus", iconStyle: .navyCircle)
                }
                .buttonStyle(GoldButtonStyle())
            }
        }
    }

    @ViewBuilder private var list: some View {
        let items = kits
        if store.db.kits.isEmpty {
            VStack(spacing: 10) {
                Image("tb_tackle_box").resizable().scaledToFit().frame(width: 136, height: 120).accessibilityHidden(true)
                Text("Save the setup you use most").tbFont(22, .heavy).foregroundColor(.tbText).multilineTextAlignment(.center)
                Text("A kit is a reusable list of your own gear: shore spinning, float fishing, a boat day or your own mix.")
                    .tbFont(14).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if items.isEmpty {
            Text(search.isEmpty ? (archived ? "No archived kits." : "No active kits.") : "No kits match.")
                .tbFont(16, .semibold).foregroundColor(.tbSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            let sample = items.filter(\.isDemo)
            let own = items.filter { !$0.isDemo }
            if !own.isEmpty {
                if !sample.isEmpty { Text("Your kits").tbFont(13, .medium).foregroundColor(.tbSecondary) }
                ForEach(own) { KitCard(kit: $0) }
            }
            if !sample.isEmpty {
                Text("Sample collection").tbFont(13, .medium).foregroundColor(.tbSecondary)
                ForEach(sample) { KitCard(kit: $0) }
            }
        }
    }
}

struct KitCard: View {
    let kit: Kit
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let db = store.db
        let unavailable = KitUseCases.unavailableCount(db, kit: kit)
        let short = KitUseCases.shortLines(db, kit: kit).count
        Button { router.push(.kitEditor(.edit(kit.id, addGear: nil))) } label: {
            HStack(alignment: .center, spacing: 10) {
                coverTile(db)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kit.name).tbFont(17, .heavy).foregroundColor(.tbText).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(Fmt.items(kit.lines.count)).foregroundColor(.tbSecondary)
                        Text("·").foregroundColor(.tbSecondary)
                        if unavailable > 0 {
                            Text("\(unavailable) unavailable").foregroundColor(Color(hex: 0xE25A1C)).fontWeight(.semibold)
                        } else if short > 0 {
                            Text("\(short) \(short == 1 ? "needs" : "need") attention").foregroundColor(Color(hex: 0xE25A1C)).fontWeight(.semibold)
                        } else {
                            Text("All available").foregroundColor(.tbSecondary)
                        }
                    }
                    .tbFont(13)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    HStack(spacing: 6) {
                        ForEach(kit.lines.prefix(4)) { line in
                            GearImage(gear: db.gear[line.gearID], width: 40, height: 40, corner: 9)
                                .opacity(KitUseCases.isAvailable(db, gearID: line.gearID) ? 1 : 0.4)
                        }
                    }
                    .padding(.top, 2)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(radius: 18, padding: 8)
        }
        .buttonStyle(PressableStyle())
        .contextMenu { KitActions(kit: kit) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kit.name), \(Fmt.items(kit.lines.count)), \(previewNames(db))")
    }

    @ViewBuilder private func coverTile(_ db: TBDatabase) -> some View {
        if kit.isDemo {
            Image("tb_harbor_sample").resizable().scaledToFill()
                .frame(width: 92, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
        } else if let first = kit.lines.compactMap({ db.gear[$0.gearID] }).first(where: { $0.photoID != nil }) {
            GearImage(gear: first, width: 92, height: 88, corner: 14, fill: true)
        } else {
            SeaTile(width: 92, height: 88, corner: 14)
        }
    }

    private func previewNames(_ db: TBDatabase) -> String {
        kit.lines.prefix(3).map { db.gear[$0.gearID]?.name ?? "Unavailable" }.joined(separator: ", ")
    }
}

/// Shared kit actions (context menu and view mode).
struct KitActions: View {
    let kit: Kit
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        if !kit.isArchived {
            Button { useForTrip() } label: { Label("Use for trip", systemImage: "calendar.badge.plus") }
        }
        Button { router.push(.kitEditor(.duplicate(kit.id))) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if kit.isArchived {
            Button { setArchived(false) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
        } else {
            Button { setArchived(true) } label: { Label("Archive", systemImage: "archivebox") }
        }
        Button(role: .destructive) { delete() } label: { Label("Delete kit", systemImage: "trash") }
    }

    func useForTrip() {
        ui.present {
            TripPickerSheet(title: "Use for trip", isDemo: kit.isDemo) { tripID in
                ui.dismissSheet()
                router.push(.packing(tripID, applyKit: kit.id))
            }
        }
    }

    func setArchived(_ value: Bool) {
        ui.run { try store.perform { db, now in try KitUseCases.setArchived(&db, kitID: kit.id, archived: value, now: now) } }
    }

    func delete() {
        ui.confirm("Delete \(kit.name)?", message: "Your gear, trips and packing lists stay as they are.", confirm: "Delete kit", destructive: true) {
            if ui.run({ try store.perform { db, _ in try KitUseCases.delete(&db, kitID: kit.id) } }) {
                if case .kitEditor = router.topRoute { router.pop() }
            }
        }
    }
}
