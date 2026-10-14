import PhotosUI
import SwiftUI
import UIKit

/// Sheet header used by every picker sheet.
struct SheetHeader: View {
    let title: String
    var subtitle: String?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).tbFont(26, .heavy).foregroundColor(.tbText).accessibilityAddTraits(.isHeader)
                if let subtitle = subtitle {
                    Text(subtitle).tbFont(15).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.tbText)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.tbIceTile))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Close")
            }
        }
    }
}

/// Picks one active gear record. Archived records never appear here.
struct GearPickerSheet: View {
    let title: String
    let isDemo: Bool
    var excluded: Set<UUID> = []
    var existing: Set<UUID> = []
    let onPick: (UUID) -> Void
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @State private var search = ""

    var body: some View {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let candidates = store.db.gear.values
            .filter { !$0.isArchived && !excluded.contains($0.id) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.storage.lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let allowed = candidates.filter { $0.isDemo == isDemo }
        let otherSpace = candidates.count - allowed.count
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: title, subtitle: "Only active gear can be picked.") { ui.dismissSheet() }
            SearchField(text: $search, placeholder: "Search gear...")
            ScrollView {
                VStack(spacing: 10) {
                    if allowed.isEmpty {
                        Text(q.isEmpty ? "No active gear to add." : "No gear matches.")
                            .tbFont(17, .semibold).foregroundColor(.tbSecondary).padding(.vertical, 24)
                    }
                    ForEach(allowed) { gear in
                        Button { onPick(gear.id) } label: {
                            HStack(spacing: 12) {
                                GearImage(gear: gear, width: 52, corner: 12)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(gear.name).tbFont(18, .bold).foregroundColor(.tbText).lineLimit(2)
                                    Text("Ready \(gear.unit.format(gear.readyQty)) · \(gear.storage)")
                                        .tbFont(15).foregroundColor(.tbSecondary).lineLimit(1)
                                }
                                Spacer()
                                if existing.contains(gear.id) {
                                    Text("In list").tbFont(14, .semibold).foregroundColor(.tbTeal)
                                } else {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundColor(.tbTeal)
                                }
                            }
                            .tbCard(radius: 18, padding: 10)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if otherSpace > 0 {
                        Text(isDemo ? "Your own gear can't be used in the sample collection." : "Sample gear stays in the sample collection and can't be mixed with your records.")
                            .tbFont(14).foregroundColor(.tbSecondary).multilineTextAlignment(.center).padding(.top, 6)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// Picks an existing kit (optionally "New kit").
struct KitPickerSheet: View {
    let title: String
    let isDemo: Bool?
    var allowNew = false
    let onPick: (UUID?) -> Void
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let kits = store.db.kits.values.filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let allowed = kits.filter { isDemo == nil || $0.isDemo == isDemo }
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: title) { ui.dismissSheet() }
            ScrollView {
                VStack(spacing: 10) {
                    if allowNew {
                        Button { onPick(nil) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundColor(.white)
                                    .frame(width: 44, height: 44).background(Circle().fill(Color.tbTeal))
                                Text("New kit").tbFont(18, .bold).foregroundColor(.tbText)
                                Spacer()
                            }
                            .tbCard(radius: 18, padding: 10)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if allowed.isEmpty && !allowNew {
                        Text("No kits yet. Save the setup you use most in My Kits.")
                            .tbFont(16).foregroundColor(.tbSecondary).multilineTextAlignment(.center).padding(.vertical, 20)
                    }
                    ForEach(allowed) { kit in
                        Button { onPick(kit.id) } label: {
                            HStack(spacing: 12) {
                                IconTile(systemName: "briefcase.fill", tint: .tbTeal, size: 44, circle: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kit.name).tbFont(18, .bold).foregroundColor(.tbText).lineLimit(2)
                                    Text(Fmt.items(kit.lines.count)).tbFont(15).foregroundColor(.tbSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundColor(.tbText)
                            }
                            .tbCard(radius: 18, padding: 10)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    if let isDemo = isDemo, kits.count > allowed.count {
                        Text(isDemo ? "Only the sample kit fits the sample collection." : "Sample kits stay in the sample collection and can't be mixed with your records.")
                            .tbFont(14).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// Picks a planned trip (Use for Trip).
struct TripPickerSheet: View {
    let title: String
    let isDemo: Bool
    let onPick: (UUID) -> Void
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let trips = store.db.trips.values.filter { $0.status == .planned && $0.isDemo == isDemo }
            .sorted { $0.plannedDepartureAt < $1.plannedDepartureAt }
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: title, subtitle: "Kit rows are added to the packing list. Nothing is packed automatically.") { ui.dismissSheet() }
            ScrollView {
                VStack(spacing: 10) {
                    if trips.isEmpty {
                        Text("No planned trips. Create one in Trips first.")
                            .tbFont(16).foregroundColor(.tbSecondary).padding(.vertical, 20)
                    }
                    ForEach(trips) { trip in
                        Button { onPick(trip.id) } label: {
                            HStack(spacing: 12) {
                                IconTile(systemName: "calendar", tint: .tbTeal, size: 44, circle: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trip.name).tbFont(18, .bold).foregroundColor(.tbText)
                                    Text("\(trip.place) · \(Fmt.dayTime(trip.plannedDepartureAt, now: store.now))")
                                        .tbFont(15).foregroundColor(.tbSecondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundColor(.tbText)
                            }
                            .tbCard(radius: 18, padding: 10)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - System pickers

/// PHPicker: the user picks one photo; no photo-library permission is requested.
struct PhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (Data?) -> Void
        init(onPicked: @escaping (Data?) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                onPicked(nil)
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async { self.onPicked(data) }
            }
        }
    }
}

/// System share sheet. Sharing is only started by the user; it doesn't confirm delivery.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
