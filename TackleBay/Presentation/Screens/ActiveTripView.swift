import SwiftUI

struct ActiveTripView: View {
    let tripID: UUID
    @EnvironmentObject private var store: TackleStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: AppUI
    @EnvironmentObject private var services: AppServices
    @State private var showMissing = false

    var body: some View {
        if let trip = store.db.trips[tripID] {
            switch trip.status {
            case .active: screen(trip)
            case .returning:
                redirect("Return in progress", "Resume return") { router.replaceTop(with: .returnGear(trip.id)) }
            case .completed, .cancelled:
                redirect("This trip is finished", "Open summary") { router.replaceTop(with: .tripSummary(trip.id)) }
            case .planned:
                redirect("This trip hasn't started", "Open packing") { router.replaceTop(with: .packing(trip.id, applyKit: nil)) }
            }
        } else {
            MissingRecordView(title: "This trip is no longer available")
        }
    }

    private func redirect(_ title: String, _ button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title).tbFont(26, .heavy).foregroundColor(.tbText)
            Button(action: action) { ButtonLabel(title: button, chevron: true) }.buttonStyle(GoldButtonStyle()).padding(.horizontal, 40)
            Spacer()
        }
    }

    private func screen(_ trip: Trip) -> some View {
        let taken = trip.lines.filter { ($0.takenQty ?? 0) > 0 }
        let missing = trip.lines.filter { $0.importance == .required && ($0.takenQty ?? 0) < $0.requiredQty }
        return HeroScreen(heroHeight: 214, heroOverlay: LinearGradient(colors: [Color.black.opacity(0.0), Color(hex: 0x053A66, opacity: 0.5)],
                                                                       startPoint: .center, endPoint: .bottom), overlap: 20, contentTopPadding: 12) {
            ZStack(alignment: .topLeading) {
                Image("tb_gear_rod").resizable().scaledToFit()
                    .frame(width: 210)
                    .rotationEffect(.degrees(-62))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 46, y: -40)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        CircleIconButton(systemName: "chevron.left", style: .glass, size: 38, label: "Back to trips") { router.pop() }
                        TackleBayLogo(height: 46)
                        Spacer()
                    }
                    Spacer(minLength: 0)
                    Text("On the water")
                        .tbDisplay(31)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .accessibilityAddTraits(.isHeader)
                    Text(trip.displayName)
                        .tbFont(19, .bold)
                        .foregroundColor(Color(hex: 0xC9F6FF))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    if let started = trip.startedAt {
                        TimelineView(.periodic(from: Date(), by: 30)) { _ in
                            let now = store.now
                            HStack(spacing: 14) {
                                Label("Started \(Fmt.time(started))", systemImage: "mappin.circle.fill")
                                if now < started {
                                    Label("Check device time", systemImage: "exclamationmark.triangle.fill")
                                } else {
                                    Label(Fmt.duration(now.timeIntervalSince(started)), systemImage: "clock")
                                }
                            }
                            .tbFont(13, .semibold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        }
                        Text("\(trip.displayPlace) · \(Fmt.fullDateTime(started))")
                            .tbFont(11, .medium).foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 26)
            }
        } content: {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Taken with you", size: 21)
                    if taken.isEmpty {
                        Text("Nothing was taken.").tbFont(15).foregroundColor(.tbSecondary)
                    }
                    ForEach(taken) { line in
                        Button { router.push(.gearDetail(line.gearID)) } label: {
                            HStack(spacing: 12) {
                                GearImage(gear: store.db.gear[line.gearID], width: 66, height: 50, corner: 10)
                                Text(TripUseCases.lineName(store.db, line)).tbFont(16, .heavy).foregroundColor(.tbText).lineLimit(2)
                                    .layoutPriority(1)
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("\(line.takenQty ?? 0)").tbFont(19, .heavy).foregroundColor(.tbText)
                                    Text(TripUseCases.lineUnit(store.db, line).text(for: line.takenQty ?? 0)).tbFont(10).foregroundColor(.tbSecondary)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.tbCardBorder, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityElement(children: .combine)
                    }
                }
                .tbCard(radius: 20, fill: Color(hex: 0xF9FDFE), padding: 10)

                if !missing.isEmpty || trip.missingItemsNote != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { withAnimation(.easeOut(duration: 0.2)) { showMissing.toggle() } } label: {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill").foregroundColor(Color(hex: 0xE58A13))
                                Text("Left at home (\(missing.count))").tbFont(15, .bold).foregroundColor(.tbText)
                                Spacer()
                                Image(systemName: showMissing ? "chevron.up" : "chevron.down").foregroundColor(.tbText)
                            }
                            .frame(minHeight: 44)
                        }
                        if showMissing {
                            ForEach(missing) { line in
                                Text("\(TripUseCases.lineName(store.db, line)) — \(line.takenQty ?? 0) of \(line.requiredQty) taken")
                                    .tbFont(14).foregroundColor(.tbText)
                            }
                            if let note = trip.missingItemsNote {
                                Text("“\(note)”").italic().tbFont(14).foregroundColor(.tbSecondary)
                            }
                        }
                    }
                    .tbCard(radius: 16, fill: Color(hex: 0xFFF8E8), padding: 10)
                }

                if let note = trip.note {
                    NoteCard(title: "Plan note", text: note)
                }
                ForEach(trip.liveNotes) { note in
                    NoteCard(title: Fmt.dayTime(note.createdAt, now: store.now), text: note.text)
                }
                Button(action: addNote) {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: 0x1A6E92))
                            .frame(width: 42, height: 42).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xDDF3F8)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Add note").tbFont(16, .bold).foregroundColor(.tbText)
                            Text("Jot down conditions, spots or reminders.").tbFont(12).foregroundColor(.tbSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.tbText)
                    }
                    .tbCard(radius: 16, padding: 10)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { returnGear(trip) } label: { ButtonLabel(title: "Return gear", chevron: true) }
                    .buttonStyle(GoldButtonStyle())
            }
        }
    }

    private func addNote() {
        ui.present {
            NoteSheet(title: "Add note", placeholder: "Conditions, spots or reminders", limit: 2000, minLength: 1) { text in
                if ui.run({ try store.perform { db, now in try TripUseCases.addLiveNote(&db, tripID: tripID, text: text, now: now) } }) {
                    ui.dismissSheet()
                }
            }
        }
    }

    private func returnGear(_ trip: Trip) {
        if ui.run({ try store.perform { db, now in try TripUseCases.beginReturn(&db, tripID: trip.id, now: now) } }) {
            services.tapFeedback()
            router.replaceTop(with: .returnGear(trip.id))
        }
    }
}

struct NoteCard: View {
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text").font(.system(size: 15, weight: .semibold)).foregroundColor(Color(hex: 0x1A6E92))
                .frame(width: 34, height: 34).background(Circle().fill(Color.tbIceTile))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tbFont(12, .semibold).foregroundColor(.tbSecondary)
                Text(text).tbFont(14).foregroundColor(.tbText).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .tbCard(radius: 16, fill: Color(hex: 0xEAF6FB), padding: 10)
        .accessibilityElement(children: .combine)
    }
}

struct NoteSheet: View {
    let title: String
    let placeholder: String
    let limit: Int
    var minLength = 0
    var initial = ""
    let onSave: (String) -> Void
    @State private var text = ""
    @State private var loaded = false
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: title) { ui.dismissSheet() }
            TBTextEditor(text: $text, placeholder: placeholder, minHeight: 140, limit: limit)
            Button { onSave(text) } label: { Text("Save") }
                .buttonStyle(GoldButtonStyle())
                .disabled(TextRules.trimmed(text).count < minLength)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear { if !loaded { loaded = true; text = initial } }
    }
}
