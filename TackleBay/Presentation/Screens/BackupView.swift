import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var backup: BackupService
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var busy: String?
    @State private var importError: String?

    private var db: TBDatabase { store.db }

    var body: some View {
        ZStack {
            HeroScreen(heroHeight: 196, overlap: 20, contentTopPadding: 14) {
                ZStack(alignment: .topLeading) {
                    PelicanPeek(width: 250)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 10)
                        .padding(.bottom, 14)
                    Image("tb_trip_log").resizable().scaledToFit().frame(width: 96)
                        .rotationEffect(.degrees(-6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 70)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                    CircleIconButton(systemName: "chevron.left", style: .light, size: 38, label: "Back") { router.pop() }
                        .padding(.leading, 14)
                }
            } content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Backup & Restore").tbDisplay(29).foregroundColor(.tbText).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count(db.gear.count, "gear record")) · \(count(db.kits.count, "kit")) · \(count(db.trips.count, "trip"))")
                            .tbFont(15).foregroundColor(.tbSecondary)
                        Text("\(count(db.photos.count, "photo")) · \(count(db.movements.count, "stock movement"))")
                            .tbFont(12).foregroundColor(.tbSecondary)
                    }
                    Button(action: export) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .bold))
                            Text("Export backup")
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy))
                        }
                    }
                    .buttonStyle(GoldButtonStyle(height: 50))
                    Button { importing = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down").font(.system(size: 19, weight: .bold)).foregroundColor(Color(hex: 0x17A9BC))
                            Text("Import backup")
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy))
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(height: 50))
                    .disabled(backup.importBlockReason() != nil)
                    if let reason = backup.importBlockReason() {
                        InfoBanner(text: reason, detail: "Import and restore replace everything, so they wait until the trip is returned. Export still works.", kind: .warning)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x17A9BC))
                            .frame(width: 36, height: 36).background(Circle().fill(Color(hex: 0xE0F4F9)))
                        Text("Includes gear, storage notes, photos and bonus progress. The file isn't encrypted by the app.")
                            .tbFont(13).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").font(.system(size: 17, weight: .semibold)).foregroundColor(Color(hex: 0x17A9BC))
                            .frame(width: 42, height: 42).background(Circle().fill(Color(hex: 0xDDF3F8)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Last export").tbFont(12).foregroundColor(.tbSecondary)
                            Text(db.settings.lastExportAt.map { Fmt.dayTimeComma($0, now: store.now) } ?? "Never").tbFont(16, .heavy).foregroundColor(.tbText)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xE9F6FA)))
                    if let date = backup.previousCopyDate {
                        Divider().background(Color.tbBorder)
                        Button(action: restorePrevious) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: 0x17A9BC))
                                    .frame(width: 42, height: 42).background(Circle().fill(Color(hex: 0xE0F4F9)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Restore previous data").tbFont(16, .heavy).foregroundColor(.tbText)
                                    Text("Replace current data with the safety copy from \(Fmt.dayTimeComma(date, now: store.now)).")
                                        .tbFont(12).foregroundColor(.tbSecondary).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                            }
                            .tbCard(radius: 16, padding: 10)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(backup.importBlockReason() != nil)
                        Button("Delete previous copy") {
                            ui.confirm("Delete the safety copy?", message: "You won't be able to restore the data you had before the last import.",
                                       confirm: "Delete copy", destructive: true) { backup.deletePreviousCopy() }
                        }
                        .tbFont(16, .semibold).foregroundColor(.tbError).frame(minHeight: 44)
                    }
                }
            }
            if let busy = busy {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().scaleEffect(1.4)
                    Text(busy).tbFont(18, .semibold).foregroundColor(.tbText)
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
                .accessibilityElement(children: .combine)
            }
            if let error = importError {
                ImportErrorCard(message: error) {
                    importError = nil
                    importing = true
                } onBack: {
                    importError = nil
                }
            }
        }
        .onAppear {
            #if DEBUG
            if DebugScenario.showImportError { importError = "Some gear records have invalid quantities." }
            #endif
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): validate(url)
            case .failure: break
            }
        }
        .sheet(item: Binding(get: { exportURL.map { ExportItem(url: $0) } }, set: { if $0 == nil { exportURL = nil } })) { item in
            ShareSheet(items: [item.url]) { backup.cleanUpExport() }
        }
    }

    private func count(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

    private func export() {
        busy = "Preparing backup…"
        Task {
            do {
                let url = try await backup.makeExportFile()
                busy = nil
                exportURL = url
            } catch {
                busy = nil
                ui.show(error, title: "Backup not created")
            }
        }
    }

    private func validate(_ url: URL) {
        busy = "Validating backup…"
        Task {
            do {
                let candidate = try await backup.readCandidate(from: url)
                busy = nil
                showPreview(candidate)
            } catch {
                busy = nil
                importError = (error as? DomainError)?.message ?? "This file isn't a valid Tackle Bay backup."
            }
        }
    }

    private func restorePrevious() {
        busy = "Validating previous data…"
        Task {
            do {
                let candidate = try await backup.readPreviousCandidate()
                busy = nil
                showPreview(candidate)
            } catch {
                busy = nil
                importError = (error as? DomainError)?.message ?? "The safety copy couldn't be read."
            }
        }
    }

    private func showPreview(_ candidate: ImportCandidate) {
        ui.present {
            ImportPreviewSheet(summary: candidate.summary) {
                ui.dismissSheet()
                busy = "Replacing data…"
                Task {
                    do {
                        try await backup.apply(candidate)
                        busy = nil
                        router.resetAll()
                        ui.showToast("Data replaced")
                    } catch {
                        busy = nil
                        importError = (error as? DomainError)?.message ?? error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ImportPreviewSheet: View {
    let summary: BackupSummary
    let onReplace: () -> Void
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Ready to replace", subtitle: "This backup passed every check. Replace swaps all current data; nothing is merged.") { ui.dismissSheet() }
            VStack(spacing: 0) {
                row("Format", "Tackle Bay backup v1")
                row("Created", Fmt.fullDateTime(summary.createdAt))
                row("Gear / Kits / Trips", "\(summary.gearCount) / \(summary.kitCount) / \(summary.tripCount)")
                row("Photos / Movements", "\(summary.photoCount) / \(summary.movementCount)")
                row("Trip on the water", summary.hasOpenTrip ? "Yes" : "No")
                row("Tickets / Parts", "\(summary.tickets) / \(summary.parts)")
                row("Miniatures built", "\(summary.builtMiniatures) of 4", last: true)
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            InfoBanner(text: "A safety copy of your current data is saved first.", kind: .info)
            Button(action: onReplace) { Text("Replace all data") }.buttonStyle(GoldButtonStyle())
            Button("Cancel") { ui.dismissSheet() }.buttonStyle(SoftButtonStyle(height: 50))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func row(_ a: String, _ b: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(a).tbFont(16).foregroundColor(.tbSecondary)
                Spacer()
                Text(b).tbFont(16, .bold).foregroundColor(.tbText).multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 44)
            if !last { Divider() }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "This backup could not be imported" — the current data is untouched.
struct ImportErrorCard: View {
    let message: String
    let onChooseAnother: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
            VStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "doc")
                        .font(.system(size: 46, weight: .regular))
                        .foregroundColor(Color(hex: 0xE5484D))
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: 0xE5484D))
                        .background(Circle().fill(Color.white))
                        .offset(x: 8, y: 4)
                }
                .frame(width: 104, height: 104)
                .background(Circle().fill(Color(hex: 0xFDECEC)))
                .accessibilityHidden(true)
                Text("This backup could not be imported")
                    .tbFont(25, .heavy, max: 34).foregroundColor(.tbText).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("\(message) Your current data has not changed.")
                    .tbFont(15).foregroundColor(.tbText).multilineTextAlignment(.center)
                Button("Choose another file", action: onChooseAnother).buttonStyle(OutlineButtonStyle(height: 46))
                Button("Back to data", action: onBack).buttonStyle(GoldButtonStyle(height: 46))
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white))
            .padding(.horizontal, 28)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .accessibilityAddTraits(.isModal)
        }
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        HeroScreen(heroHeight: 84, overlap: 20, contentTopPadding: 12) {
            HStack(spacing: 8) {
                Button { router.pop() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            .frame(width: 36, height: 36).background(Circle().fill(Color.tbNavy))
                        Text("Back").tbFont(16, .semibold).foregroundColor(.tbText)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Back")
                TackleBayLogo(height: 42)
                    .padding(.leading, 6)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        } content: {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("Privacy &\nBonus Rules")
                        .tbDisplay(34)
                        .foregroundColor(.tbText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Swoosh().fill(Color(hex: 0x2BD0E4)).frame(width: 170, height: 12)
                }
                .padding(.bottom, 4)
                InfoCard(icon: "iphone", title: "Local data",
                         text: "Your gear, places and notes stay on this device. There's no account, analytics or ads, and nothing is sent to the developer.",
                         link: "Manage data") { router.push(.backup) }
                InfoCard(icon: "photo", title: "Photos",
                         text: "You choose which photos to add. The app keeps a resized copy without location data and never changes your original.")
                InfoCard(icon: "square.and.arrow.up", title: "Sharing",
                         text: "Export or share only when you choose. The share sheet doesn't confirm that anything was delivered.")
                InfoCard(icon: "externaldrive.fill", title: "Device backups",
                         text: "Your data may be included in your device's own backups, depending on your device settings.")
                InfoCard(icon: "gift.fill", title: "Free bonus",
                         text: "No purchases, cash prizes or withdrawals. Tickets and Parts are free, virtual and can't be bought, sold or exchanged.",
                         link: "Open Bay Bonus") { router.push(.bonus) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill").font(.system(size: 22)).foregroundColor(Color(hex: 0x1F9BE0))
                        Text("Bonus odds").tbFont(19, .heavy).foregroundColor(.tbText)
                    }
                    OddsTable()
                    Text(BonusRules.probabilitiesText).tbFont(12).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
                    Text(BonusRules.howItWorksText).tbFont(12).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .tbCard(radius: 18, padding: 12)
                InfoCard(icon: "clock.fill", title: "Device time",
                         text: "Free tickets follow your device clock. If the clock moves back by more than 5 minutes, claiming pauses until it's corrected. An offline app can't fully prevent clock changes.")
                InfoCard(icon: "trash.fill", title: "Deleting data",
                         text: "Reset All Data deletes everything the app stores, including the safety copy. Files you exported stay where you saved them.",
                         link: "Delete data") { ResetFlow.start(ui: ui) }
            }
        }
    }
}
