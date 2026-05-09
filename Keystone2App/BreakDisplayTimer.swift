import Foundation
import Combine

final class BreakDisplayTimer: ObservableObject {
    static let shared = BreakDisplayTimer()

    @Published private(set) var isPeriodicBreakVisible = false

    private var periodicTimer: Timer?
    private var hideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let periodInterval: TimeInterval = 5 * 60
    private let visibleDuration: TimeInterval = 20

    private init() {
        AppState.shared.$breakEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.startPeriodic() } else { self?.stop() }
            }
            .store(in: &cancellables)
    }

    private func startPeriodic() {
        periodicTimer?.invalidate()
        stopCurrentDisplay()
    }

    private func showPeriodicBreak() {
        isPeriodicBreakVisible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: visibleDuration, repeats: false) { [weak self] _ in
            self?.isPeriodicBreakVisible = false
        }
    }

    func stopCurrentDisplay() {
        hideTimer?.invalidate()
        hideTimer = nil
        isPeriodicBreakVisible = false
    }

    func stop() {
        periodicTimer?.invalidate()
        periodicTimer = nil
        stopCurrentDisplay()
    }

}
