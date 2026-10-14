import AVFoundation
import SwiftUI

/// Measured transparent windows of tb_reel_frame (integration/reel_windows.json).
enum ReelGeometry {
    static let windows: [CGRect] = [
        CGRect(x: 0.137161, y: 0.217703, width: 0.212919, height: 0.560606),
        CGRect(x: 0.392344, y: 0.217703, width: 0.212919, height: 0.560606),
        CGRect(x: 0.647528, y: 0.217703, width: 0.212121, height: 0.560606)
    ]
    /// Masks run slightly under the frame so no seam shows (inset 4 px of 1254 in the source).
    static let bleed: CGFloat = 0.006

    static func window(_ i: Int, size: CGFloat) -> CGRect {
        let n = windows[i]
        return CGRect(x: (n.minX - bleed) * size, y: (n.minY - bleed) * size,
                      width: (n.width + bleed * 2) * size, height: (n.height + bleed * 2) * size)
    }
}

struct BayBonusView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.safeTop) private var safeTop

    enum Phase: Equatable {
        case idle
        case spinning(UUID)
        case result(UUID)
    }

    @State private var phase: Phase = .idle
    @State private var positions: [Double] = [0, 2, 0]
    @State private var castOperationID: UUID?
    @State private var claimOperationID: UUID?
    @State private var scheduled: [DispatchWorkItem] = []
    @State private var spinPlayer: AVAudioPlayer?
    @State private var symbolOpacity: Double = 1
    @State private var appeared = false

    private var db: TBDatabase { store.db }

    var body: some View {
        Group {
            if BonusUseCases.isCollectionComplete(db) && BonusUseCases.pendingReceipt(db) == nil && phase == .idle {
                BonusCompleteView()
            } else {
                scene
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear { cancelScheduled() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { finishAnimationNow() }
        }
    }

    // MARK: Scene

    private var scene: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, 460)
            let frameSize = min(width - 24, 370)
            ZStack {
                Image("tb_bonus_underwater")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height + safeTop + 40)
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        sign(width: width)
                            .padding(.top, 26)
                            .overlay(alignment: .topLeading) {
                                CircleIconButton(systemName: "chevron.left", style: .glass, size: 38, label: "Back") { router.pop() }
                                    .padding(.leading, 12)
                            }
                        balanceBar(width: width)
                            .padding(.top, -2)
                        reels(frameSize: frameSize)
                            .padding(.top, -frameSize * 0.12)
                        if case .result(let id) = phase, let receipt = db.receipts[id] {
                            resultPlaque(receipt, width: width)
                                .padding(.top, -frameSize * 0.24)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            castControls(width: width)
                                .padding(.top, -frameSize * 0.13)
                            bottomPanel
                                .padding(.top, 10)
                        }
                    }
                    .frame(width: width)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.tbNavy.ignoresSafeArea())
    }

    private func sign(width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            PelicanPeek(width: width * 0.4)
                .offset(x: -width * 0.01, y: -width * 0.11)
            ZStack {
                Image("tb_bonus_plaque_clean").resizable().scaledToFit()
                    .accessibilityHidden(true)
                BayBonusTitle(size: width * 0.115)
                    .offset(x: -width * 0.02, y: width * 0.0)
            }
            .frame(width: width * 0.82)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, width * 0.04)
        }
        .frame(height: width * 0.32)
    }

    /// While the reels spin, the bar shows the balance before this cast so the stored result isn't revealed early.
    private var shownParts: Int {
        if case .spinning(let id) = phase, let r = db.receipts[id] { return db.wallet.parts - r.rewardParts }
        return db.wallet.parts
    }

    private func balanceBar(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("tb_bonus_ticket").resizable().scaledToFit().frame(width: 46, height: 32).accessibilityHidden(true)
                (Text("\(db.wallet.tickets) ").foregroundColor(Color(hex: 0xFFD54F)) + Text(db.wallet.tickets == 1 ? "ticket" : "tickets").foregroundColor(.white))
                    .tbFont(20, .heavy)
            }
            Rectangle().fill(Color(hex: 0xC9881A)).frame(width: 2, height: 30)
            HStack(spacing: 8) {
                Image("icon_parts").renderingMode(.template).resizable().scaledToFit().frame(width: 28, height: 28)
                    .foregroundColor(Color(hex: 0xE8EEF2)).accessibilityHidden(true)
                (Text("\(shownParts) ").foregroundColor(Color(hex: 0x5CE6F2)) + Text(shownParts == 1 ? "Part" : "Parts").foregroundColor(.white))
                    .tbFont(20, .heavy)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .background(
            Capsule().fill(LinearGradient(colors: [Color(hex: 0x6B3F1C), Color(hex: 0x40230D)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color(hex: 0xF3C35A), Color(hex: 0xA8701A)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .zIndex(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Fmt.tickets(db.wallet.tickets)), \(Fmt.parts(shownParts))")
    }

    // MARK: Reels

    private func reels(frameSize: CGFloat) -> some View {
        let f = frameSize
        let w0 = ReelGeometry.window(0, size: f)
        let w2 = ReelGeometry.window(2, size: f)
        let cell = ReelGeometry.window(0, size: f).height / 3
        let centerY = w0.minY + cell
        return ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                let rect = ReelGeometry.window(i, size: f)
                ReelStrip(position: positions[i], cellHeight: rect.height / 3, symbolSize: min(rect.width * 1.38, rect.height / 3 * 1.5))
                    .opacity(symbolOpacity)
                    .frame(width: rect.width, height: rect.height)
                    .background(ReelDrum())
                    .clipShape(RoundedRectangle(cornerRadius: rect.width * 0.12, style: .continuous))
                    .offset(x: rect.minX, y: rect.minY)
            }
            Image("tb_reel_frame").resizable().scaledToFit().frame(width: f, height: f)
                .accessibilityHidden(true)
            // Centre scoring row: the only line that counts.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: 0x6DF6FF), lineWidth: 3)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x6DF6FF).opacity(0.07)))
                .shadow(color: Color(hex: 0x29E3F2), radius: 8)
                .shadow(color: Color(hex: 0x29E3F2).opacity(0.7), radius: 3)
                .frame(width: w2.maxX - w0.minX + f * 0.02, height: cell)
                .offset(x: w0.minX - f * 0.01, y: centerY)
                .accessibilityHidden(true)
            Pointer()
                .fill(LinearGradient(colors: [Color(hex: 0xFFE08A), Color(hex: 0xC98A1E)], startPoint: .top, endPoint: .bottom))
                .overlay(Pointer().stroke(Color(hex: 0x5A3510), lineWidth: 1.5))
                .frame(width: f * 0.07, height: f * 0.09)
                .offset(x: w0.minX - f * 0.1, y: centerY + cell / 2 - f * 0.045)
                .accessibilityHidden(true)
            Pointer()
                .fill(LinearGradient(colors: [Color(hex: 0xFFE08A), Color(hex: 0xC98A1E)], startPoint: .top, endPoint: .bottom))
                .overlay(Pointer().stroke(Color(hex: 0x5A3510), lineWidth: 1.5))
                .frame(width: f * 0.07, height: f * 0.09)
                .scaleEffect(x: -1, y: 1)
                .offset(x: w2.maxX + f * 0.03, y: centerY + cell / 2 - f * 0.045)
                .accessibilityHidden(true)
        }
        .frame(width: f, height: f)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reelsAccessibilityLabel)
    }

    private var reelsAccessibilityLabel: String {
        let centre = positions.map { BonusRules.strip[mod(Int(($0).rounded()), 6)].title }
        return "Reels. Centre row: \(centre.joined(separator: ", "))"
    }

    // MARK: Cast & claim

    private func castControls(width: CGFloat) -> some View {
        let castReason = BonusUseCases.castBlockReason(db)
        let castEnabled = castReason == nil && phase == .idle
        let claim = BonusUseCases.claimState(db, now: store.now)
        return VStack(spacing: 10) {
            Button(action: cast) {
                ZStack {
                    Image("tb_bonus_button").resizable().scaledToFit()
                    HStack(spacing: width * 0.03) {
                        Splash().stroke(Color(hex: 0x1A9FC0), style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 22, height: 24)
                        Text("CAST")
                            .font(.system(size: width * 0.13, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: 0x0E2C47))
                            .kerning(1)
                        Splash().stroke(Color(hex: 0x1A9FC0), style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 22, height: 24)
                            .scaleEffect(x: -1, y: 1)
                    }
                    .offset(y: -width * 0.005)
                }
                .frame(width: min(width * 0.86, 340))
                .saturation(castEnabled ? 1 : 0.35)
                .brightness(castEnabled ? 0 : -0.28)
            }
            .buttonStyle(PressableStyle())
            .disabled(!castEnabled)
            .accessibilityLabel("Cast")
            .accessibilityHint(castReason ?? "Uses 1 free ticket")

            if case .spinning = phase {
                Button("Skip animation", action: skipAnimation)
                    .tbFont(16, .semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
            } else {
                statusText(castReason: castReason, claim: claim)
            }
            if claim == .available && phase == .idle {
                Button(action: claimTicket) {
                    HStack(spacing: 10) {
                        Image("tb_bonus_ticket").resizable().scaledToFit().frame(width: 40, height: 28).accessibilityHidden(true)
                        Text("Claim free ticket").tbFont(19, .heavy).foregroundColor(.white)
                    }
                    .padding(.horizontal, 22)
                    .frame(minHeight: 52)
                    .background(Capsule().fill(Color(hex: 0x0A3D66).opacity(0.92)))
                    .overlay(Capsule().strokeBorder(Color(hex: 0xFFD54F), lineWidth: 2))
                    .shadow(color: Color(hex: 0xFFD54F).opacity(0.35), radius: 8)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder private func statusText(castReason: String?, claim: ClaimState) -> some View {
        VStack(spacing: 4) {
            if db.wallet.tickets > 0 && castReason == nil {
                (Text("Uses ") + Text("1").foregroundColor(Color(hex: 0xFFD54F)) + Text(" free ticket"))
                    .tbFont(21, .bold).foregroundColor(.white)
            }
            switch claim {
            case .cooldown(let until):
                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                    let remaining = until.timeIntervalSince(BonusUseCases.effectiveNow(db, now: store.now))
                    Text("Next free ticket in \(Fmt.countdown(remaining))").tbFont(db.wallet.tickets > 0 ? 16 : 21, .bold).foregroundColor(.white)
                        .monospacedDigit()
                        .onChange(of: remaining <= 0) { done in if done { store.objectWillChange.send() } }
                }
                if db.wallet.tickets == 0 {
                    Text("One free ticket every 24 hours.").tbFont(15).foregroundColor(.tbBonusSecondary)
                }
            case .storageFull:
                Text("Ticket storage is full. \(BonusRules.fullText)").tbFont(15, .semibold).foregroundColor(.tbBonusSecondary)
            case .checkDeviceTime:
                Text("Check your device date and time").tbFont(16, .bold).foregroundColor(Color(hex: 0xFFD54F))
            case .limitReached:
                Text("Bonus limit reached").tbFont(16, .bold).foregroundColor(.tbBonusSecondary)
            case .collectionComplete:
                Text(BonusRules.completedText).tbFont(15, .semibold).foregroundColor(.tbBonusSecondary).multilineTextAlignment(.center)
            case .available:
                EmptyView()
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
    }

    private var bottomPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                panelLink("My Showcase", icon: "rosette") { router.push(.showcase) }
                Divider().frame(height: 44)
                panelLink("How it works", icon: "doc.text.fill") { showText("How it works", BonusRules.howItWorksText) }
                Divider().frame(height: 44)
                panelLink("Odds", icon: "chart.bar.fill") { showOdds() }
            }
            Text("Virtual rewards only. \(BonusRules.footerText)")
                .tbFont(11).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 40)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0xF4FBFE))
                .padding(.bottom, -400)
        )
    }

    private func panelLink(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 21, weight: .semibold)).foregroundColor(Color(hex: 0x1580A8))
                HStack(spacing: 3) {
                    Text(title).tbFont(13, .bold).lineLimit(1).minimumScaleFactor(0.75)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                }
                .foregroundColor(.tbText)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Result

    /// Result plaque under the reels; the reels above keep showing the three stored centre symbols.
    private func resultPlaque(_ receipt: CastReceipt, width: CGFloat) -> some View {
        let outcome = BonusRules.outcome(receipt.symbols)
        return VStack(spacing: 10) {
            (Text("\(receipt.rewardParts) ").foregroundColor(Color(hex: 0x2EE6F2)) + Text(receipt.rewardParts == 1 ? "Part collected" : "Parts collected").foregroundColor(.white))
                .tbFont(32, .heavy, max: 42)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .padding(.top, 8)
            Text(outcome.explanation).tbFont(17, .semibold).foregroundColor(Color(hex: 0xBDE9F5))
            HStack(spacing: 12) {
                Image(systemName: "briefcase.fill").font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: 0x18A7C9))
                    .frame(width: 46, height: 46).background(Circle().fill(Color(hex: 0xDDF3F8))).accessibilityHidden(true)
                Text("Parts balance").tbFont(18, .bold).foregroundColor(.tbText)
                Spacer()
                Text("\(db.wallet.parts)").tbFont(30, .heavy).foregroundColor(.tbText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
            .accessibilityElement(children: .combine)
            Button { finishResult(openShowcase: false) } label: { ButtonLabel(title: "Continue", chevron: true) }
                .buttonStyle(GoldButtonStyle(height: 50))
            Button { finishResult(openShowcase: true) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "photo").foregroundColor(Color(hex: 0x1580A8))
                    Text("My Showcase")
                }
            }
            .buttonStyle(OutlineButtonStyle(height: 48, tint: Color(hex: 0x9ED8EA)))
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 40)
        .frame(width: width)
        .background(
            ResultPlaque()
                .fill(LinearGradient(colors: [Color(hex: 0x0D3F6E), Color(hex: 0x062B4F)], startPoint: .top, endPoint: .bottom))
                .overlay(ResultPlaque().stroke(LinearGradient(colors: [Color(hex: 0xF6CF6A), Color(hex: 0xB07A1C)], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                .padding(.bottom, -300)
                .shadow(color: .black.opacity(0.45), radius: 16, y: -4)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You collected \(Fmt.parts(receipt.rewardParts)). Centre symbols: \(receipt.symbols.map(\.title).joined(separator: ", ")).")
    }

    // MARK: Behaviour

    private func onAppear() {
        try? store.perform { db, now in BonusUseCases.observe(&db, now: now) }
        guard !appeared else { return }
        appeared = true
        if let pending = BonusUseCases.pendingReceipt(db) {
            // Cold start or return with an unopened result: show the same stored result, no new draw.
            setPositions(pending.symbols)
            phase = .result(pending.id)
        } else if let last = db.receipts.values.max(by: { $0.sequence < $1.sequence }) {
            setPositions(last.symbols)
        }
    }

    private func setPositions(_ symbols: [SymbolID]) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            positions = symbols.map { Double(BonusRules.strip.firstIndex(of: $0) ?? 0) }
        }
    }

    private func claimTicket() {
        let opID = claimOperationID ?? UUID()
        claimOperationID = opID
        do {
            try store.perform { db, now in try BonusUseCases.claim(&db, operationID: opID, now: now) }
            claimOperationID = nil
            services.audio.play(.ticketClaim)
            services.haptics.success()
        } catch {
            claimOperationID = nil
            ui.show(error, title: "No ticket claimed")
        }
    }

    /// The receipt is committed first; the animation only reveals the stored symbols.
    private func cast() {
        guard phase == .idle else { return }
        let opID = castOperationID ?? UUID()
        castOperationID = opID
        let receipt: CastReceipt
        do {
            receipt = try store.perform { db, now in
                try BonusUseCases.cast(&db, operationID: opID, random: store.random, now: now)
            }
        } catch {
            ui.alert = AlertItem(title: "Cast not saved", message: "\((error as? DomainError)?.message ?? error.localizedDescription) No ticket was used.",
                                 actions: [AlertAction(title: "Cancel", role: .cancel) { castOperationID = nil },
                                           AlertAction(title: "Retry") { cast() }])
            return
        }
        castOperationID = nil
        services.tapFeedback()
        animate(to: receipt)
    }

    private func animate(to receipt: CastReceipt) {
        phase = .spinning(receipt.id)
        let targets = receipt.symbols.map { BonusRules.strip.firstIndex(of: $0) ?? 0 }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) { symbolOpacity = 0 }
            schedule(after: 0.12) {
                setPositions(receipt.symbols)
                withAnimation(.easeIn(duration: 0.12)) { symbolOpacity = 1 }
            }
            schedule(after: 0.25) { showResult(receipt) }
            return
        }
        spinPlayer = services.audio.play(.reelSpin)
        var lastStop: Double = 0
        for i in 0..<3 {
            let current = positions[i]
            let currentIndex = mod(Int(current.rounded()), 6)
            let back = mod(currentIndex - targets[i], 6)
            let final = current.rounded() - Double(6 * (3 + i) + back)
            let duration = 1.86 + 0.18 * Double(i)
            lastStop = duration
            withAnimation(.timingCurve(0.12, 0.55, 0.22, 1.0, duration: duration)) { positions[i] = final }
            schedule(after: duration) {
                services.audio.play(.reelStop)
                services.haptics.tap()
            }
        }
        schedule(after: lastStop + 0.15) { showResult(receipt) }
    }

    private func schedule(after seconds: Double, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        scheduled.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelScheduled() {
        scheduled.forEach { $0.cancel() }
        scheduled = []
    }

    private func skipAnimation() {
        finishAnimationNow()
    }

    /// Skip, background or leaving: jump straight to the already stored result.
    private func finishAnimationNow() {
        guard case .spinning(let id) = phase, let receipt = db.receipts[id] else { return }
        cancelScheduled()
        services.audio.fadeOut(spinPlayer)
        symbolOpacity = 1
        setPositions(receipt.symbols)
        showResult(receipt)
    }

    private func showResult(_ receipt: CastReceipt) {
        cancelScheduled()
        setPositions(receipt.symbols)
        services.audio.play(.partsReceived)
        services.haptics.success()
        withAnimation(.easeOut(duration: 0.22)) { phase = .result(receipt.id) }
    }

    private func finishResult(openShowcase: Bool) {
        guard case .result(let id) = phase else { return }
        try? store.perform { db, now in BonusUseCases.markPresented(&db, receiptID: id, now: now) }
        withAnimation(.easeOut(duration: 0.2)) { phase = .idle }
        if openShowcase { router.push(.showcase) }
    }

    private func showText(_ title: String, _ text: String) {
        ui.present {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: title) { ui.dismissSheet() }
                Text(text).tbFont(18).foregroundColor(.tbText).fixedSize(horizontal: false, vertical: true)
                Button("Got it") { ui.dismissSheet() }.buttonStyle(GoldButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func showOdds() {
        ui.present {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: "Probabilities") { ui.dismissSheet() }
                OddsTable()
                Text(BonusRules.probabilitiesText).tbFont(16).foregroundColor(.tbSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Got it") { ui.dismissSheet() }.buttonStyle(GoldButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

/// One vertical reel. Symbol j of the infinite strip sits at y = (j − position) × cell; above = previous, below = next.
struct ReelStrip: View, Animatable {
    var position: Double
    let cellHeight: CGFloat
    let symbolSize: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        let base = Int(floor(position))
        ZStack {
            ForEach((base - 2)...(base + 3), id: \.self) { j in
                let y = CGFloat(Double(j) - position) * cellHeight
                let distance = min(abs(y) / cellHeight, 1.5)
                Image(BonusRules.strip[mod(j, BonusRules.strip.count)].assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: symbolSize, height: symbolSize)
                    .saturation(1 - Double(min(distance, 1)) * 0.2)
                    .opacity(1 - Double(min(distance, 1)) * 0.22)
                    .offset(y: y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Light drum behind the symbols with cylinder shading (UI, per handoff notes).
struct ReelDrum: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xBDB4A2), Color(hex: 0xEDE7DA), Color(hex: 0xFFFDF8), Color(hex: 0xEDE7DA), Color(hex: 0xBDB4A2)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(LinearGradient(colors: [Color.black.opacity(0.12), .clear, Color.black.opacity(0.12)], startPoint: .leading, endPoint: .trailing))
    }
}

struct Pointer: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Splash: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.45), control: CGPoint(x: r.midX, y: r.minY))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.2))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.1), control: CGPoint(x: r.midX, y: r.midY))
        return p
    }
}

