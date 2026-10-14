import SwiftUI

enum GearStatusFilter: String, CaseIterable, Identifiable {
    case any, ready, care, out, outOfStock
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any status"
        case .ready: return "Ready"
        case .care: return "Needs Care"
        case .out: return "Out on Trip"
        case .outOfStock: return "Out of Stock"
        }
    }

    func matches(_ g: Gear) -> Bool {
        switch self {
        case .any: return true
        case .ready: return g.readyQty > 0
        case .care: return g.careQty > 0
        case .out: return g.outQty > 0
        case .outOfStock: return g.ownedQty == 0
        }
    }
}

enum GearSort: String, CaseIterable, Identifiable {
    case name, recent
    var id: String { rawValue }
    var title: String { self == .name ? "Name" : "Recently Added" }
}

struct GearLibraryView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var search = ""
    @State private var archived = false
    @State private var category: GearCategory?
    @State private var status: GearStatusFilter = .any
    @State private var sort: GearSort = .recent

    private var allGear: [Gear] { Array(store.db.gear.values) }

    private var filtered: [Gear] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return allGear.filter { g in
            g.isArchived == archived
                && (category == nil || g.category == category)
                && status.matches(g)
                && (q.isEmpty || g.name.lowercased().contains(q) || g.storage.lowercased().contains(q))
        }
        .sorted { a, b in
            switch sort {
            case .name:
                let c = a.name.localizedCaseInsensitiveCompare(b.name)
                return c == .orderedSame ? a.id.uuidString < b.id.uuidString : c == .orderedAscending
            case .recent:
                return a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt > b.createdAt
            }
        }
    }

    private var filtersActive: Bool { category != nil || status != .any || !search.isEmpty }


    var body: some View {
        if allGear.isEmpty {
            emptyLibrary
        } else {
            library
        }
    }

    // MARK: Library

    private var library: some View {
        HeroScreen(heroHeight: 96, overlap: 22, contentTopPadding: 12) {
            HStack {
                TackleBayLogo(height: 48)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        } content: {
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    Text("My Gear").tbDisplay(36).foregroundColor(.tbText).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { router.push(.gearEditor(.new)) } label: {
                        ButtonLabel(title: "Add gear", icon: "plus", iconStyle: .navyCircle)
                    }
                    .buttonStyle(GoldButtonStyle(height: 40, compact: true))
                    .fixedSize()
                }
                SearchField(text: $search, placeholder: "Search gear...") { filterMenu }
                TBSegmented(options: [(false, "Active", nil), (true, "Archived", nil)], selection: $archived, height: 38)
                categoryChips
                if status != .any || sort != .recent {
                    activeFilters
                }
                list
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { router.push(.gearEditor(.new)) } label: {
                    ButtonLabel(title: "Add gear", icon: "plus", iconStyle: .navyCircle)
                }
                .buttonStyle(GoldButtonStyle())
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $status) {
                ForEach(GearStatusFilter.allCases) { Text($0.title).tag($0) }
            }
            Picker("Sort", selection: $sort) {
                ForEach(GearSort.allCases) { Text("Sort: \($0.title)").tag($0) }
            }
        } label: {
            Image(systemName: status == .any ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(status == .any ? .tbText : .tbTeal)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Filter and sort")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(title: "All", icon: AnyView(Image(systemName: "square.grid.2x2.fill").font(.system(size: 17, weight: .semibold))),
                           selected: category == nil) { category = nil }
                ForEach(GearCategory.allCases) { c in
                    ChipButton(title: c.title,
                               icon: AnyView(CategoryIcon(category: c, size: 19, color: category == c ? .white : .tbText)),
                               selected: category == c) { category = (category == c ? nil : c) }
                }
            }
            .padding(.horizontal, Metrics.side)
        }
        .padding(.horizontal, -Metrics.side)
    }

    private var activeFilters: some View {
        HStack(spacing: 8) {
            if status != .any {
                MenuPill(icon: "line.3.horizontal.decrease.circle", title: status.title, highlighted: true)
            }
            if sort != .recent {
                MenuPill(icon: "arrow.up.arrow.down", title: sort.title, highlighted: false)
            }
            Spacer(minLength: 0)
            Button("Clear filters") {
                category = nil
                status = .any
                sort = .recent
                search = ""
            }
            .tbFont(14, .semibold)
            .foregroundColor(Color(hex: 0x1366C9))
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder private var list: some View {
        let items = filtered
        if items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: archived ? "archivebox" : "magnifyingglass")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.tbSecondary)
                Text(archived && !filtersActive ? "No archived gear" : "No gear matches")
                    .tbFont(21, .heavy).foregroundColor(.tbText)
                Text(archived && !filtersActive ? "Archived records stay here with their history." : "Try another search or filter.")
                    .tbFont(16).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
                if filtersActive {
                    Button("Clear filters") {
                        category = nil
                        status = .any
                        search = ""
                    }
                    .buttonStyle(OutlineButtonStyle(height: 44))
                    .frame(maxWidth: 220)
                }
            }
            .padding(.vertical, 30)
        } else {
            let sample = items.filter(\.isDemo)
            let own = items.filter { !$0.isDemo }
            VStack(alignment: .leading, spacing: 8) {
                if !own.isEmpty {
                    if !sample.isEmpty { listHeader("Your gear") }
                    ForEach(own) { GearRow(gear: $0) }
                }
                if !sample.isEmpty {
                    listHeader("Sample collection")
                    ForEach(sample) { GearRow(gear: $0) }
                }
            }
        }
    }

    private func listHeader(_ text: String) -> some View {
        Text(text).tbFont(13, .medium).foregroundColor(.tbSecondary).padding(.top, 2)
    }

    // MARK: Empty database

    private var emptyLibrary: some View {
        HeroScreen(heroHeight: 470, heroAlignment: .bottom, overlap: 22, contentTopPadding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                TackleBayLogo(height: 50)
                HStack {
                    Text("My Gear").tbDisplay(38).foregroundColor(.tbText).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { router.push(.gearEditor(.new)) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(.tbText)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(LinearGradient(colors: [.tbGoldTop, .tbGoldBottom], startPoint: .top, endPoint: .bottom)))
                            .overlay(Circle().strokeBorder(Color.tbGoldEdge, lineWidth: 1.2))
                            .shadow(color: Color.tbGoldShadow.opacity(0.35), radius: 6, y: 3)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Add gear")
                }
                SearchField(text: .constant(""), placeholder: "Search gear").disabled(true).opacity(0.85)
                TBSegmented(options: [(false, "Active", nil), (true, "Archived", nil)], selection: .constant(false), height: 38)
                    .disabled(true)
                Spacer(minLength: 0)
                Image("tb_tackle_box")
                    .resizable().scaledToFit()
                    .frame(width: 270, height: 230)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 8)
                    .accessibilityHidden(true)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        } content: {
            EmptyStateBlock(title: "Make room for your tackle", message: "Add the gear you actually own.") {
                EmptyView()
            } actions: {
                Button { router.push(.gearEditor(.new)) } label: { ButtonLabel(title: "Add gear", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
            }
        }
    }
}

