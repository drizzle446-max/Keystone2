import Foundation

enum StatusBarMode: Equatable {
    case iconOnly
    case currentTask(String)
    case activeElapsed(String)
    case periodicBreak(String)  // 专注中的周期提醒
    case breakHint(String)      // breakPrompt 循环里的「该休息了」
    case resting                // 休息中，显示 ☕
}

enum StatusBarPresenter {
    static let maxTextLength = 20

    static func mode(appState: AppState,
                     breakState: BreakTimerState,
                     isPeriodicBreakVisible: Bool,
                     showActiveElapsed: Bool = false,
                     showBreakHint: Bool = false,
                     activeElapsed: TimeInterval = 0) -> StatusBarMode {
        guard appState.showMenuBarText else { return .iconOnly }

        if breakState == .resting { return .resting }

        let hintText = appState.breakHintText.isEmpty ? "该休息了" : appState.breakHintText

        if breakState == .breakPrompt {
            if showBreakHint { return .breakHint(hintText) }
            let task = appState.currentTask.trimmingCharacters(in: .whitespaces)
            if showActiveElapsed || task.isEmpty {
                return activeElapsed > 0 ? .activeElapsed(formatElapsed(activeElapsed)) : .breakHint(hintText)
            }
            return .currentTask(truncate(task))
        }

        let task = appState.currentTask.trimmingCharacters(in: .whitespaces)
        if !task.isEmpty {
            if showActiveElapsed, activeElapsed > 0 {
                return .activeElapsed(formatElapsed(activeElapsed))
            }
            return .currentTask(truncate(task))
        }

        if breakState == .focusing {
            return .activeElapsed(formatElapsed(activeElapsed))
        }
        return .iconOnly
    }

    static func menuBarTitle(for mode: StatusBarMode) -> String {
        switch mode {
        case .iconOnly:              return ""
        case .currentTask(let t):   return t
        case .activeElapsed(let t): return t
        case .periodicBreak(let t): return t
        case .breakHint(let t):     return t
        case .resting:              return "☕"
        }
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxTextLength else { return text }
        return String(text.prefix(maxTextLength)) + "…"
    }

    static func formatElapsed(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if interval < 60 { return "<1分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours)小时\(rest)分"
    }
}
