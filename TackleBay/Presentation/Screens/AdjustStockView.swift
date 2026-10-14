import SwiftUI

struct AdjustStockView: View {
    let gearID: UUID
    let initialOperation: AdjustOperation?
    let tripID: UUID?
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var operation: AdjustOperation = .addStock
    @State private var source: StockSource = .ready
    @State private var reason: StockReason = .purchase
    @State private var quantity: Int? = 1
    @State private var note = ""
    @State private var expectedRevision: Int64 = -1
    @State private var operationID = UUID()
    @State private var started = false

    var body: some View {
        if let gear = store.db.gear[gearID] {
            screen(gear)
                .onAppear { start(gear) }
        } else {
            MissingRecordView()
        }
    }

    private func start(_ gear: Gear) {
        guard !started else { return }
        started = true
        expectedRevision = gear.stockRevision
        let op = initialOperation ?? (gear.careQty > 0 && gear.trackingType == .reusable ? .markReady : .addStock)
        select(op, gear: gear)
        if tripID != nil { reason = .countCorrection }
        // Remove Damaged Stock from Needs Care opens with Source = Care.
        if initialOperation == .removeStock && gear.careQty > 0 {
            source = .care
            reason = .damaged
        }
    }

    private func select(_ op: AdjustOperation, gear: Gear) {
        operation = op
        if !op.reasons.contains(reason) || tripID == nil { reason = op.reasons[0] }
        if op == .removeStock { source = gear.readyQty > 0 || gear.trackingType == .consumable ? .ready : .care }
    }

    private func screen(_ gear: Gear) -> some View {
        HeroScreen(heroHeight: 186, overlap: 20, contentTopPadding: 14) {
            ZStack(alignment: .top) {
                heroArt(gear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                HeroTopBar {
                    CircleIconButton(systemName: "chevron.left", style: .light, label: "Cancel") { router.pop() }
                } center: {
                    Text("Adjust Stock").tbFont(23, .heavy).foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.6), radius: 5)
                        .accessibilityAddTraits(.isHeader)
                } trailing: {
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, -6)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text(gear.name).tbDisplay(27).foregroundColor(.tbText).fixedSize(horizontal: false, vertical: true)
                operationGrid(gear)
                if operation == .removeStock && gear.trackingType == .reusable {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(text: "Remove from")
                        TBSegmented(options: [(StockSource.ready, "Ready \(gear.readyQty)", nil), (StockSource.care, "Needs care \(gear.careQty)", nil)],
                                    selection: $source, height: 38)
                    }
                }
                reasonPicker
                quantitySection(gear)
                previewSection(gear)
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Optional note")
                    TBTextField(label: nil, text: $note, placeholder: "Cleaned and checked", limit: 1000)
                }
                if tripID != nil {
                    InfoBanner(text: "This correction is linked to the trip. The trip result stays as it was.", kind: .info)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { confirm(gear) } label: { ButtonLabel(title: "Confirm adjustment", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(previewResult(gear) == nil)
            }
        }
    }

