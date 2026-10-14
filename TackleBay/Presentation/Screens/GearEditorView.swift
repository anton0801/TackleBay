import SwiftUI

struct GearEditorView: View {
    let mode: GearEditorMode
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var draft = GearDraft()
    @State private var original = GearDraft()
    @State private var loaded = false
    @State private var showErrors = false
    @State private var pickingPhoto = false
    @State private var processingPhoto = false
    /// Photos picked in this session that aren't saved yet (removed again on discard).
    @State private var pendingPhotos: [PhotoRef] = []

    private var isNew: Bool { if case .new = mode { return true } else { return false } }
    private var editingID: UUID? { if case .edit(let id) = mode { return id } else { return nil } }
    private var gear: Gear? { editingID.flatMap { store.db.gear[$0] } }
    private var errors: [GearField: String] { GearUseCases.validate(draft, isNew: isNew) }
    private var isDirty: Bool { draft != original }

    var body: some View {
        Group {
            if !isNew && gear == nil {
                MissingRecordView()
            } else {
                editor
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $pickingPhoto) {
            PhotoPicker { data in
                pickingPhoto = false
                if let data = data { importPhoto(data) }
            }
            .ignoresSafeArea()
        }
    }

    private var editor: some View {
        HeroScreen(heroHeight: 146, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 196)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, -6)
                    .padding(.bottom, 14)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        HeroTextButton(title: "Cancel", pill: false, action: cancel)
                        Spacer()
                        GoldPillButton(title: "Save", action: save)
                    }
                    Text(isNew ? "Add Gear" : "Edit Gear")
                        .tbDisplay(32)
                        .foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.6), radius: 5)
                        .accessibilityAddTraits(.isHeader)
                    Text("Keep your tackle organized\nand ready for the next trip.")
                        .tbFont(13, .medium)
                        .foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.6), radius: 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 8) {
                photoAndName
                categoryRow
                trackingRow
                unitRow
                if draft.countingUnit == .other {
                    TBTextField(label: "Custom unit", text: $draft.customUnit, placeholder: "e.g. box", error: shown(.customUnit), limit: 20)
                        .disabled(!isNew)
                }
                storageRow
                if isNew { quantityTiles } else { stockSummary }
                notesRow
                if let hint = GearUseCases.duplicateNameHint(store.db, draft: draft) {
                    InfoBanner(text: hint, kind: .info)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.8)))
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: save) { Text("Save gear") }
                    .buttonStyle(GoldButtonStyle())
            }
        }
    }

    private func shown(_ field: GearField) -> String? { showErrors ? errors[field] : nil }

    // MARK: Sections

    private var photoAndName: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { pickingPhoto = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xE9F7FB))
                    if let ref = currentPhotoRef, let image = store.photos.image(ref, thumbnail: true) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 104, height: 98).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if let art = gear?.sampleArt {
                        Image(art).resizable().scaledToFit().padding(10)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill").font(.system(size: 26, weight: .semibold)).foregroundColor(Color(hex: 0x17A9BC))
                            Text(processingPhoto ? "Saving…" : "Add photo").tbFont(13, .medium).foregroundColor(.tbSecondary)
                        }
                    }
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: 0x6CCFDE), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                        .padding(6)
                }
                .frame(width: 104, height: 98)
            }
            .buttonStyle(PressableStyle())
            .disabled(processingPhoto)
            .accessibilityLabel(currentPhotoRef == nil ? "Choose photo" : "Change photo")
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").tbFont(13, .medium).foregroundColor(.tbSecondary)
                TBTextField(label: nil, text: $draft.name, placeholder: "e.g. Shore rod", error: shown(.name), limit: 80, capitalization: .sentences)
                if currentPhotoRef != nil {
                    Button("Remove photo") { draft.photoID = nil }
                        .tbFont(13, .semibold)
                        .foregroundColor(.tbError)
                        .frame(minHeight: 44)
                }
            }
            .padding(.top, 4)
        }
    }

    private var currentPhotoRef: PhotoRef? {
        guard let id = draft.photoID else { return nil }
        return pendingPhotos.first { $0.id == id } ?? store.db.photos[id]
    }

    private var categoryRow: some View {
        Menu {
            Picker("Category", selection: $draft.category) {
                ForEach(GearCategory.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            PickerRow(label: "Category", value: draft.category.title) {
                CategoryIcon(category: draft.category, size: 18, color: Color(hex: 0x1A6E92))
            }
        }
    }

    private var trackingRow: some View {
        Group {
            if isNew {
                Menu {
                    Picker("Tracking", selection: $draft.trackingType) {
                        ForEach(TrackingType.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    PickerRow(label: "Tracking", value: draft.trackingType.title) { trackingIcon }
                }
                .onChange(of: draft.trackingType) { t in if t == .consumable { draft.careQty = 0 } }
            } else {
                PickerRow(label: "Tracking", value: draft.trackingType.title, locked: true) { trackingIcon }
            }
        }
    }

    private var trackingIcon: some View {
        Image(systemName: draft.trackingType == .reusable ? "arrow.triangle.2.circlepath" : "drop.fill")
            .font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x1592C7))
    }

    private var unitRow: some View {
        Group {
            if isNew {
                Menu {
                    Picker("Count in", selection: $draft.countingUnit) {
                        ForEach(CountingUnit.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    PickerRow(label: "Count in", value: unitTitle) { unitIcon }
                }
            } else {
                PickerRow(label: "Count in", value: unitTitle, locked: true) { unitIcon }
            }
        }
    }

    private var unitTitle: String {
        draft.countingUnit == .other ? (draft.customUnit.isEmpty ? "Other" : draft.customUnit) : draft.countingUnit.title
    }

    private var unitIcon: some View {
        Image(systemName: "cube.fill").font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x1592C7))
    }

    private var storageRow: some View {
        let suggestions = Array(Set(store.db.gear.values.map(\.storage))).sorted()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: 0x1592C7))
                    .frame(width: 32, height: 32).background(Circle().fill(Color.tbIceTile))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Storage").tbFont(11, .medium).foregroundColor(.tbSecondary)
                    TextField("e.g. Blue rack", text: $draft.storage)
                        .tbFont(16, .bold)
                        .foregroundColor(.tbText)
                        .onChange(of: draft.storage) { if $0.count > 80 { draft.storage = String($0.prefix(80)) } }
                        .accessibilityLabel("Storage")
                }
                Spacer(minLength: 0)
                if !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions, id: \.self) { s in Button(s) { draft.storage = s } }
                    } label: {
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Choose a saved storage place")
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF8FDFE)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(shown(.storage) == nil ? Color.tbCardBorder : Color.tbError, lineWidth: 1))
            if let e = shown(.storage) { Text(e).tbFont(13, .medium).foregroundColor(.tbError) }
        }
    }

    private var quantityTiles: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                QuantityTile(title: "Ready", icon: "checkmark", iconColor: .white, iconBackground: Color(hex: 0x17A9BC),
                             value: $draft.readyQty, placeholder: "–", error: shown(.ready) != nil)
                if draft.trackingType == .reusable {
                    QuantityTile(title: "Needs care", icon: "wrench.fill", iconColor: .tbCoral, iconBackground: .tbCoralSoft,
                                 value: $draft.careQty, placeholder: "0", error: shown(.care) != nil)
                }
            }
            if let e = shown(.ready) ?? shown(.care) ?? shown(.total) {
                Label(e, systemImage: "exclamationmark.circle.fill").tbFont(13, .medium).foregroundColor(.tbError)
            } else {
                Text("Enter what you actually own right now, in \(UnitLabel(unit: draft.countingUnit, custom: draft.customUnit).plural).")
                    .tbFont(12).foregroundColor(.tbSecondary)
            }
        }
    }

    private var stockSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let gear = gear {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundColor(.tbSecondary)
                    Text("Ready \(gear.readyQty) · Needs care \(gear.careQty) · Out \(gear.outQty)")
                        .tbFont(17, .semibold).foregroundColor(.tbText)
                }
                Text("Quantities change only through Adjust Stock, trips and care.")
                    .tbFont(14).foregroundColor(.tbSecondary)
                Button {
                    router.replaceTop(with: .adjustStock(gear.id, operation: nil, tripID: nil))
                } label: { ButtonLabel(title: "Adjust stock", chevron: true) }
                .buttonStyle(OutlineButtonStyle(height: 50))
                .disabled(isDirty)
                if isDirty {
                    Text("Save or cancel your edits first.").tbFont(13).foregroundColor(.tbSecondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xF8FDFE)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1.2))
    }

    private var notesRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.tbSecondary)
                .frame(width: 32, height: 32).background(Circle().fill(Color.tbIceTile))
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes (optional)").tbFont(11, .medium).foregroundColor(.tbSecondary)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.note)
                        .tbFont(14)
                        .foregroundColor(.tbText)
                        .frame(minHeight: 44)
                        .padding(.horizontal, -4)
                        .onChange(of: draft.note) { if $0.count > 2000 { draft.note = String($0.prefix(2000)) } }
                        .accessibilityLabel("Notes")
                    if draft.note.isEmpty {
                        Text("Add any details about this item...").tbFont(14).foregroundColor(.tbSecondary.opacity(0.7))
                            .padding(.top, 8).allowsHitTesting(false)
                    }
                }
                if let e = shown(.note) { Text(e).tbFont(12).foregroundColor(.tbError) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF8FDFE)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let gear = gear {
            draft = GearDraft(gear: gear)
        } else {
            draft = GearDraft()
        }
        original = draft
    }

    private func importPhoto(_ data: Data) {
        processingPhoto = true
        let photoStore = store.photos
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<PhotoRef, Error> in
                do { return .success(try photoStore.importPhoto(data: data)) } catch { return .failure(error) }
            }.value
            processingPhoto = false
            switch result {
            case .success(let ref):
                pendingPhotos.append(ref)
                draft.photoID = ref.id
            case .failure(let error):
                ui.show(error, title: "Photo not added")
            }
        }
    }

    private func save() {
        guard errors.isEmpty else {
            showErrors = true
            services.haptics.warning()
            return
        }
        let pending = pendingPhotos.first { $0.id == draft.photoID }
        let oldPhoto = gear?.photoID
        var removedPhoto: PhotoRef?
        let ok = ui.run {
            try store.perform { db, now in
                if let ref = pending { db.photos[ref.id] = ref }
                if isNew {
                    try GearUseCases.create(&db, draft: draft, now: now)
                } else {
                    try GearUseCases.update(&db, draft: draft, now: now)
                    if let old = oldPhoto, old != draft.photoID, !db.gear.values.contains(where: { $0.photoID == old }) {
                        removedPhoto = db.photos[old]
                        db.photos[old] = nil
                    }
                }
            }
        }
        guard ok else { return }
        services.tapFeedback()
        if let removed = removedPhoto { store.photos.remove(removed) }
        for ref in pendingPhotos where ref.id != draft.photoID { store.photos.remove(ref) }
        pendingPhotos = []
        original = draft
        if isNew {
            router.replaceTop(with: .gearDetail(draft.id))
        } else {
            router.pop()
        }
    }

    private func cancel() {
        guard isDirty else {
            discard()
            return
        }
        ui.alert = AlertItem(title: "Discard changes?", message: "Your edits to this gear haven't been saved.", actions: [
            AlertAction(title: "Keep Editing", role: .cancel),
            AlertAction(title: "Discard Changes", role: .destructive) { discard() }
        ])
    }

    private func discard() {
        for ref in pendingPhotos { store.photos.remove(ref) }
        pendingPhotos = []
        router.pop()
    }
}

