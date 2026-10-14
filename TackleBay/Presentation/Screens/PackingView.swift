import SwiftUI

struct PackingView: View {
    let tripID: UUID
    let applyKitID: UUID?
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var appliedInitialKit = false

    var body: some View {
        Group {
            if let trip = store.db.trips[tripID] {
                if trip.status == .planned {
                    screen(trip)
                } else {
                    startedNotice(trip)
                }
            } else {
                MissingRecordView(title: "This trip is no longer available")
            }
        }
        .onAppear {
            guard !appliedInitialKit, let kitID = applyKitID else { return }
            appliedInitialKit = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showMerge(kitID) }
        }
    }

    private func startedNotice(_ trip: Trip) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("This trip has started").tbFont(26, .heavy).foregroundColor(.tbText)
            Text("The packing list is fixed once a trip starts.").tbFont(17).foregroundColor(.tbSecondary)
            Button {
                router.replaceTop(with: trip.status == .completed || trip.status == .cancelled ? .tripSummary(trip.id)
                                  : (trip.status == .returning ? .returnGear(trip.id) : .activeTrip(trip.id)))
            } label: { ButtonLabel(title: "Open trip", chevron: true) }
            .buttonStyle(GoldButtonStyle())
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding()
    }

    private func screen(_ trip: Trip) -> some View {
        let progress = TripUseCases.progress(trip)
        let conflicts = TripUseCases.dateConflicts(store.db, trip: trip)
        return HeroScreen(heroHeight: 182, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanKeeper(height: 168)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 4)
                    .padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        CircleIconButton(systemName: "chevron.left", style: .navy, size: 38, label: "Back") { router.pop() }
                        TackleBayLogo(height: 44)
                        Spacer()
                        Menu {
                            Button { router.push(.tripEditor(.edit(trip.id))) } label: { Label("Edit plan", systemImage: "pencil") }
                            Button { cancelPlan(trip) } label: { Label("Cancel plan", systemImage: "xmark.circle") }
                            if TripUseCases.deleteBlockReason(store.db, tripID: trip.id) == nil {
                                Button(role: .destructive) { deletePlan(trip) } label: { Label("Delete plan", systemImage: "trash") }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .heavy)).foregroundColor(.tbText)
                                .frame(width: 38, height: 38).background(Circle().fill(Color.white.opacity(0.92)))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Plan actions")
                    }
                    Spacer(minLength: 0)
                    Text(trip.name)
                        .tbFont(26, .heavy, style: .largeTitle, max: 36)
                        .foregroundColor(.tbText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 230, alignment: .leading)
                        .shadow(color: .white.opacity(0.7), radius: 5)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 12)).foregroundColor(Color(hex: 0x557488))
                        Text("\(trip.place) · \(Fmt.dayTimeComma(trip.plannedDepartureAt, now: store.now))")
                            .tbFont(13, .medium).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: 250, alignment: .leading)
                    .shadow(color: .white.opacity(0.7), radius: 4)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(progress.text).tbFont(14, .bold).foregroundColor(.tbText)
                    TBProgressBar(fraction: progress.fraction, height: 11)
                }
                .tbCard(radius: 14, padding: 12)
                .accessibilityElement(children: .combine)
                if trip.plannedDepartureAt < store.now {
                    InfoBanner(text: "This plan date has passed", kind: .warning)
                }
                if !conflicts.isEmpty {
                    InfoBanner(text: "Same day as \(conflicts.map(\.name).joined(separator: ", ")).",
                               detail: "Plans don't reserve gear. Availability is checked when you start.", kind: .warning)
                }
                if trip.lines.isEmpty {
                    VStack(spacing: 8) {
                        Image("tb_tackle_box").resizable().scaledToFit().frame(width: 64, height: 56).accessibilityHidden(true)
                        Text("Your packing list is empty").tbFont(20, .heavy).foregroundColor(.tbText)
                        Text("Add a kit or single items you own.").tbFont(16).foregroundColor(.tbSecondary)
                    }
                    .padding(.vertical, 16)
                }
                ForEach(trip.lines) { line in
                    PackingRow(trip: trip, line: line,
                               onToggle: { toggle(trip, line) },
                               onOpen: { openRow(trip, line.id) })
                }
                HStack(spacing: 8) {
                    AddTile(title: "Add gear") { addGear(trip) }
                    AddTile(title: "Add kit") { addKit(trip) }
                }
                .disabled(trip.lines.count >= TripUseCases.maxLines)
                Text("Packed doesn't reserve or remove stock. Only Start Trip moves packed units out.")
                    .tbFont(12).foregroundColor(.tbSecondary).multilineTextAlignment(.center).padding(.top, 2)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { reviewDeparture(trip) } label: { ButtonLabel(title: "Review departure", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
            }
        }
    }

    // MARK: Actions

    private func toggle(_ trip: Trip, _ line: TripLine) {
        guard let gear = store.db.gear[line.gearID], !gear.isArchived else {
            openRow(trip, line.id)
            return
        }
        let target: Int
        if line.packedQty >= line.requiredQty {
            target = 0
        } else {
            target = min(line.requiredQty, gear.readyQty)
            if target <= line.packedQty {
                ui.info("Not enough ready at home", "\(gear.name): \(gear.unit.format(gear.readyQty)) ready. Adjust stock or mark care items ready first.")
                return
            }
        }
        if ui.run({ try store.perform { db, now in try TripUseCases.setPacked(&db, tripID: trip.id, lineID: line.id, packed: target, now: now) } }) {
            if target >= line.requiredQty {
                services.audio.play(.itemChecked)
                services.haptics.success()
            } else {
                services.haptics.selection()
            }
        }
    }

    private func openRow(_ trip: Trip, _ lineID: UUID) {
        ui.present {
            PackingRowSheet(tripID: trip.id, lineID: lineID)
        }
    }

    private func addGear(_ trip: Trip) {
        let existing = Set(trip.lines.map(\.gearID))
        ui.present {
            GearPickerSheet(title: "Add gear", isDemo: trip.isDemo, existing: existing) { gearID in
                ui.dismissSheet()
                var lineID: UUID?
                if ui.run({ lineID = try store.perform { db, now in try TripUseCases.addGear(&db, tripID: trip.id, gearID: gearID, now: now) } }),
                   existing.contains(gearID), let id = lineID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openRow(trip, id) }
                }
            }
        }
    }

    private func addKit(_ trip: Trip) {
        ui.present {
            KitPickerSheet(title: "Add kit", isDemo: trip.isDemo) { kitID in
                ui.dismissSheet()
                if let kitID = kitID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showMerge(kitID) }
                }
            }
        }
    }

    private func showMerge(_ kitID: UUID) {
        guard let preview = TripUseCases.mergePreview(store.db, tripID: tripID, kitID: kitID), let kit = store.db.kits[kitID] else { return }
        ui.present {
            MergePreviewSheet(kitName: kit.name, preview: preview) {
                ui.dismissSheet()
                if ui.run({ try store.perform { db, now in try TripUseCases.applyKit(&db, tripID: tripID, kitID: kitID, now: now) } }) {
                    ui.showToast("Kit added to the list")
                }
            }
        }
    }

    private func reviewDeparture(_ trip: Trip) {
        ui.present {
            DepartureReviewSheet(tripID: trip.id, expectedRevision: trip.revision) { started in
                ui.dismissSheet()
                if started {
                    services.audio.play(.tripStarted)
                    services.haptics.success()
                    router.replaceTop(with: .activeTrip(trip.id))
                }
            }
        }
    }

    private func cancelPlan(_ trip: Trip) {
        ui.confirm("Cancel \(trip.name)?", message: "The plan moves to History as cancelled. Your stock doesn't change.",
                   confirm: "Cancel plan", destructive: true, cancel: "Keep plan") {
            if ui.run({ try store.perform { db, now in try TripUseCases.cancelPlan(&db, tripID: trip.id, now: now) } }) { router.pop() }
        }
    }

    private func deletePlan(_ trip: Trip) {
        ui.confirm("Delete \(trip.name)?", message: "The plan and its packing list are removed. Your stock doesn't change.",
                   confirm: "Delete plan", destructive: true) {
            if ui.run({ try store.perform { db, _ in try TripUseCases.deleteTrip(&db, tripID: trip.id) } }) { router.pop() }
        }
    }
}

