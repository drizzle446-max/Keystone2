import Carbon
import AppKit
import Combine

enum HotkeyAction: UInt32, CaseIterable {
    case screenshot     = 1
    case screenshotCopy = 2
    case screenshotPin  = 3
    case ocr            = 4
    case annotation     = 5

    var label: String {
        switch self {
        case .screenshot:     return "截图并编辑"
        case .screenshotCopy: return "截图并复制"
        case .screenshotPin:  return "截图并钉图"
        case .ocr:            return "OCR 并复制"
        case .annotation:     return "屏幕标注"
        }
    }
}

final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published private(set) var isActive = false

    var onScreenshot:     (() -> Void)?
    var onScreenshotCopy: (() -> Void)?
    var onScreenshotPin:  (() -> Void)?
    var onOCR:            (() -> Void)?
    var onAnnotation:     (() -> Void)?

    private let sig: OSType = 0x4B533248  // 'KS2H'
    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    private init() {}

    // MARK: - 生命周期

    @discardableResult
    func start() -> [HotkeyAction] {
        guard !isActive else { return [] }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                hotkeyManagerCallback,
                                                1, &eventSpec,
                                                selfPtr,
                                                &handlerRef)
        guard installStatus == noErr else { return Array(HotkeyAction.allCases) }

        var failed: [HotkeyAction] = []
        var successCount = 0
        for action in HotkeyAction.allCases {
            let binding = HotkeyStore.shared.binding(for: action)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: sig, id: action.rawValue)
            let s = RegisterEventHotKey(binding.keyCode, binding.carbonModifiers, hkID,
                                        GetApplicationEventTarget(), 0, &ref)
            if s == noErr, let ref {
                refs.append(ref)
                successCount += 1
            } else {
                failed.append(action)
            }
        }

        if successCount == 0 {
            if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
            return failed
        }

        isActive = true
        return failed
    }

    func stop() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
        isActive = false
    }

    @discardableResult
    func reloadAndReregister() -> [HotkeyAction] {
        stop()
        return start()
    }

    // MARK: - 触发分发

    func didReceiveHotkey(id: UInt32) {
        guard let action = HotkeyAction(rawValue: id) else { return }
        handlerFor(action)?()
    }

    // MARK: - 内部

    private func handlerFor(_ action: HotkeyAction) -> (() -> Void)? {
        switch action {
        case .screenshot:     return onScreenshot
        case .screenshotCopy: return onScreenshotCopy
        case .screenshotPin:  return onScreenshotPin
        case .ocr:            return onOCR
        case .annotation:     return onAnnotation
        }
    }

}

private func hotkeyManagerCallback(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    var hkID = EventHotKeyID()
    let paramStatus = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hkID)
    guard paramStatus == noErr else { return OSStatus(eventNotHandledErr) }
    manager.didReceiveHotkey(id: hkID.id)
    return noErr
}
