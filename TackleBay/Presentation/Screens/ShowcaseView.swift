import SwiftUI

struct ShowcaseView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    private var db: TBDatabase { store.db }

    var body: some View {
        HeroScreen(heroHeight: 190, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanKeeper(height: 170)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 6)
                    .padding(.bottom, 10)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        CircleIconButton(systemName: "chevron.left", style: .light, size: 38, label: "Back") { router.pop() }
                        TackleBayLogo(height: 44)
                    }
                    Text("My Showcase").tbDisplay(29).foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.7), radius: 5)
                        .accessibilityAddTraits(.isHeader)
                    Text("Build and display your favorite\ndockside pieces.").tbFont(13, .medium).foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.7), radius: 4)
                    HStack(spacing: 8) {
                        Image("tb_parts_token").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Fmt.parts(db.wallet.parts)).tbFont(16, .heavy).foregroundColor(.tbText)
                            Text("\(db.ownerships.count) of 4 built").tbFont(11).foregroundColor(.tbSecondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.95)))
                    .accessibilityElement(children: .combine)
                    .padding(.leading, 100)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 10) {
                if BonusUseCases.isCollectionComplete(db) {
                    InfoBanner(text: "Your bay collection is complete.", detail: "Enjoy your miniatures on My Bay.", kind: .success)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(BonusRules.collectibles, id: \.id) { info in
                        CollectibleCard(info: info)
                    }
                }
                if db.settings.selectedCollectibleID != nil {
                    Button {
                        ui.run { try store.perform { db, _ in try BonusUseCases.display(&db, collectibleID: nil) } }
                    } label: { ButtonLabel(title: "Use Pelican on My Bay", icon: "arrow.uturn.backward") }
                    .buttonStyle(OutlineButtonStyle(height: 44))
                }
                Text("Miniatures are decorative virtual items. They never add real gear to your library.")
                    .tbFont(12).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
                backToBonus
            }
        }
    }

    private var backToBonus: some View {
        ZStack(alignment: .leading) {
            FillImage(name: "tb_bay_header", height: 76, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                if router.currentEntries.dropLast().last?.route == .bonus { router.pop() } else { router.replaceTop(with: .bonus) }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .heavy))
                    Text("Back to bonus")
                }
            }
            .buttonStyle(NavyButtonStyle(height: 50))
            .padding(.leading, 10)
        }
        .frame(height: 76)
        .padding(.top, 4)
    }
}