struct PackingRow: View {
    let trip: Trip
    let line: TripLine
    let onToggle: () -> Void
    let onOpen: () -> Void
    @EnvironmentObject private var store: TackleStore

    var body: some View {
        let gear = store.db.gear[line.gearID]
        let available = TripUseCases.isLineAvailable(store.db, line)
        let done = line.packedQty >= line.requiredQty
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    GearImage(gear: gear, width: 86, height: 46, corner: 10)
                        .opacity(available ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TripUseCases.lineName(store.db, line)).tbFont(15, .heavy).foregroundColor(.tbText).lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 5) {
                            Text("\(line.packedQty) / \(line.requiredQty) packed").tbFont(12).foregroundColor(.tbSecondary)
                            if line.importance == .optional { Badge(text: "Optional", color: .tbSecondary) }
                        }
                        if !available {
                            Text("Unavailable · Resolve").tbFont(11, .bold).foregroundColor(.tbError)
                        } else if let gear = gear, gear.readyQty < line.requiredQty {
                            Text("\(gear.readyQty) ready at home").tbFont(11, .semibold).foregroundColor(.tbCare)
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Button(action: onToggle) {
                ZStack {
                    if done {
                        Circle().fill(Color.tbTeal)
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundColor(.white)
                    } else {
                        Circle().strokeBorder(Color(hex: 0x9AAAB4), lineWidth: 2)
                        if line.packedQty > 0 {
                            Text("\(line.packedQty)").tbFont(13, .bold).foregroundColor(.tbTeal)
                        }
                    }
                }
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(done ? "Packed. Double tap to unpack" : "Not packed. Double tap to mark packed")
            Button(action: onOpen) {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                    .frame(width: 22, height: 44)
            }
            .accessibilityLabel("Edit row")
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
        .shadow(color: Color(hex: 0x0B4F6C).opacity(0.05), radius: 6, y: 3)
    }
}

struct AddTile: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy)).foregroundColor(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(Color(hex: 0x17A9BC)))
                Text(title).tbFont(14, .bold).foregroundColor(.tbText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.tbText)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Row sheet

