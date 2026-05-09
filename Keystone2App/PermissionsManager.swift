import AppKit
import SwiftUI

enum PermissionStatus {
    case granted, denied, unknown

    var displayName: String {
        switch self {
        case .granted: return "已授权"
        case .denied:  return "已拒绝"
        case .unknown: return "未设置"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied:  return .red
        case .unknown: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    /// App 级标记：是否已经触发过屏幕录制的系统 TCC 弹窗。
    /// 首次调用 `CGWindowListCreateImage` 后才置为 true，避免首次双弹窗。
    static var hasAttemptedScreenCapture = false

    @Published var screenRecording: PermissionStatus = .unknown
    @Published var accessibility: PermissionStatus = .unknown

    private var shownAlertKeys = Set<String>()

    func checkPermissions() {
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(opts) ? .granted : .denied
    }

    func showScreenRecordingAlertIfNeeded(feature: String) {
        showPermissionAlertIfNeeded(
            key: "screenRecording-\(feature)",
            title: "\(feature)需要屏幕录制权限",
            message: "Keystone2 需要读取你框选的屏幕区域，才能完成\(feature)。请到「系统设置 > 隐私与安全性 > 屏幕录制」中允许 Keystone2，然后重新尝试。",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func showAccessibilityAlertIfNeeded(feature: String) {
        showPermissionAlertIfNeeded(
            key: "accessibility-\(feature)",
            title: "\(feature)需要辅助功能权限",
            message: "Keystone2 需要辅助功能权限来接收和处理鼠标滚轮事件。请到「系统设置 > 隐私与安全性 > 辅助功能」中允许 Keystone2，然后重新开启该功能。",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func requestAccessibilityPermissionIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        checkPermissions()
        return trusted
    }

    private func showPermissionAlertIfNeeded(key: String, title: String, message: String, settingsURL: String) {
        guard !shownAlertKeys.contains(key) else { return }
        shownAlertKeys.insert(key)

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
