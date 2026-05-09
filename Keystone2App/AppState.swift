import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    enum CurrentTaskColorMode: String, CaseIterable, Identifiable {
        case red
        case yellow
        case green
        case black

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .red:    return "红色"
            case .yellow: return "黄色"
            case .green:  return "绿色"
            case .black:  return "黑色"
            }
        }

        static func normalized(rawValue: String) -> CurrentTaskColorMode {
            rawValue == "system" ? .black : (CurrentTaskColorMode(rawValue: rawValue) ?? .red)
        }
    }

    enum Keys {
        static let currentTask     = "currentTask"
        static let showMenuBarText = "showMenuBarText"
        static let currentTaskColorMode = "currentTaskColorMode"
        // MVP-1B
        static let breakEnabled    = "breakEnabled"
        static let focusMinutes    = "focusMinutes"
        // MVP-1C
        static let scrollEnabled   = "scrollEnabled"
        // v1.0.x 菜单栏显示节奏
        static let breakHintText          = "breakHintText"
        static let taskDisplaySeconds     = "taskDisplaySeconds"
        static let elapsedDisplaySeconds  = "elapsedDisplaySeconds"
        static let hintDisplaySeconds     = "hintDisplaySeconds"
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

    @Published var scrollEnabled: Bool {
        didSet { UserDefaults.standard.set(scrollEnabled, forKey: Keys.scrollEnabled) }
    }

    @Published var breakHintText: String {
        didSet { UserDefaults.standard.set(breakHintText, forKey: Keys.breakHintText) }
    }
    @Published var taskDisplaySeconds: Int {
        didSet { UserDefaults.standard.set(taskDisplaySeconds, forKey: Keys.taskDisplaySeconds) }
    }
    @Published var elapsedDisplaySeconds: Int {
        didSet { UserDefaults.standard.set(elapsedDisplaySeconds, forKey: Keys.elapsedDisplaySeconds) }
    }
    @Published var hintDisplaySeconds: Int {
        didSet { UserDefaults.standard.set(hintDisplaySeconds, forKey: Keys.hintDisplaySeconds) }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.showMenuBarText: true,
            Keys.currentTaskColorMode: CurrentTaskColorMode.red.rawValue,
            Keys.breakEnabled:    true,
            Keys.focusMinutes:    50,
            Keys.scrollEnabled:   false,
            Keys.breakHintText:          "该休息了",
            Keys.taskDisplaySeconds:     8,
            Keys.elapsedDisplaySeconds:  2,
            Keys.hintDisplaySeconds:     2,
        ])
        currentTask     = UserDefaults.standard.string(forKey: Keys.currentTask) ?? ""
        showMenuBarText = UserDefaults.standard.bool(forKey: Keys.showMenuBarText)
        let colorRaw    = UserDefaults.standard.string(forKey: Keys.currentTaskColorMode) ?? CurrentTaskColorMode.red.rawValue
        currentTaskColorMode = CurrentTaskColorMode.normalized(rawValue: colorRaw)
        breakEnabled    = UserDefaults.standard.bool(forKey: Keys.breakEnabled)
        focusMinutes    = UserDefaults.standard.integer(forKey: Keys.focusMinutes)
        scrollEnabled   = UserDefaults.standard.bool(forKey: Keys.scrollEnabled)
        breakHintText         = UserDefaults.standard.string(forKey: Keys.breakHintText) ?? "该休息了"
        taskDisplaySeconds    = UserDefaults.standard.integer(forKey: Keys.taskDisplaySeconds)
        elapsedDisplaySeconds = UserDefaults.standard.integer(forKey: Keys.elapsedDisplaySeconds)
        hintDisplaySeconds    = UserDefaults.standard.integer(forKey: Keys.hintDisplaySeconds)
    }
}