struct CollectibleCard: View {
    let info: CollectibleInfo
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        let db = store.db
        let owned = db.ownerships[info.id] != nil
        let onBay = db.settings.selectedCollectibleID == info.id
        let missing = max(0, info.costParts - db.wallet.parts)
        VStack(spacing: 4) {
            Image(info.assetName).resizable().scaledToFit()
                .frame(width: 140, height: 140)
                .overlay(alignment: .topLeading) {
                    if !owned {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            .frame(width: 26, height: 26).background(Circle().fill(Color.tbNavy.opacity(0.7)))
                    }
                }
                .accessibilityHidden(true)
            Text(info.name).tbFont(16, .heavy).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.75)
            if owned {
                Text(stateLabel(owned: owned, onBay: onBay, missing: missing)).tbFont(11, .semibold).foregroundColor(.tbSecondary)
            } else {
                HStack(spacing: 4) {
                    Image("tb_parts_token").resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true)
                    Text("\(info.costParts) Parts · \(stateLabel(owned: owned, onBay: onBay, missing: missing))")
                        .tbFont(11, .medium).foregroundColor(.tbSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            actions(owned: owned, onBay: onBay, missing: missing)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xF4FBFE)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
        .shadow(color: Color(hex: 0x0B4F6C).opacity(0.06), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(info.name). \(info.description)")
    }

    private func stateLabel(owned: Bool, onBay: Bool, missing: Int) -> String {
        if onBay { return "On My Bay" }
        if owned { return "Built" }
        return missing == 0 ? "Ready to Build" : "Locked by Balance"
    }

    @ViewBuilder private func actions(owned: Bool, onBay: Bool, missing: Int) -> some View {
        if owned {
            HStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.tbTeal))
                    Text("Built").tbFont(13, .bold).foregroundColor(.tbText)
                }
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xD8F4F4)))
                if onBay {
                    Text("On My Bay").tbFont(11, .bold).foregroundColor(.tbTeal)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                } else {
                    Button {
                        ui.run { try store.perform { db, _ in try BonusUseCases.display(&db, collectibleID: info.id) } }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill").font(.system(size: 11)).foregroundColor(Color(hex: 0x1580A8))
                            Text("Display\non My Bay").tbFont(10, .semibold).foregroundColor(.tbText).lineLimit(2)
                                .multilineTextAlignment(.leading).minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 5).frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.tbCardBorder, lineWidth: 1))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Display on My Bay")
                }
            }
        } else if missing == 0 {
            Button(action: build) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                    Text("Build")
                }
            }
            .buttonStyle(GoldButtonStyle(height: 36, compact: true))
        } else {
            Button {
                ui.alert = AlertItem(title: "\(missing) more Parts needed", message: "Cast with free tickets in Bay Bonus to collect Parts. There's no store and no time limit.",
                                     actions: [AlertAction(title: "OK", role: .cancel),
                                               AlertAction(title: "Back to Bonus") {
                                                   if router.currentEntries.dropLast().last?.route == .bonus { router.pop() } else { router.replaceTop(with: .bonus) }
                                               }])
            } label: {
                HStack(spacing: 5) {
                    Image("tb_parts_token").resizable().scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true)
                    Text("\(missing) more Parts").tbFont(13, .bold).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Capsule().fill(LinearGradient(colors: [.tbGoldTop, .tbGoldBottom], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(Color.tbGoldEdge, lineWidth: 1))
                .frame(minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(missing) more Parts needed")
        }
    }

    private func build() {
        ui.present {
            BuildSheet(info: info)
        }
    }
}

struct BuildSheet: View {
    let info: CollectibleInfo
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var operationID = UUID()

    var body: some View {
        let before = store.db.wallet.parts
        let after = before - info.costParts
        VStack(spacing: 10) {
            ZStack {
                FillImage(name: "tb_bay_header", height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Image(info.assetName).resizable().scaledToFit().frame(width: 240, height: 240)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
            }
            .padding(.horizontal, -12)
            .accessibilityHidden(true)
            Text(info.name).tbDisplay(32).foregroundColor(.tbText).accessibilityAddTraits(.isHeader)
            Text("Decorative miniature").tbFont(16, .medium).foregroundColor(.tbSecondary)
            Text(info.description).tbFont(13).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Image("tb_parts_token").resizable().scaledToFit().frame(width: 22, height: 22)
                Text("\(info.costParts) Parts").tbFont(15, .bold).foregroundColor(.tbText)
            }
            .padding(.horizontal, 14).frame(minHeight: 34)
            .background(Capsule().fill(Color(hex: 0xD9F0F7)))
            if after < 0 {
                InfoBanner(text: "\(-after) more Parts needed", kind: .warning)
            }
            HStack(spacing: 14) {
                balanceCard("Before", before, dim: true)
                Image(systemName: "arrow.right").font(.system(size: 20, weight: .bold)).foregroundColor(.tbText)
                balanceCard("After", after, dim: false)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0xE0F2F8)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Parts before \(before), after \(after)")
            Button(action: confirm) {
                HStack(spacing: 10) { Image(systemName: "hammer.fill"); Text("Build miniature") }
            }
            .buttonStyle(GoldButtonStyle(height: 50))
            .disabled(after < 0)
            Button("Cancel") { ui.dismissSheet() }.buttonStyle(SoftButtonStyle(height: 48))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func balanceCard(_ title: String, _ value: Int, dim: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title).tbFont(12, .semibold).foregroundColor(.tbText)
            HStack(spacing: 8) {
                Image("tb_parts_token").resizable().scaledToFit().frame(width: 36, height: 36).saturation(dim ? 0 : 1).opacity(dim ? 0.7 : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(max(value, 0))").tbFont(26, .heavy).foregroundColor(.tbText)
                    Text("Parts").tbFont(13).foregroundColor(.tbSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
    }

    private func confirm() {
        do {
            try store.perform { db, now in try BonusUseCases.build(&db, collectibleID: info.id, operationID: operationID, now: now) }
            services.audio.play(.miniatureBuilt)
            services.haptics.success()
            ui.dismissSheet()
            ui.showToast("\(info.name) built")
        } catch {
            ui.dismissSheet()
            ui.show(error, title: "Not built")
        }
    }
}