/// Navy result panel with a raised centre on its top edge.
struct ResultPlaque: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.minY + 26
        p.move(to: CGPoint(x: r.minX, y: top + 30))
        p.addQuadCurve(to: CGPoint(x: r.minX + 30, y: top), control: CGPoint(x: r.minX, y: top))
        p.addLine(to: CGPoint(x: r.midX - 60, y: top))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.midX - 30, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX + 60, y: top), control: CGPoint(x: r.midX + 30, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 30, y: top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: top + 30), control: CGPoint(x: r.maxX, y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct OddsTable: View {
    var body: some View {
        VStack(spacing: 0) {
            row("3 matching:", "3 Parts", "1 in 36")
            Divider()
            row("2 matching:", "2 Parts", "5 in 12")
            Divider()
            row("All different:", "1 Part", "5 in 9")
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xEAF5F9)))
    }

    private func row(_ a: String, _ b: String, _ c: String) -> some View {
        HStack {
            Text(a).tbFont(15, .bold).foregroundColor(.tbText)
            Spacer()
            Text("\(b)  ·  \(c)").tbFont(15, .semibold).foregroundColor(.tbText)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// 4 of 4 built: Claim and Cast stop; tickets and Parts are kept.
struct BonusCompleteView: View {
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router

    var body: some View {
        HeroScreen(heroHeight: 470) {
            ZStack(alignment: .topLeading) {
                PelicanKeeper(height: 330)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, -10)
                    .padding(.bottom, 120)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        CircleIconButton(systemName: "chevron.left", style: .light, label: "Back") { router.pop() }
                        TackleBayLogo(height: 56)
                    }
                    .padding(.top, 6)
                    Text("Your bay collection is complete.")
                        .tbDisplay(38)
                        .foregroundColor(.tbText)
                        .frame(maxWidth: 230, alignment: .leading)
                        .shadow(color: .white.opacity(0.7), radius: 6)
                        .accessibilityAddTraits(.isHeader)
                    Text("Enjoy your miniatures on My Bay.").tbFont(19, .semibold).foregroundColor(.tbText)
                        .frame(maxWidth: 210, alignment: .leading)
                }
                .padding(.horizontal, 16)
                Shelf()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 8)
                    .padding(.bottom, Metrics.sheetOverlap - 18)
            }
        } content: {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    StatTile(value: store.db.wallet.tickets, title: "Tickets", icon: "ticket.fill", tint: Color(hex: 0x18A7C9), tileColor: Color(hex: 0xDDF3F8))
                    StatTile(value: store.db.wallet.parts, title: "Parts", icon: "gearshape.fill", tint: Color(hex: 0x18A7C9), tileColor: Color(hex: 0xDDF3F8))
                }
                Button { router.push(.showcase) } label: { ButtonLabel(title: "View my showcase", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
                Text("Claim and Cast are paused because every miniature is built. Your tickets and Parts stay with you.")
                    .tbFont(15).foregroundColor(.tbSecondary).multilineTextAlignment(.center)
            }
            .padding(.top, 10)
        }
    }
}

/// Wooden shelf with the four built miniatures (code-drawn shelf, delivered miniature art).
struct Shelf: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x9B5A2C), Color(hex: 0x6D3A17)], startPoint: .top, endPoint: .bottom))
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0x4E2A10), lineWidth: 2))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xB86F38), Color(hex: 0x7E431B)], startPoint: .top, endPoint: .bottom))
                .frame(height: 34)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
            HStack(spacing: 4) {
                ForEach(BonusRules.collectibles, id: \.id) { c in
                    VStack(spacing: 4) {
                        Image(c.assetName).resizable().scaledToFit().frame(height: 96)
                        RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(hex: 0xF3D27A), Color(hex: 0xB98A2A)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 50, height: 12)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 26)
        }
        .accessibilityElement()
        .accessibilityLabel("All four miniatures on the shelf")
    }
}