struct PackingRowSheet: View {
    let tripID: UUID
    let lineID: UUID
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var required = 1
    @State private var packed = 0
    @State private var importance: Importance = .required
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        if let trip = store.db.trips[tripID], let line = trip.lines.first(where: { $0.id == lineID }) {
            content(trip, line)
                .onAppear {
                    guard !loaded else { return }
                    loaded = true
                    required = line.requiredQty
                    packed = line.packedQty
                    importance = line.importance
                    note = line.packingNote ?? ""
                }
        } else {
            Text("This row is no longer in the list.").padding(30)
        }
    }

    private func content(_ trip: Trip, _ line: TripLine) -> some View {
        let gear = store.db.gear[line.gearID]
        let available = TripUseCases.isLineAvailable(store.db, line)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    GearImage(gear: gear, width: 64, corner: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TripUseCases.lineName(store.db, line)).tbFont(24, .heavy).foregroundColor(.tbText)
                        if let gear = gear {
                            Text("Ready at home: \(gear.unit.format(gear.readyQty))").tbFont(16).foregroundColor(.tbSecondary)
                        }
                    }
                    Spacer()
                    Button { ui.dismissSheet() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.tbText)
                            .frame(width: 36, height: 36).background(Circle().fill(Color.tbIceTile))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Close")
                }
                if !available {
                    InfoBanner(text: "This gear is unavailable", detail: "Replace it with another record or remove the row before starting.", kind: .warning)
                    HStack(spacing: 10) {
                        Button { replace(trip) } label: { Text("Replace") }.buttonStyle(OutlineButtonStyle(height: 50))
                        Button { remove(trip) } label: { Text("Remove") }.buttonStyle(SoftButtonStyle(height: 50, foreground: .tbError))
                    }
                } else {
                    FieldLabel(text: "Packed")
                    IntStepper(value: $packed, range: 0...required, size: 52, accessibilityName: "Packed")
                    FieldLabel(text: "Required")
                    IntStepper(value: $required, range: 1...StockRules.maxQuantity, size: 46, accessibilityName: "Required")
                    FieldLabel(text: "Importance")
                    TBSegmented(options: [(Importance.required, "Required", nil), (Importance.optional, "Optional", nil)], selection: $importance, height: 48)
                    FieldLabel(text: "Packing note")
                    TBTextField(label: nil, text: $note, placeholder: "Optional", limit: 300)
                    Button { save(trip, line) } label: { Text("Save row") }.buttonStyle(GoldButtonStyle())
                    Button { remove(trip) } label: { Text("Remove from list") }.buttonStyle(SoftButtonStyle(height: 48, foreground: .tbError))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.8)
    }

    private func save(_ trip: Trip, _ line: TripLine) {
        let apply = {
            let newPacked = min(packed, required)
            if ui.run({ try store.perform { db, now in
                try TripUseCases.updateLine(&db, tripID: trip.id, lineID: line.id, required: required, packed: newPacked,
                                            importance: importance, note: note, now: now)
            } }) {
                if newPacked >= required && line.packedQty < line.requiredQty { services.audio.play(.itemChecked) }
                ui.dismissSheet()
            }
        }
        if packed > required {
            ui.confirm("Lower packed too?", message: "Required is now \(required), so Packed goes down from \(packed) to \(required).",
                       confirm: "Lower packed", action: apply)
        } else {
            apply()
        }
    }

    private func remove(_ trip: Trip) {
        if ui.run({ try store.perform { db, now in try TripUseCases.removeLine(&db, tripID: trip.id, lineID: lineID, now: now) } }) {
            ui.dismissSheet()
        }
    }

    private func replace(_ trip: Trip) {
        let existing = Set(trip.lines.map(\.gearID))
        ui.present {
            GearPickerSheet(title: "Replace with", isDemo: trip.isDemo, excluded: existing) { gearID in
                ui.dismissSheet()
                ui.run { try store.perform { db, now in try TripUseCases.replaceLine(&db, tripID: trip.id, lineID: lineID, gearID: gearID, now: now) } }
            }
        }
    }
}

