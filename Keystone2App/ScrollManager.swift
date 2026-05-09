import AppKit
import CoreGraphics
import Combine

final class ScrollManager: ObservableObject {
    static let shared = ScrollManager()

    @Published private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    // 平滑滚动状态
    private var velocityY: Double = 0
    private var velocityX: Double = 0
    private var fractionY: Double = 0   // 亚像素累积
    private var fractionX: Double = 0
    private var smoothTimer: Timer?
    private let friction: Double = 0.85
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private let syntheticScrollMarker: Int64 = 0x4B533253

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
        smoothTimer?.invalidate()
        smoothTimer = nil
        velocityY = 0; velocityX = 0
        fractionY = 0; fractionX = 0
        guard isActive || eventTap != nil else { return }
        cleanupTap()
    }

    // MARK: - 内部

    func handleTapDisabled(type: CGEventType) {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticScrollMarker {
            return Unmanaged.passUnretained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        if isContinuous {
            // 触控板保持系统原生方向和惯性，不受外接鼠标翻转影响。
            return Unmanaged.passUnretained(event)
        }

        enqueueSmoothScroll(from: event)
        return nil
    }

    private func enqueueSmoothScroll(from event: CGEvent) {
        let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)

        let dy = smoothDelta(point: pointY, fixed: fixedY, line: lineY)
        let dx = smoothDelta(point: pointX, fixed: fixedX, line: lineX)

        velocityY += -dy
        velocityX += -dx
        startSmoothTimer()
    }

    private func smoothDelta(point: Int64, fixed: Double, line: Int64) -> Double {
        if point != 0 { return Double(point) }
        if fixed != 0 { return fixed * 10 }
        return Double(line) * 12
    }

    private func startSmoothTimer() {
        guard smoothTimer == nil else { return }
        smoothTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.smoothStep()
        }
    }

    private func smoothStep() {
        velocityY *= friction
        velocityX *= friction
        fractionY += velocityY
        fractionX += velocityX

        let dy = Int32(fractionY)
        let dx = Int32(fractionX)
        fractionY -= Double(dy)
        fractionX -= Double(dx)

        if dy != 0 || dx != 0 {
            postSmoothScroll(dy: dy, dx: dx)
        }

        if abs(velocityY) < 0.1 && abs(velocityX) < 0.1 {
            velocityY = 0; velocityX = 0
            fractionY = 0; fractionX = 0
            smoothTimer?.invalidate()
            smoothTimer = nil
        }
    }

    private func postSmoothScroll(dy: Int32, dx: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                   units: .pixel,
                                   wheelCount: 2,
                                   wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticScrollMarker)
        event.post(tap: .cghidEventTap)
    }

    private func cleanupTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
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

    return manager.handleEvent(event)
}
