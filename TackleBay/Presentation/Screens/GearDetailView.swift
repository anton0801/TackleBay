import SwiftUI

struct GearDetailView: View {
    let gearID: UUID
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var historyLimit = 20

    var body: some View {
        if let gear = store.db.gear[gearID] {
            content(gear)
        } else {
            MissingRecordView()
        }
    }

    private func content(_ gear: Gear) -> some View {
        HeroScreen(heroHeight: 196, heroImage: heroImageName(gear), overlap: 20, contentTopPadding: 14) {
            ZStack(alignment: .top) {
                heroVisual(gear)
                HeroTopBar {
                    CircleIconButton(systemName: "chevron.left", style: .light, label: "Back") { router.pop() }
                } center: {
                    EmptyView()
                } trailing: {
                    Menu {
                        Button { router.push(.gearEditor(.edit(gear.id))) } label: { Label("Edit", systemImage: "pencil") }
                        if gear.careQty > 0 {
                            Button { router.push(.needsCare(tripID: nil)) } label: { Label("Needs care", systemImage: "wrench") }
                        }
                        if gear.isArchived {
                            Button { restore(gear) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                        } else {
                            Button { archive(gear) } label: { Label("Archive", systemImage: "archivebox") }
                        }
                        Button(role: .destructive) { delete(gear) } label: { Label("Delete record", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(.tbText)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.92)))
                            .shadow(color: Color.tbNavy.opacity(0.18), radius: 6, y: 3)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("More actions")
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                header(gear)
                stockTiles(gear)
                storageCard(gear)
                if let trip = store.db.openTrip, trip.lines.contains(where: { $0.gearID == gear.id && ($0.takenQty ?? 0) > 0 }) {
                    linkedTrip(trip)
                }
                actions(gear)
                activity(gear)
            }
        }
    }

    private func heroImageName(_ gear: Gear) -> String {
        "tb_bay_header"
    }

    @ViewBuilder private func heroVisual(_ gear: Gear) -> some View {
        if let pid = gear.photoID, let ref = store.db.photos[pid], let image = store.photos.image(ref, thumbnail: false) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.top, -60)
                .accessibilityLabel("Photo of \(gear.name)")
        } else if let art = gear.sampleArt {
            ZStack(alignment: .bottomTrailing) {
                Image(art).resizable().scaledToFit()
                    .frame(maxWidth: 290, maxHeight: 190)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                Text("Sample image")
                    .tbFont(11, .semibold)
                    .foregroundColor(.tbText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
                    .padding(.trailing, 14)
                    .padding(.bottom, 30)
            }
            .accessibilityHidden(true)
        } else {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEAF8FB, opacity: 0.94), Color(hex: 0xD3EEF6, opacity: 0.96)], startPoint: .top, endPoint: .bottom)
                CategoryIcon(category: gear.category, size: 86, color: Color(hex: 0x1A6E92))
                    .frame(width: 150, height: 150)
                    .background(Circle().fill(Color.white.opacity(0.8)))
                    .padding(.bottom, Metrics.sheetOverlap)
            }
            .padding(.top, -60)
            .accessibilityHidden(true)
        }
    }

    private func header(_ gear: Gear) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(gear.category.singular.uppercased()).tracking(0.8).tbFont(11, .semibold).foregroundColor(.tbSecondary)
                if gear.isArchived { Badge(text: "Archived", color: .tbSecondary) }
                if gear.isDemo { Badge(text: "Sample", color: Color(hex: 0x1366C9)) }
            }
            Text(gear.name).tbDisplay(30).foregroundColor(.tbText).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let note = gear.note {
                Text(note).tbFont(15).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(gear.trackingType.title) · counted in \(gear.unit.plural)")
                .tbFont(12, .medium).foregroundColor(.tbSecondary)
        }
    }

    private func stockTiles(_ gear: Gear) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                StockTile(value: gear.readyQty, title: "Ready", icon: "briefcase.fill", tint: Color(hex: 0x18A7C9), background: Color(hex: 0xDDF3F8))
                if gear.trackingType == .reusable {
                    StockTile(value: gear.careQty, title: "Needs care", icon: "wrench.fill", tint: .tbCoral, background: .tbCoralSoft)
                }
                StockTile(value: gear.outQty, title: "Out", icon: "case.fill", tint: Color(hex: 0x5E7383), background: Color(hex: 0xE6EDF1))
            }
            Text("\(gear.unit.format(gear.ownedQty)) owned").tbFont(13, .medium).foregroundColor(.tbSecondary)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ready \(gear.readyQty), needs care \(gear.careQty), out \(gear.outQty). \(gear.unit.format(gear.ownedQty)) owned.")
    }

    private func storageCard(_ gear: Gear) -> some View {
        Button { router.push(.gearEditor(.edit(gear.id))) } label: {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.tbWood)
                    .frame(width: 42, height: 42).background(Circle().fill(Color(hex: 0xDDF3F8)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Storage location").tbFont(12, .medium).foregroundColor(.tbSecondary)
                    Text(gear.storage).tbFont(17, .heavy).foregroundColor(.tbText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(radius: 16, padding: 10)
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Edit gear details")
    }

    private func linkedTrip(_ trip: Trip) -> some View {
        Button { router.push(trip.status == .returning ? .returnGear(trip.id) : .activeTrip(trip.id)) } label: {
            HStack(spacing: 12) {
                IconTile(systemName: "clock.fill", tint: .tbBlue, size: 46, circle: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Out on a trip").tbFont(15, .medium).foregroundColor(.tbSecondary)
                    Text(trip.displayName).tbFont(19, .bold).foregroundColor(.tbText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundColor(.tbText)
            }
            .tbCard(padding: 12)
        }
        .buttonStyle(PressableStyle())
    }

    private func actions(_ gear: Gear) -> some View {
        VStack(spacing: 8) {
            if gear.isArchived {
                Button { restore(gear) } label: { ButtonLabel(title: "Restore", icon: "arrow.uturn.backward") }
                    .buttonStyle(GoldButtonStyle())
            } else {
                Button { router.push(.adjustStock(gear.id, operation: nil, tripID: nil)) } label: {
                    ButtonLabel(title: "Adjust stock", chevron: true)
                }
                .buttonStyle(GoldButtonStyle(height: 46))
                Button { addToKit(gear) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "briefcase.fill").foregroundColor(Color(hex: 0x18A7C9))
                        Text("Add to kit")
                    }
                }
                .buttonStyle(OutlineButtonStyle(height: 46))
                if gear.careQty > 0 {
                    Button { router.push(.needsCare(tripID: nil)) } label: { ButtonLabel(title: "Open care list", chevron: true) }
                        .buttonStyle(SoftButtonStyle(height: 44))
                }
            }
        }
    }

    private func activity(_ gear: Gear) -> some View {
        let moves = store.db.movements(for: gear.id)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Activity", size: 18)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(moves.prefix(historyLimit).enumerated()), id: \.element.id) { index, m in
                    MovementRow(movement: m, isLast: index == min(moves.count, historyLimit) - 1)
                }
                if moves.count > historyLimit {
                    Button("Show older activity") { historyLimit += 20 }
                        .tbFont(16, .semibold).foregroundColor(Color(hex: 0x1366C9))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .tbCard(radius: 18, padding: 10)
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func archive(_ gear: Gear) {
        ui.run("Can't archive") { try store.perform { db, now in try GearUseCases.archive(&db, gearID: gear.id, now: now) } }
    }

    private func restore(_ gear: Gear) {
        ui.run { try store.perform { db, now in try GearUseCases.restore(&db, gearID: gear.id, now: now) } }
    }

    private func delete(_ gear: Gear) {
        if let reason = GearUseCases.deleteBlockReason(store.db, gearID: gear.id) {
            ui.alert = AlertItem(title: "Can't delete", message: reason, actions: gear.isArchived ? [AlertAction(title: "OK")] : [
                AlertAction(title: "Cancel", role: .cancel),
                AlertAction(title: "Archive") { archive(gear) }
            ])
            return
        }
        var stock = "Ready \(gear.unit.format(gear.readyQty))"
        if gear.trackingType == .reusable { stock += ", Needs care \(gear.careQty)" }
        ui.confirm("Delete \(gear.name)?", message: "This removes the record and its starting stock (\(stock)). This can't be undone.",
                   confirm: "Delete record", destructive: true) {
            var removed: PhotoRef?
            let ok = ui.run {
                try store.perform { db, _ in
                    if let pid = try GearUseCases.delete(&db, gearID: gear.id) { removed = db.photos[pid] ?? store.db.photos[pid] }
                }
            }
            if ok {
                if let removed = removed { store.photos.remove(removed) }
                router.pop()
            }
        }
    }

    private func addToKit(_ gear: Gear) {
        ui.present {
            KitPickerSheet(title: "Add to kit", isDemo: gear.isDemo, allowNew: true) { kitID in
                ui.dismissSheet()
                router.push(.kitEditor(kitID.map { .edit($0, addGear: gear.id) } ?? .new(addGear: gear.id)))
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).tbFont(13, .bold).foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct StockTile: View {
    let value: Int
    let title: String
    let icon: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 8) {
            Image.symbol(icon, fallback: "briefcase.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(background))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").tbFont(22, .heavy).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).tbFont(11, .medium).foregroundColor(.tbText).lineLimit(2).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xEFF8FB)))
    }
}

struct MovementRow: View {
    let movement: StockMovement
    let isLast: Bool
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router

    var body: some View {
        let trip = movement.tripID.flatMap { store.db.trips[$0] }
        Button {
            if let trip = trip { open(trip) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(iconColor.opacity(0.14)))
                    if !isLast {
                        Rectangle().fill(Color(hex: 0xBFE4EE)).frame(width: 2).frame(minHeight: 16)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(trip)).tbFont(14, .bold).foregroundColor(.tbText).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).tbFont(12).foregroundColor(.tbSecondary)
                    if let note = movement.note {
                        Text(note).italic().tbFont(12).foregroundColor(.tbSecondary).lineLimit(3)
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
                if trip != nil {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.tbSecondary).padding(.top, 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(trip == nil)
        .accessibilityElement(children: .combine)
    }

    private func open(_ trip: Trip) {
        switch trip.status {
        case .active: router.push(.activeTrip(trip.id))
        case .returning: router.push(.returnGear(trip.id))
        case .planned: router.push(.packing(trip.id, applyKit: nil))
        case .completed, .cancelled: router.push(.tripSummary(trip.id))
        }
    }

    private var unit: UnitLabel { movement.unitSnapshot }

    private func title(_ trip: Trip?) -> String {
        let m = movement
        switch m.kind {
        case .added:
            let total = m.deltaReady + m.deltaCare
            return m.deltaCare > 0 ? "Added \(unit.format(total)) · \(m.deltaCare) need care" : "Added \(unit.format(total))"
        case .adjusted:
            let delta = m.deltaReady + m.deltaCare
            return delta >= 0 ? "+\(unit.format(delta)) added" : "−\(unit.format(-delta)) removed"
        case .takenOnTrip:
            return "\(unit.format(m.deltaOut)) taken on \(trip?.displayName ?? "a trip")"
        case .returned:
            var parts: [String] = []
            if m.deltaReady > 0 { parts.append("\(m.deltaReady) ready") }
            if m.deltaCare > 0 { parts.append("\(m.deltaCare) need care") }
            if m.usedQty > 0 { parts.append("\(m.usedQty) used") }
            if m.lostQty > 0 { parts.append("\(m.lostQty) lost") }
            return "Back from \(trip?.displayName ?? "a trip"): \(parts.joined(separator: ", "))"
        case .used: return "\(unit.format(-m.deltaReady - m.deltaCare)) used at home"
        case .lost: return "\(unit.format(-m.deltaReady - m.deltaCare)) lost at home"
        case .sentToCare: return "\(m.deltaCare) sent to care"
        case .markedReady: return "\(m.deltaReady) marked ready"
        }
    }

    private var subtitle: String {
        var s = "\(movement.kind.title) · \(Fmt.relative(movement.timestamp))"
        if let reason = movement.reason { s += " · \(reason.title)" }
        if movement.tripID != nil && movement.reason == .countCorrection { s += " · Related correction" }
        return s
    }

    private var icon: String {
        switch movement.kind {
        case .added: return "plus"
        case .adjusted: return movement.deltaReady + movement.deltaCare >= 0 ? "plus" : "minus"
        case .takenOnTrip: return "arrow.up.right"
        case .returned: return "arrow.down.left"
        case .used: return "drop.fill"
        case .lost: return "exclamationmark.triangle.fill"
        case .sentToCare: return "wrench.fill"
        case .markedReady: return "checkmark"
        }
    }

    private var iconColor: Color {
        switch movement.kind {
        case .added, .adjusted, .markedReady: return Color(hex: 0x14A6B8)
        case .takenOnTrip, .returned: return .tbBlue
        case .used: return Color(hex: 0x6C8494)
        case .lost: return .tbError
        case .sentToCare: return .tbCoral
        }
    }
}