    @ViewBuilder private func heroArt(_ gear: Gear) -> some View {
        if let pid = gear.photoID, let ref = store.db.photos[pid], let image = store.photos.image(ref, thumbnail: false) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 200, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        } else if let art = gear.sampleArt {
            Image(art).resizable().scaledToFit().frame(width: 220, height: 120)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
        } else {
            CategoryIcon(category: gear.category, size: 60, color: Color(hex: 0x1A6E92))
                .frame(width: 104, height: 104)
                .background(Circle().fill(Color.white.opacity(0.85)))
        }
    }

    private func operationGrid(_ gear: Gear) -> some View {
        let ops = AdjustOperation.allCases
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
            ForEach(ops) { op in
                let disabled = gear.trackingType == .consumable && op.usesCare
                let selected = op == operation
                Button { select(op, gear: gear) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(op))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(selected ? Color.tbTeal : iconColor(op)))
                        Text(op.title).tbFont(14, selected ? .bold : .medium).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Color(hex: 0xE3F7FA) : .white))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.tbTeal : Color.tbCardBorder, lineWidth: selected ? 1.6 : 1))
                    .shadow(color: Color(hex: 0x0B4F6C).opacity(0.05), radius: 6, y: 3)
                }
                .buttonStyle(PressableStyle())
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(disabled ? "Consumable items don't use Needs Care" : "")
            }
        }
    }

    private func icon(_ op: AdjustOperation) -> String {
        switch op {
        case .addStock: return "plus"
        case .removeStock: return "minus"
        case .sendToCare: return "wrench.fill"
        case .markReady: return "checkmark"
        }
    }

    private func iconColor(_ op: AdjustOperation) -> Color {
        switch op {
        case .addStock: return Color(hex: 0x16A6B8)
        case .removeStock: return Color(hex: 0xF0623C)
        case .sendToCare: return Color(hex: 0x6E8494)
        case .markReady: return .tbReady
        }
    }

    private var reasonPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(text: "Reason")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(operation.reasons) { r in
                        ChipButton(title: r.title, selected: r == reason) { reason = r }
                    }
                }
                .padding(.horizontal, Metrics.side)
            }
            .padding(.horizontal, -Metrics.side)
        }
    }

    private func available(_ gear: Gear) -> Int {
        switch operation {
        case .addStock: return StockRules.maxQuantity - gear.ownedQty
        case .removeStock: return source == .ready ? gear.readyQty : gear.careQty
        case .sendToCare: return gear.readyQty
        case .markReady: return gear.careQty
        }
    }

    private func quantitySection(_ gear: Gear) -> some View {
        let maxQty = max(1, available(gear))
        return VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Quantity")
            QuantityStepper(value: $quantity, range: 1...maxQty, size: 46, accessibilityName: "Quantity")
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xE3F4F8)))
            Text(hint(gear)).tbFont(13).foregroundColor(.tbSecondary).frame(maxWidth: .infinity)
        }
    }

    private func hint(_ gear: Gear) -> String {
        switch operation {
        case .addStock: return "\(gear.unit.format(gear.ownedQty)) owned now"
        case .removeStock: return source == .ready ? "\(gear.readyQty) ready at home" : "\(gear.careQty) need care"
        case .sendToCare: return "\(gear.readyQty) ready at home"
        case .markReady: return gear.careQty == 1 ? "1 needs care" : "\(gear.careQty) need care"
        }
    }

    private func previewResult(_ gear: Gear) -> AdjustPreview? {
        guard let q = quantity else { return nil }
        return try? GearUseCases.preview(gear, operation: operation, quantity: q, source: source)
    }

    @ViewBuilder private func previewSection(_ gear: Gear) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Preview change")
            if let p = previewResult(gear) {
                HStack(spacing: 10) {
                    PreviewTile(title: "Ready", before: p.before.ready, after: p.after.ready, icon: "checkmark", tint: .tbReady)
                    if gear.trackingType == .reusable {
                        PreviewTile(title: "Care", before: p.before.care, after: p.after.care, icon: "wrench.fill", tint: .tbCoral)
                    } else {
                        PreviewTile(title: "Owned", before: p.before.owned, after: p.after.owned, icon: "shippingbox.fill", tint: Color(hex: 0x5E7383))
                    }
                }
                Text("Out stays \(p.after.out). Trips change Out, not this screen.")
                    .tbFont(12).foregroundColor(.tbSecondary)
            } else {
                let q = quantity ?? 0
                let message = (try? GearUseCases.preview(gear, operation: operation, quantity: max(q, 0), source: source)) == nil
                    ? errorMessage(gear) : "Enter a quantity."
                InfoBanner(text: message, kind: .warning)
            }
        }
    }

    private func errorMessage(_ gear: Gear) -> String {
        do {
            _ = try GearUseCases.preview(gear, operation: operation, quantity: quantity ?? 0, source: source)
            return ""
        } catch {
            return (error as? DomainError)?.message ?? error.localizedDescription
        }
    }

    private func confirm(_ gear: Gear) {
        guard let q = quantity else { return }
        do {
            try store.perform { db, now in
                try GearUseCases.adjust(&db, gearID: gearID, operation: operation, quantity: q, source: source, reason: reason,
                                        note: note, expectedRevision: expectedRevision, operationID: operationID, tripID: tripID, now: now)
            }
            services.haptics.success()
            ui.showToast("Stock updated")
            router.pop()
        } catch let error as DomainError where error.isConflict {
            expectedRevision = store.db.gear[gearID]?.stockRevision ?? expectedRevision
            ui.show(error)
        } catch {
            ui.show(error)
        }
    }
}

struct PreviewTile: View {
    let title: String
    let before: Int
    let after: Int
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image.symbol(icon, fallback: "circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).tbFont(12, .medium).foregroundColor(.tbText)
                HStack(spacing: 5) {
                    Text("\(before)").tbFont(21, .heavy).foregroundColor(.tbText)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundColor(.tbText)
                    Text("\(after)").tbFont(21, .heavy).foregroundColor(after == before ? .tbText : Color(hex: 0x14A6B8))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .tbCard(radius: 14, padding: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): before \(before), change \(changeText), after \(after)")
    }

    private var changeText: String {
        let d = after - before
        return d == 0 ? "No change" : (d > 0 ? "+\(d)" : "−\(-d)")
    }
}