struct SearchField<Accessory: View>: View {
    @Binding var text: String
    var placeholder: String
    let accessory: Accessory

    init(text: Binding<String>, placeholder: String, @ViewBuilder accessory: () -> Accessory) {
        _text = text
        self.placeholder = placeholder
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundColor(.tbText)
            TextField(placeholder, text: $text)
                .tbFont(16)
                .foregroundColor(.tbText)
                .disableAutocorrection(true)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundColor(.tbSecondary)
                        .frame(width: 32, height: 40)
                }
                .accessibilityLabel("Clear search")
            }
            accessory
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xE6F4F8)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
    }
}

extension SearchField where Accessory == EmptyView {
    init(text: Binding<String>, placeholder: String) {
        self.init(text: text, placeholder: placeholder) { EmptyView() }
    }
}

struct MenuPill: View {
    let icon: String
    let title: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).tbFont(15, .semibold).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(highlighted ? .white : .tbText)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(Capsule().fill(highlighted ? Color.tbTeal : Color.white))
        .overlay(Capsule().strokeBorder(Color.tbCardBorder, lineWidth: highlighted ? 0 : 1))
    }
}

struct GearRow: View {
    let gear: Gear
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        Button { router.push(.gearDetail(gear.id)) } label: {
            HStack(spacing: 10) {
                GearImage(gear: gear, width: 118, height: 66, corner: 12, fill: true, scenic: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(gear.name).tbFont(17, .heavy).foregroundColor(.tbText).lineLimit(2).multilineTextAlignment(.leading)
                    StockSummaryLine(gear: gear, compact: true)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 11)).foregroundColor(Color(hex: 0x8FA6B4))
                        Text("\(gear.storage) · \(gear.unit.plural)").tbFont(12).foregroundColor(.tbSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(radius: 16, padding: 6)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if gear.isArchived {
                Button { ui.run { try store.perform { db, now in try GearUseCases.restore(&db, gearID: gear.id, now: now) } } } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button { addToKit() } label: { Label("Add to kit", systemImage: "plus.circle") }
                Button { archive() } label: { Label("Archive", systemImage: "archivebox") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the gear record")
    }

    private func archive() {
        ui.run("Can't archive") { try store.perform { db, now in try GearUseCases.archive(&db, gearID: gear.id, now: now) } }
    }

    private func addToKit() {
        ui.present {
            KitPickerSheet(title: "Add to kit", isDemo: gear.isDemo, allowNew: true) { kitID in
                ui.dismissSheet()
                if let kitID = kitID {
                    router.push(.kitEditor(.edit(kitID, addGear: gear.id)))
                } else {
                    router.push(.kitEditor(.new(addGear: gear.id)))
                }
            }
        }
    }
}
