import SwiftUI

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .gearDetail(let id): GearDetailView(gearID: id)
        case .gearEditor(let mode): GearEditorView(mode: mode)
        case .adjustStock(let id, let operation, let tripID): AdjustStockView(gearID: id, initialOperation: operation, tripID: tripID)
        case .kitEditor(let mode): KitEditorView(mode: mode)
        case .tripEditor(let mode): TripEditorView(mode: mode)
        case .packing(let id, let kitID): PackingView(tripID: id, applyKitID: kitID)
        case .activeTrip(let id): ActiveTripView(tripID: id)
        case .returnGear(let id): ReturnGearView(tripID: id)
        case .tripSummary(let id): TripSummaryView(tripID: id)
        case .needsCare(let tripID): NeedsCareView(tripFilter: tripID)
        case .bonus: BayBonusView()
        case .showcase: ShowcaseView()
        case .settings: SettingsView()
        case .backup: BackupView()
        case .privacy: PrivacyView()
        case .about: AboutView()
        }
    }
}

/// Shown when a link points to a record that no longer exists.
struct MissingRecordView: View {
    var title = "Gear is no longer available"
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "questionmark.folder")
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(.tbSecondary)
            Text(title).tbFont(24, .heavy).foregroundColor(.tbText).multilineTextAlignment(.center)
            Button { router.pop() } label: { ButtonLabel(title: "Back", icon: "chevron.left") }
                .buttonStyle(GoldButtonStyle())
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tbBackground.ignoresSafeArea())
    }
}
