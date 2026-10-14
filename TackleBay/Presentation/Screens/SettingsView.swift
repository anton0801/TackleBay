import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices

    private var settings: AppSettings { store.db.settings }
    private var sampleLoaded: Bool { SampleCollection.isLoaded(store.db) }

    var body: some View {
        HeroScreen(heroHeight: 136, overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                PelicanPeek(width: 200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, -30)
                    .padding(.bottom, 14)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        CircleIconButton(systemName: "chevron.left", style: .navy, size: 36, label: "Back") { router.pop() }
                        TackleBayLogo(height: 44)
                    }
                    Text("Settings").tbDisplay(36).foregroundColor(.tbText)
                        .shadow(color: .white.opacity(0.7), radius: 5)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 14)
            }
        } content: {
            VStack(spacing: 10) {
                SettingsGroup {
                    ToggleRow(icon: "iphone.radiowaves.left.and.right", title: "Haptics", isOn: binding(\.haptics))
                    ToggleRow(icon: "speaker.wave.2.fill", title: "Sound effects", isOn: binding(\.soundEffects))
                    ToggleRow(icon: "music.note", title: "Bonus ambience", isOn: binding(\.bonusAmbience))
                    ToggleRow(icon: "star.fill", title: "Show Bay Bonus", isOn: binding(\.showBonusOnHome), last: settings.showBonusOnHome)
                    if !settings.showBonusOnHome {
                        LinkRow(icon: "ticket.fill", title: "Open Bay Bonus", last: true) { router.push(.bonus) }
                    }
                }
                SettingsGroup {
                    LinkRow(icon: "graduationcap.fill", title: "View onboarding") {
                        withAnimation(.easeOut(duration: 0.2)) { ui.replayingOnboarding = true }
                    }
                    LinkRow(icon: "icloud.and.arrow.up.fill", title: "Backup & restore") { router.push(.backup) }
                    if sampleLoaded {
                        LinkRow(icon: "photo.on.rectangle", title: "Remove sample collection", last: true, action: removeSample)
                    } else {
                        LinkRow(icon: "photo.on.rectangle", title: "Load sample collection", last: true, action: loadSample)
                    }
                }
                SettingsGroup {
                    LinkRow(icon: "checkmark.shield.fill", title: "Privacy & bonus rules") { router.push(.privacy) }
                    LinkRow(icon: "info.circle.fill", title: "About", last: true) { router.push(.about) }
                }
                Button { ResetFlow.start(ui: ui) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Color(hex: 0xE5484D))
                            .frame(width: 34, height: 34).background(Circle().fill(Color(hex: 0xFCE3E3)))
                        Text("Reset all data").tbFont(15, .bold).foregroundColor(Color(hex: 0xD62F35))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0xD62F35))
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xFDF0F0)))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func binding(_ key: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.db.settings[keyPath: key] },
                set: { value in ui.run { try store.perform { db, _ in db.settings[keyPath: key] = value } } })
    }

    private func loadSample() {
        ui.confirm("Load sample collection?", message: "Adds clearly marked Sample gear, one kit and one planned trip. They never mix with your records and don't affect Bay Bonus.",
                   confirm: "Load sample") {
            if ui.run({ try store.perform { db, now in try SampleCollection.load(&db, now: now) } }) {
                ui.showToast("Sample collection loaded")
            }
        }
    }

    private func removeSample() {
        if let reason = SampleCollection.removeBlockReason(store.db) {
            ui.info("Can't remove yet", reason)
            return
        }
        ui.confirm("Remove sample collection?", message: "Only sample records and their history are removed. Your own gear and bonus progress stay.",
                   confirm: "Remove", destructive: true) {
            if ui.run({ try store.perform { db, _ in try SampleCollection.remove(&db) } }) {
                ui.showToast("Sample collection removed")
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
            .shadow(color: Color(hex: 0x0B4F6C).opacity(0.06), radius: 10, y: 4)
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SettingsIcon(name: icon)
                Toggle(title, isOn: $isOn)
                    .tbFont(15, .semibold)
                    .foregroundColor(.tbText)
                    .tint(.tbTeal)
            }
            .frame(minHeight: 48)
            if !last { Divider().padding(.leading, 48) }
        }
    }
}

struct LinkRow: View {
    let icon: String
    let title: String
    var last = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    SettingsIcon(name: icon)
                    Text(title).tbFont(15, .semibold).foregroundColor(.tbText).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            if !last { Divider().padding(.leading, 48) }
        }
    }
}

struct SettingsIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Color(hex: 0x1592C7))
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color(hex: 0xE0F4F9)))
            .accessibilityHidden(true)
    }
}

/// Reset requires typing DELETE and a final confirmation.
enum ResetFlow {
    @MainActor static func start(ui: AppUI) {
        ui.present { ResetSheet() }
    }
}

struct ResetSheet: View {
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var backup: BackupService
    @EnvironmentObject private var router: Router
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Reset all data") { ui.dismissSheet() }
            Text("This deletes all gear, kits, trips, photos, history, sound settings, your virtual collection and the internal safety copy. Files you exported earlier are not deleted.")
                .tbFont(17).foregroundColor(.tbText).fixedSize(horizontal: false, vertical: true)
            TBTextField(label: "Type DELETE to continue", text: $text, placeholder: "DELETE", capitalization: .characters)
            Button {
                ui.confirm("Delete everything?", message: "This can't be undone.", confirm: "Delete everything", destructive: true) {
                    ui.dismissSheet()
                    do {
                        try backup.resetAll()
                        router.resetAll()
                    } catch {
                        ui.show(error, title: "Couldn't reset")
                    }
                }
            } label: { Text("Delete all data") }
            .buttonStyle(GoldButtonStyle())
            .disabled(text != "DELETE")
            Button("Cancel") { ui.dismissSheet() }.buttonStyle(SoftButtonStyle(height: 50))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

struct AboutView: View {
    @EnvironmentObject private var router: Router

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        HeroScreen(heroHeight: 220) {
            HStack(spacing: 14) {
                CircleIconButton(systemName: "chevron.left", style: .navy, label: "Back") { router.pop() }
                TackleBayLogo(height: 56)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("About").tbDisplay(42).foregroundColor(.tbText).accessibilityAddTraits(.isHeader)
                Text("Tackle Bay is a personal fishing tackle log: what you own, where it lives, what's ready, what went on a trip and what needs care.")
                    .tbFont(18).foregroundColor(.tbText)
                InfoCard(icon: "lock.fill", title: "Works offline", text: "No account, no server, no ads and no analytics. Everything stays on this device.")
                InfoCard(icon: "ticket.fill", title: "Bay Bonus", text: "An optional free extra with decorative miniatures. No purchases, cash prizes or withdrawals.")
                InfoCard(icon: "speaker.wave.2.fill", title: "Sounds", text: "Sound effects were generated with ElevenLabs. They're off until you turn them on in Settings.")
                Text("Version \(version)").tbFont(15).foregroundColor(.tbSecondary)
            }
        }
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let text: String
    var link: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color(hex: 0x15A3B7))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color(hex: 0xE2F5F9)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).tbFont(18, .heavy).foregroundColor(.tbText).accessibilityAddTraits(.isHeader)
                Text(text).tbFont(14).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
                if let link = link, let action = action {
                    Button(action: action) {
                        HStack(spacing: 5) {
                            Text(link).tbFont(15, .semibold)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color(hex: 0x1580D8))
                        .frame(minHeight: 44)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .tbCard(radius: 18, padding: 12)
    }
}
