import Foundation
import Combine

enum BreakTimerState: Equatable {
    case disabled
    case focusing
    case breakPrompt  // 专注到期，显示「该休息了」循环，等用户触发
    case resting      // 用户已进入休息，显示 ☕
}

final class BreakTimer: ObservableObject {
    static let shared = BreakTimer()

    @Published private(set) var state: BreakTimerState = .disabled
    @Published private(set) var focusStartedAt: Date?
    // 专注到期时快照的时长，供 breakPrompt 状态显示用
    private(set) var focusedDuration: TimeInterval = 0

    private var focusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        AppState.shared.$breakEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.handleEnabledChange(enabled) }
            .store(in: &cancellables)

        AppState.shared.$focusMinutes
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] minutes in self?.handleFocusMinutesChange(minutes) }
            .store(in: &cancellables)
    }

    // MARK: - 设置变化响应

    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            if state == .disabled {
                startFocusing(minutes: AppState.shared.focusMinutes)
            }
        } else {
            stop()
        }
    }

    private func handleFocusMinutesChange(_ minutes: Int) {
        guard AppState.shared.breakEnabled else { return }
        if state == .focusing {
            startFocusing(minutes: minutes)
        }
    }

    // MARK: - 计时控制

    func startFocusing(minutes: Int) {
        focusTimer?.invalidate()
        focusStartedAt = Date()
        state = .focusing
        focusTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                          repeats: false) { [weak self] _ in
            self?.triggerBreakPrompt()
        }
    }

    // 专注到期 → breakPrompt（不自动进入休息）
    private func triggerBreakPrompt() {
        focusedDuration = activeElapsed
        focusTimer?.invalidate()
        focusStartedAt = nil
        state = .breakPrompt
    }

    // 用户触发休息（左键点击 / 菜单"休息一下" / 空闲检测）
    func enterRest() {
        focusTimer?.invalidate()
        focusStartedAt = nil
        state = .resting
    }

    // 休息完毕（用户点击或休息期间持续活跃自动触发）
    func confirmRest() {
        BreakDisplayTimer.shared.stopCurrentDisplay()
        guard AppState.shared.breakEnabled else { stop(); return }
        startFocusing(minutes: AppState.shared.focusMinutes)
    }

    func stop() {
        focusTimer?.invalidate()
        focusTimer = nil
        focusStartedAt = nil
        state = .disabled
        BreakDisplayTimer.shared.stop()
    }

    var activeElapsed: TimeInterval {
        guard state == .focusing, let focusStartedAt else { return 0 }
        return Date().timeIntervalSince(focusStartedAt)
    }

    // MARK: - 强制进入休息（跳过 prompt）

    func forceBreak() {
        enterRest()
    }

}
