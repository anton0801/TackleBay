import SwiftUI

@main
struct TackleBayApp: App {
    @StateObject private var services: AppServices
    @StateObject private var router = Router()
    @StateObject private var ui = AppUI()

    init() {
        #if DEBUG
        if let scenario = DebugScenario.requested {
            _services = StateObject(wrappedValue: DebugScenario.services(for: scenario))
            return
        }
        #endif
        _services = StateObject(wrappedValue: AppServices.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
                .environmentObject(services.store)
                .environmentObject(services.backup)
                .environmentObject(router)
                .environmentObject(ui)
                .preferredColorScheme(.light)
                #if DEBUG
                .onAppear { DebugScenario.present(router: router, ui: ui, store: services.store) }
                #endif
        }
    }
}