/// Bordered row with a round icon, small label, bold value and a chevron.
struct PickerRow<Icon: View>: View {
    let label: String
    let value: String
    var locked = false
    let icon: Icon

    init(label: String, value: String, locked: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.label = label
        self.value = value
        self.locked = locked
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 32, height: 32).background(Circle().fill(Color.tbIceTile))
            VStack(alignment: .leading, spacing: 0) {
                Text(label).tbFont(11, .medium).foregroundColor(.tbSecondary)
                Text(value).tbFont(16, .bold).foregroundColor(.tbText).lineLimit(1)
            }
            Spacer()
            Image(systemName: locked ? "lock.fill" : "chevron.down")
                .font(.system(size: locked ? 12 : 13, weight: .bold))
                .foregroundColor(locked ? .tbSecondary : .tbText)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF8FDFE)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(locked ? "Fixed after the record is created" : "Double tap to change")
    }
}

struct QuantityTile: View {
    let title: String
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    @Binding var value: Int?
    var placeholder = "0"
    var error = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(iconBackground))
                Text(title).tbFont(14, .bold).foregroundColor(.tbText)
            }
            QuantityStepper(value: $value, range: 0...StockRules.maxQuantity, size: 34, placeholder: placeholder, accessibilityName: title)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF8FDFE)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(error ? Color.tbError : Color.tbCardBorder, lineWidth: 1))
    }
}
