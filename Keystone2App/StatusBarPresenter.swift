import Foundation

// 菜单栏显示模式，MVP-1B 补充 periodicBreak / breakDue
enum StatusBarMode: Equatable {
    case iconOnly
    case currentTask(String)
    case activeElapsed(String)
    case periodicBreak(String)
    case breakDue(String)
}

enum StatusBarPresenter {
    static let maxTextLength = 20

    static func mode(appState: AppState,
                     breakState: BreakTimerState,
                     isPeriodicBreakVisible: Bool,
                     showActiveElapsed: Bool = false,
                     activeElapsed: TimeInterval = 0) -> StatusBarMode {
        guard appState.showMenuBarText else { return .iconOnly }
        if breakState == .breakDue {
            return .breakDue("休息中，点击继续专注！")
        }
        if appState.breakEnabled && isPeriodicBreakVisible {
            return .periodicBreak("该休息了")
        }
        let task = appState.currentTask.trimmingCharacters(in: .whitespaces)
        if !task.isEmpty {
            if showActiveElapsed, activeElapsed > 0 {
                return .activeElapsed(formatElapsed(activeElapsed))
            }
            return .currentTask(truncate(task))
        }
        // 当前事项为空：持续显示活跃时长或休息状态，不交替回空
        if activeElapsed > 0, breakState == .focusing {
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
        case .breakDue(let t):      return t
        }
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxTextLength else { return text }
        return String(text.prefix(maxTextLength)) + "…"
    }

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if interval < 60 { return "活跃 <1分钟" }
        if minutes < 60 { return "活跃 \(minutes) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "活跃 \(hours) 小时" : "活跃 \(hours)小时\(rest)分"
    }
}
