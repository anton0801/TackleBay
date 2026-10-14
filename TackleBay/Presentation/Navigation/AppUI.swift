import SwiftUI

struct AlertAction: Identifiable {
    let id = UUID()
    let title: String
    var role: ButtonRole?
    var action: () -> Void = {}
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let actions: [AlertAction]
}

struct SheetItem: Identifiable {
    let id = UUID()
    let content: AnyView
    var dismissable = true
    var onDismiss: (() -> Void)?
}

/// Shared presentation state: alerts, bottom sheets, toasts, onboarding replay.
@MainActor
final class AppUI: ObservableObject {
    @Published var alert: AlertItem?
    @Published var sheet: SheetItem?
    @Published var toast: String?
    @Published var replayingOnboarding = false
    private var toastWork: DispatchWorkItem?

    func show(_ error: Error, title: String = "Couldn't save") {
        let message = (error as? DomainError)?.message ?? error.localizedDescription
        let heading = (error as? DomainError)?.isConflict == true ? "Please check again" : title
        alert = AlertItem(title: heading, message: message, actions: [AlertAction(title: "OK")])
    }

    func info(_ title: String, _ message: String?) {
        alert = AlertItem(title: title, message: message, actions: [AlertAction(title: "OK")])
    }

    func confirm(_ title: String, message: String?, confirm: String, destructive: Bool = false,
                 cancel: String = "Cancel", action: @escaping () -> Void) {
        alert = AlertItem(title: title, message: message, actions: [
            AlertAction(title: cancel, role: .cancel),
            AlertAction(title: confirm, role: destructive ? .destructive : nil, action: action)
        ])
    }

    /// Runs a throwing action and shows its error. Returns true on success.
    @discardableResult
    func run<T>(_ body: () throws -> T) -> Bool {
        run("Couldn't save", body)
    }

    @discardableResult
    func run<T>(_ title: String, _ body: () throws -> T) -> Bool {
        do {
            _ = try body()
            return true
        } catch {
            show(error, title: title)
            return false
        }
    }

    func present<V: View>(dismissable: Bool = true, onDismiss: (() -> Void)? = nil, @ViewBuilder _ content: () -> V) {
        withAnimation(.easeOut(duration: 0.22)) {
            sheet = SheetItem(content: AnyView(content()), dismissable: dismissable, onDismiss: onDismiss)
        }
    }

    func dismissSheet() {
        let callback = sheet?.onDismiss
        withAnimation(.easeOut(duration: 0.2)) { sheet = nil }
        callback?()
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}

/// Bottom-sheet chrome: rounded light panel with a grabber, drag down to dismiss.
struct SheetHost: View {
    @EnvironmentObject private var ui: AppUI
    @State private var drag: CGFloat = 0
    @Environment(\.safeBottom) private var safeBottom

    var body: some View {
        ZStack(alignment: .bottom) {
            if let sheet = ui.sheet {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture { if sheet.dismissable { ui.dismissSheet() } }
                    .transition(.opacity)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Close")
                VStack(spacing: 0) {
                    Capsule().fill(Color(hex: 0xB9CED8)).frame(width: 48, height: 5).padding(.top, 10).padding(.bottom, 6)
                        .accessibilityHidden(true)
                    sheet.content
                }
                .frame(maxWidth: 600)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xF4FBFE), Color(hex: 0xEAF7FB)], startPoint: .top, endPoint: .bottom))
                        .padding(.bottom, -60)
                        .shadow(color: Color.black.opacity(0.18), radius: 18, y: -4)
                )
                .offset(y: max(0, drag))
                .gesture(
                    DragGesture()
                        .onChanged { v in if sheet.dismissable { drag = v.translation.height } }
                        .onEnded { v in
                            if sheet.dismissable && (v.translation.height > 120 || v.predictedEndTranslation.height > 260) {
                                ui.dismissSheet()
                            }
                            withAnimation(.easeOut(duration: 0.2)) { drag = 0 }
                        }
                )
                .transition(.move(edge: .bottom))
                .id(sheet.id)
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.easeOut(duration: 0.22), value: ui.sheet?.id)
    }
}

struct ToastView: View {
    @EnvironmentObject private var ui: AppUI

    var body: some View {
        VStack {
            if let text = ui.toast {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.tbTurquoise)
                    Text(text).tbFont(16, .semibold).foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.tbNavy.opacity(0.94)))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}
