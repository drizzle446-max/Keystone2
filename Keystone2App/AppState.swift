import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    enum CurrentTaskColorMode: String, CaseIterable, Identifiable {
        case system
        case black
        case red

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .black:  return "黑色"
            case .red:    return "红色"
            }
        }
    }

    enum Keys {
        static let currentTask     = "currentTask"
        static let showMenuBarText = "showMenuBarText"
        static let currentTaskColorMode = "currentTaskColorMode"
        // MVP-1B
        static let breakEnabled    = "breakEnabled"
        static let focusMinutes    = "focusMinutes"
        static let breakMinutes    = "breakMinutes"
        // MVP-1C
        static let scrollEnabled   = "scrollEnabled"
    }

    @Published var currentTask: String {
        didSet { UserDefaults.standard.set(currentTask, forKey: Keys.currentTask) }
    }

    @Published var showMenuBarText: Bool {
        didSet { UserDefaults.standard.set(showMenuBarText, forKey: Keys.showMenuBarText) }
    }

    @Published var currentTaskColorMode: CurrentTaskColorMode {
        didSet { UserDefaults.standard.set(currentTaskColorMode.rawValue, forKey: Keys.currentTaskColorMode) }
    }

    @Published var breakEnabled: Bool {
        didSet { UserDefaults.standard.set(breakEnabled, forKey: Keys.breakEnabled) }
    }

    @Published var focusMinutes: Int {
        didSet { UserDefaults.standard.set(focusMinutes, forKey: Keys.focusMinutes) }
    }

    @Published var breakMinutes: Int {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: Keys.breakMinutes) }
    }

    @Published var scrollEnabled: Bool {
        didSet { UserDefaults.standard.set(scrollEnabled, forKey: Keys.scrollEnabled) }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.showMenuBarText: true,
            Keys.currentTaskColorMode: CurrentTaskColorMode.system.rawValue,
            Keys.breakEnabled:    true,
            Keys.focusMinutes:    50,
            Keys.breakMinutes:    10,
            Keys.scrollEnabled:   false,
        ])
        currentTask     = UserDefaults.standard.string(forKey: Keys.currentTask) ?? ""
        showMenuBarText = UserDefaults.standard.bool(forKey: Keys.showMenuBarText)
        let colorRaw    = UserDefaults.standard.string(forKey: Keys.currentTaskColorMode) ?? CurrentTaskColorMode.system.rawValue
        currentTaskColorMode = CurrentTaskColorMode(rawValue: colorRaw) ?? .system
        breakEnabled    = UserDefaults.standard.bool(forKey: Keys.breakEnabled)
        focusMinutes    = UserDefaults.standard.integer(forKey: Keys.focusMinutes)
        breakMinutes    = UserDefaults.standard.integer(forKey: Keys.breakMinutes)
        scrollEnabled   = UserDefaults.standard.bool(forKey: Keys.scrollEnabled)
    }
}