// MARK: - Merge preview

struct MergePreviewSheet: View {
    let kitName: String
    let preview: KitMergePreview
    let onAdd: () -> Void
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Add “\(kitName)”", subtitle: "Matching rows add up. Packed stays as it is.") { ui.dismissSheet() }
            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Text("Item").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Existing").frame(width: 70)
                        Text("Added").frame(width: 56)
                        Text("Result").frame(width: 58)
                    }
                    .tbFont(13, .semibold).foregroundColor(.tbSecondary)
                    ForEach(preview.rows) { row in
                        HStack {
                            Text(row.name).tbFont(16, .semibold).foregroundColor(.tbText).frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.existing.map(String.init) ?? "—").frame(width: 70)
                            Text("+\(row.added)").frame(width: 56)
                            Text("\(row.result)").tbFont(16, .bold).foregroundColor(row.existing == nil ? .tbText : Color(hex: 0x14A6B8)).frame(width: 58)
                        }
                        .tbFont(16).foregroundColor(.tbText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(row.existing == nil ? Color.white : Color(hex: 0xE3F7FA)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.name): existing \(row.existing.map(String.init) ?? "none"), added \(row.added), result \(row.result)")
                    }
                    if preview.rows.contains(where: \.capped) {
                        Text("Some totals were capped at 9999.").tbFont(14).foregroundColor(.tbCare)
                    }
                }
            }
            .frame(maxHeight: 300)
            if !preview.unavailable.isEmpty {
                InfoBanner(text: "Not added: \(preview.unavailable.joined(separator: ", "))", detail: "These items are unavailable.", kind: .warning)
            }
            if preview.sampleMismatch {
                InfoBanner(text: "Sample and personal records can't be mixed in one trip.", kind: .error)
            } else if preview.overflow {
                InfoBanner(text: "This would make the list longer than 100 items.", kind: .error)
            }
            Button(action: onAdd) { Text(preview.unavailable.isEmpty ? "Add to list" : "Add available") }
                .buttonStyle(GoldButtonStyle())
                .disabled(preview.sampleMismatch || preview.overflow || preview.rows.isEmpty)
            Button("Cancel") { ui.dismissSheet() }.buttonStyle(SoftButtonStyle(height: 50))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Departure review

struct DepartureReviewSheet: View {
    let tripID: UUID
    let expectedRevision: Int64
    let onFinish: (Bool) -> Void
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @State private var note = ""
    @State private var operationID = UUID()
    @State private var showTaking = false

