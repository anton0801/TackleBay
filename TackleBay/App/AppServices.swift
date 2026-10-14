import Combine
import SwiftUI
import UIKit

final class Haptics {
    var enabled = true

    func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// Composition root: wires Data services into Presentation. Dependencies are passed explicitly.
@MainActor
final class AppServices: ObservableObject {
    let store: TackleStore
    let backup: BackupService
    let audio = AudioCoordinator()
    let haptics = Haptics()
    private var bag: Set<AnyCancellable> = []

    init(store: TackleStore) {
        self.store = store
        backup = BackupService(store: store)
        store.$db
            .map(\.settings)
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.haptics.enabled = settings.haptics
                self?.audio.effectsEnabled = settings.soundEffects
                self?.audio.ambienceEnabled = settings.bonusAmbience
            }
            .store(in: &bag)
    }

    static func live() -> AppServices {
        let store = TackleStore(rootURL: TackleStore.defaultRoot(), clock: SystemTimeProvider(), random: SecureRandomSource())
        store.load()
        return AppServices(store: store)
    }

    /// UI sound + haptic for important manual buttons.
    func tapFeedback() {
        audio.play(.uiTap)
        haptics.tap()
    }
}
