import Foundation
import UserNotifications
import Combine

enum BreakTimerState: Equatable {
    case disabled
    case focusing
    case breakDue
}

final class BreakTimer: ObservableObject {
    static let shared = BreakTimer()

    @Published private(set) var state: BreakTimerState = .disabled
    @Published private(set) var focusStartedAt: Date?

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        AppState.shared.$breakEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.handleEnabledChange(enabled) }
            .store(in: &cancellables)

        AppState.shared.$focusMinutes
            .dropFirst() // 初始值由 breakEnabled 订阅处理
            .receive(on: RunLoop.main)
            .sink { [weak self] minutes in self?.handleFocusMinutesChange(minutes) }
            .store(in: &cancellables)
    }

    // MARK: - 设置变化响应

    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            requestNotificationPermission()
            if state != .breakDue {
                startFocusing(minutes: AppState.shared.focusMinutes)
            }
            // 若 breakDue：保持到期状态，等用户确认后下一轮使用新时长
        } else {
            stop()
        }
    }

    private func handleFocusMinutesChange(_ minutes: Int) {
        guard AppState.shared.breakEnabled else { return }
        if state == .focusing {
            startFocusing(minutes: minutes) // 重新按新时长开始
        }
        // breakDue 状态下不重置，下一轮生效
    }

    // MARK: - 计时控制

    func startFocusing(minutes: Int) {
        timer?.invalidate()
        focusStartedAt = Date()
        state = .focusing
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                     repeats: false) { [weak self] _ in
            self?.triggerBreakDue()
        }
    }

    // 用户确认休息完毕，重新开始专注计时
    func confirmBreak() {
        BreakDisplayTimer.shared.stopCurrentDisplay()
        guard AppState.shared.breakEnabled else { stop(); return }
        startFocusing(minutes: AppState.shared.focusMinutes)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        focusStartedAt = nil
        state = .disabled
        BreakDisplayTimer.shared.stop()
    }

    var activeElapsed: TimeInterval {
        guard state == .focusing, let focusStartedAt else { return 0 }
        return Date().timeIntervalSince(focusStartedAt)
    }

    // MARK: - 强制休息

    func forceBreak() {
        triggerBreakDue()
    }

    // MARK: - 内部

    private func triggerBreakDue() {
        BreakDisplayTimer.shared.stopCurrentDisplay()
        focusStartedAt = nil
        state = .breakDue
        sendNotification()
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "该休息了"
        content.body  = "专注时间到，休息 \(AppState.shared.breakMinutes) 分钟。"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "breakDue-\(Date().timeIntervalSince1970)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                PermissionsManager.shared.checkPermissions()
                if !granted {
                    PermissionsManager.shared.showNotificationPermissionAlertIfNeeded()
                }
            }
        }
    }

}
