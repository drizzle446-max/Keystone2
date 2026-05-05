import Carbon
import AppKit
import Combine

// MARK: - HotkeyBinding

struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// 从录制事件构造；NSEvent modifier flags → Carbon modifier bits 显式映射
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let kc = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        self.keyCode = kc
        self.carbonModifiers = mods
    }

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_F1:         return "F1"
        case kVK_F2:         return "F2"
        case kVK_F3:         return "F3"
        case kVK_F4:         return "F4"
        case kVK_F5:         return "F5"
        case kVK_F6:         return "F6"
        case kVK_F7:         return "F7"
        case kVK_F8:         return "F8"
        case kVK_F9:         return "F9"
        case kVK_F10:        return "F10"
        case kVK_F11:        return "F11"
        case kVK_F12:        return "F12"
        case kVK_Space:      return "Space"
        case kVK_Return:     return "↩"
        case kVK_Tab:        return "⇥"
        case kVK_Delete:     return "⌫"
        case kVK_Escape:     return "⎋"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        default:             return "Key(\(keyCode))"
        }
    }
}

// MARK: - HotkeyAction 默认绑定

extension HotkeyAction {
    var defaultBinding: HotkeyBinding {
        switch self {
        case .screenshot:     return HotkeyBinding(keyCode: UInt32(kVK_F1), carbonModifiers: 0)
        case .screenshotCopy: return HotkeyBinding(keyCode: UInt32(kVK_F1), carbonModifiers: UInt32(cmdKey))
        case .screenshotPin:  return HotkeyBinding(keyCode: UInt32(kVK_F1), carbonModifiers: UInt32(optionKey))
        case .ocr:            return HotkeyBinding(keyCode: UInt32(kVK_F2), carbonModifiers: 0)
        case .annotation:     return HotkeyBinding(keyCode: UInt32(kVK_F3), carbonModifiers: 0)
        }
    }
}

// MARK: - HotkeyStore

final class HotkeyStore: ObservableObject {
    static let shared = HotkeyStore()

    @Published private(set) var bindings: [HotkeyAction: HotkeyBinding] = [:]

    private init() { reload() }

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        saveBinding(binding, for: action)
        bindings[action] = binding
    }

    func restoreDefault(for action: HotkeyAction) {
        clearBinding(for: action)
        bindings[action] = action.defaultBinding
    }

    func restoreDefaults() {
        for action in HotkeyAction.allCases { clearBinding(for: action) }
        reload()
    }

    /// 返回与 binding 完全相同的其他 action；nil 表示无冲突
    func conflictingAction(binding: HotkeyBinding, excludingAction: HotkeyAction) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != excludingAction && self.binding(for: $0) == binding }
    }

    // MARK: - Persistence

    private func reload() {
        var result: [HotkeyAction: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases { result[action] = loadBinding(for: action) }
        bindings = result
    }

    private func kcKey(_ a: HotkeyAction) -> String   { "hotkey_\(a.rawValue)_keyCode" }
    private func modsKey(_ a: HotkeyAction) -> String { "hotkey_\(a.rawValue)_mods" }

    private func loadBinding(for action: HotkeyAction) -> HotkeyBinding {
        let key = kcKey(action)
        guard UserDefaults.standard.object(forKey: key) != nil else { return action.defaultBinding }
        let kc   = UInt32(UserDefaults.standard.integer(forKey: key))
        let mods = UInt32(UserDefaults.standard.integer(forKey: modsKey(action)))
        return HotkeyBinding(keyCode: kc, carbonModifiers: mods)
    }

    private func saveBinding(_ b: HotkeyBinding, for action: HotkeyAction) {
        UserDefaults.standard.set(Int(b.keyCode),          forKey: kcKey(action))
        UserDefaults.standard.set(Int(b.carbonModifiers),  forKey: modsKey(action))
    }

    private func clearBinding(for action: HotkeyAction) {
        UserDefaults.standard.removeObject(forKey: kcKey(action))
        UserDefaults.standard.removeObject(forKey: modsKey(action))
    }
}
