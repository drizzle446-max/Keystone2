import ServiceManagement
import Combine

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String? = nil

    /// Toggle 是否应呈现为"开启"：已启用或已请求待批准
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    private init() { refresh() }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enable: Bool) {
        errorMessage = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = enable
                ? "开启失败：\(error.localizedDescription)"
                : "关闭失败：\(error.localizedDescription)"
        }
        refresh()
    }

    /// 状态说明文案；空字符串表示无需显示
    var statusDescription: String {
        switch status {
        case .enabled:
            return "已开启。登录 macOS 后 Keystone2 会自动出现在菜单栏。"
        case .requiresApproval:
            return "需要在「系统设置 > 通用 > 登录项」中允许 Keystone2。"
        case .notFound:
            return "系统暂时无法找到登录项，请重新开启或重装 App。"
        default:
            return ""
        }
    }

    var statusDescriptionColor: StatusDescriptionColor {
        switch status {
        case .enabled:           return .green
        case .requiresApproval:  return .orange
        case .notFound:          return .red
        default:                 return .secondary
        }
    }

    enum StatusDescriptionColor { case green, orange, red, secondary }
}