    var body: some View {
        if let review = TripUseCases.departureReview(store.db, tripID: tripID), let trip = store.db.trips[tripID] {
            content(review, trip)
        } else {
            Text("This trip is no longer available.").padding(30)
        }
    }

    private func content(_ review: DepartureReview, _ trip: Trip) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    FillImage(name: "tb_bay_header", height: 150)
                        .overlay(LinearGradient(colors: [Color(hex: 0xF4FBFE).opacity(0.95), Color(hex: 0xF4FBFE).opacity(0.55), .clear],
                                                startPoint: .leading, endPoint: .trailing))
                        .accessibilityHidden(true)
                    PelicanPeek(width: 196)
                        .frame(maxWidth: .infinity, alignment: .bottomTrailing)
                        .offset(x: 26, y: 2)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ready to\nleave?")
                            .tbFont(36, .heavy, style: .largeTitle, max: 46)
                            .foregroundColor(.tbText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(review.progress.text).tbFont(15, .bold).foregroundColor(.tbText)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 10)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, -20)
                .padding(.top, -6)
                TBProgressBar(fraction: review.progress.fraction, height: 11)
                ForEach(review.blockers, id: \.self) { InfoBanner(text: $0, kind: .error) }
                ForEach(review.missingRequired) { line in
                    HStack(spacing: 12) {
                        GearImage(gear: store.db.gear[line.gearID], width: 66, height: 56, corner: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(TripUseCases.lineName(store.db, line)).tbFont(18, .heavy).foregroundColor(.tbText)
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 16)).foregroundColor(Color(hex: 0xE58A13))
                                Text(line.packedQty == 0 ? "Not packed" : "\(line.packedQty) of \(line.requiredQty) packed")
                                    .tbFont(14, .semibold).foregroundColor(Color(hex: 0xC56A06))
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.tbText)
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xFFF3DC)))
                    .accessibilityElement(children: .combine)
                }
                if !review.conflictTrips.isEmpty {
                    InfoBanner(text: "Also planned the same day: \(review.conflictTrips.joined(separator: ", ")).", kind: .warning)
                }
                if review.needsMissingNote {
                    Text("Why are you leaving these behind?").tbFont(15, .bold).foregroundColor(.tbText).padding(.top, 2)
                    TBTextEditor(text: $note, placeholder: "Short pier session", minHeight: 52, limit: 300)
                }
                if !review.packedLines.isEmpty {
                    Button { withAnimation { showTaking.toggle() } } label: {
                        HStack {
                            Text("Taking \(Fmt.items(review.packedLines.count))").tbFont(14, .bold).foregroundColor(.tbText)
                            Spacer()
                            Image(systemName: showTaking ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).foregroundColor(.tbText)
                        }
                        .frame(minHeight: 36)
                    }
                    if showTaking {
                        ForEach(review.packedLines) { line in
                            HStack {
                                Text(TripUseCases.lineName(store.db, line)).tbFont(14).foregroundColor(.tbText)
                                Spacer()
                                Text(TripUseCases.lineUnit(store.db, line).format(line.packedQty)).tbFont(14, .semibold).foregroundColor(.tbText)
                            }
                        }
                    }
                }
                InfoBanner(text: "Only packed quantities leave your stock.", kind: .info)
                Button(action: start) {
                    ButtonLabel(title: review.needsMissingNote ? "Start with missing items" : "Start trip", chevron: true)
                }
                .buttonStyle(GoldButtonStyle(height: 50))
                .disabled(!review.canStart || (review.needsMissingNote && TextRules.trimmed(note).isEmpty))
                Button("Keep packing") { onFinish(false) }.buttonStyle(OutlineButtonStyle(height: 50, tint: .tbBorder))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.86)
    }

    private func start() {
        do {
            try store.perform { db, now in
                try TripUseCases.start(&db, tripID: tripID, expectedRevision: expectedRevision, missingNote: note,
                                       operationID: operationID, now: now)
            }
            onFinish(true)
        } catch let error as DomainError where error.isConflict {
            onFinish(false)
            ui.show(error, title: "Couldn't start")
        } catch {
            ui.show(error, title: "Couldn't start")
        }
    }
}
