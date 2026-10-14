import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, gear, trips, kits
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "My Bay"
        case .gear: return "Gear"
        case .trips: return "Trips"
        case .kits: return "My Kits"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .gear: return "briefcase.fill"
        case .trips: return "calendar"
        case .kits: return "case.fill"
        }
    }
}

enum GearEditorMode: Hashable {
    case new
    case edit(UUID)
}

enum KitEditorMode: Hashable {
    case new(addGear: UUID?)
    case edit(UUID, addGear: UUID?)
    case duplicate(UUID)
}

enum TripEditorMode: Hashable {
    case new(kitID: UUID?)
    case edit(UUID)
    case repeatTrip(UUID)
}

enum Route: Hashable {
    case gearDetail(UUID)
    case gearEditor(GearEditorMode)
    case adjustStock(UUID, operation: AdjustOperation?, tripID: UUID?)
    case kitEditor(KitEditorMode)
    case tripEditor(TripEditorMode)
    case packing(UUID, applyKit: UUID?)
    case activeTrip(UUID)
    case returnGear(UUID)
    case tripSummary(UUID)
    case needsCare(tripID: UUID?)
    case bonus
    case showcase
    case settings
    case backup
    case privacy
    case about

    /// Forms keep their own Cancel with a discard confirmation, so the edge swipe is off there.
    var allowsSwipeBack: Bool {
        switch self {
        case .gearEditor, .kitEditor, .tripEditor, .adjustStock, .returnGear: return false
        default: return true
        }
    }
}

struct RouteEntry: Identifiable, Equatable {
    let id = UUID()
    let route: Route
}

/// Per-tab navigation stacks. Each tab keeps its own path; Back always returns to the source.
@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .home
    @Published private(set) var stacks: [AppTab: [RouteEntry]] = [:]
    var reduceMotion = false

    private var animation: Animation? { reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.22) }

    func entries(_ tab: AppTab) -> [RouteEntry] { stacks[tab] ?? [] }
    var currentEntries: [RouteEntry] { entries(tab) }
    var topRoute: Route? { currentEntries.last?.route }

    func push(_ route: Route) {
        withAnimation(animation) { stacks[tab, default: []].append(RouteEntry(route: route)) }
    }

    func pop(animated: Bool = true) {
        guard !(stacks[tab] ?? []).isEmpty else { return }
        if animated {
            withAnimation(animation) { _ = stacks[tab]?.removeLast() }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { _ = stacks[tab]?.removeLast() }
        }
    }

    func popToRoot() {
        withAnimation(animation) { stacks[tab] = [] }
    }

    /// Replaces the top screen (e.g. editor → saved detail) so Back goes to the original source.
    func replaceTop(with route: Route) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            var list = stacks[tab] ?? []
            if !list.isEmpty { list.removeLast() }
            list.append(RouteEntry(route: route))
            stacks[tab] = list
        }
    }

    /// Pops screens above the first match of `predicate`, then pushes `route`.
    func popTo(where predicate: (Route) -> Bool, thenPush route: Route? = nil) {
        withAnimation(animation) {
            var list = stacks[tab] ?? []
            while let last = list.last, !predicate(last.route) { list.removeLast() }
            if let route = route { list.append(RouteEntry(route: route)) }
            stacks[tab] = list
        }
    }

    func select(_ newTab: AppTab) {
        if newTab == tab {
            popToRoot()
        } else {
            tab = newTab
        }
    }

    func resetAll() {
        stacks = [:]
        tab = .home
    }
}
