import AppKit
import CoreGraphics
import Combine

final class ScrollManager: ObservableObject {
    static let shared = ScrollManager()

    @Published private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        AppState.shared.$scrollEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.start() } else { self?.stop() }
            }
            .store(in: &cancellables)
    }

    // MARK: - 生命周期

    func start() {
        guard !isActive else { return }
        guard PermissionsManager.shared.requestAccessibilityPermissionIfNeeded() else { return }

        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollManagerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            PermissionsManager.shared.checkPermissions()
            PermissionsManager.shared.showAccessibilityAlertIfNeeded(feature: "鼠标滚轮方向")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = src
        isActive = true
    }

    func stop() {
        guard isActive || eventTap != nil else { return }
        cleanupTap()
    }

    // MARK: - 内部

    func handleTapDisabled(type: CGEventType) {
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            cleanupTap()
        }
    }

    func handleEvent(_ event: CGEvent) -> CGEvent {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else { return event }

        let dy  = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dx  = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let fdy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fdx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let pdy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pdx = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1,       value: -dy)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2,       value: -dx)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fdy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fdx)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1,  value: -pdy)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2,  value: -pdx)

        return event
    }

    private func cleanupTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }
}

private func scrollManagerCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        manager.handleTapDisabled(type: type)
        return nil
    }

    return Unmanaged.passUnretained(manager.handleEvent(event))
}
