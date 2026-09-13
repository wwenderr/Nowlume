import Foundation

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let alwaysOnTop = "alwaysOnTop"
        static let reduceAnimations = "reduceAnimations"
    }

    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var reduceAnimations: Bool {
        didSet { UserDefaults.standard.set(reduceAnimations, forKey: Key.reduceAnimations) }
    }

    private init() {
        alwaysOnTop = UserDefaults.standard.bool(forKey: Key.alwaysOnTop)
        reduceAnimations = UserDefaults.standard.bool(forKey: Key.reduceAnimations)
    }
}
