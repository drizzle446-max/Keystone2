import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
        PermissionsManager.shared.checkPermissions()
        _ = ScrollManager.shared
        IdleDetector.shared.start()
        setupHotkeyManager()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        ScrollManager.shared.stop()
        IdleDetector.shared.stop()
    }

    private func setupHotkeyManager() {
        HotkeyManager.shared.onScreenshot     = { ScreenshotManager.shared.takeScreenshot() }
        HotkeyManager.shared.onScreenshotCopy = { ScreenshotManager.shared.takeScreenshotAndCopy() }
        HotkeyManager.shared.onScreenshotPin  = { ScreenshotManager.shared.takeScreenshotAndPin() }
        HotkeyManager.shared.onOCR        = { OCRManager.shared.startOCR() }
        HotkeyManager.shared.onAnnotation = { ScreenAnnotationManager.shared.startAnnotation() }
        HotkeyManager.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - 鼠标空闲检测

final class IdleDetector {
    static let shared = IdleDetector()

    private var pollTimer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastMousePos: CGPoint = .zero
    private var lastInputTime: Date = Date()
    private var restActivityStartedAt: Date?
    private var lastRestActivityAt: Date?
    private let idleThreshold: TimeInterval = 60
    private let restActivityThreshold: TimeInterval = 60
    private let restActivityContinuityGap: TimeInterval = 10
    private let mouseMoveThreshold: CGFloat = 2

    private init() {}

    func start() {
        lastMousePos = NSEvent.mouseLocation
        resetIdleClock()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
        startInputMonitors()
        BreakTimer.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .breakPrompt:
                    resetIdleClock()
                    resetRestActivity()
                case .resting:
                    resetRestActivity()
                default:
                    resetRestActivity()
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        cancellables.removeAll()
    }

    private func checkIdle() {
        let pos = NSEvent.mouseLocation
        if distance(pos, lastMousePos) >= mouseMoveThreshold {
            lastMousePos = pos
            recordInput()
        }

        let now = Date()
        switch BreakTimer.shared.state {
        case .breakPrompt where now.timeIntervalSince(lastInputTime) >= idleThreshold:
            BreakTimer.shared.enterRest()
        case .resting:
            evaluateRestActivity(now: now)
        default:
            break
        }
    }

    private func startInputMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .flagsChanged
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.recordInput(event: event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.recordInput(event: event)
        }
    }

    private func recordInput(event: NSEvent) {
        if event.type == .mouseMoved || event.type == .leftMouseDragged || event.type == .rightMouseDragged || event.type == .otherMouseDragged {
            lastMousePos = NSEvent.mouseLocation
        }
        recordInput()
    }

    private func recordInput() {
        resetIdleClock()
        recordRestActivityIfNeeded(now: Date())
    }

    private func resetIdleClock() {
        lastInputTime = Date()
    }

    private func recordRestActivityIfNeeded(now: Date) {
        guard BreakTimer.shared.state == .resting else { return }
        if let last = lastRestActivityAt,
           now.timeIntervalSince(last) > restActivityContinuityGap {
            restActivityStartedAt = now
        } else if restActivityStartedAt == nil {
            restActivityStartedAt = now
        }
        lastRestActivityAt = now
        evaluateRestActivity(now: now)
    }

    private func evaluateRestActivity(now: Date) {
        guard let started = restActivityStartedAt,
              let last = lastRestActivityAt else { return }
        if now.timeIntervalSince(last) > restActivityContinuityGap {
            resetRestActivity()
            return
        }
        if now.timeIntervalSince(started) >= restActivityThreshold {
            resetRestActivity()
            BreakTimer.shared.confirmRest()
        }
    }

    private func resetRestActivity() {
        restActivityStartedAt = nil
        lastRestActivityAt = nil
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
