import SwiftUI
import Carbon

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gear") }
            HotkeysTab()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            PermissionsTab()
                .tabItem { Label("权限", systemImage: "lock.shield") }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var scrollManager = ScrollManager.shared
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    var body: some View {
        Form {
            Section("开机自启动") {
                Toggle("登录时自动启动 Keystone2", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setEnabled($0) }
                ))
                if !launchManager.statusDescription.isEmpty {
                    Text(launchManager.statusDescription)
                        .font(.caption)
                        .foregroundColor(launchStatusColor)
                }
                if let err = launchManager.errorMessage {
                    Text(err).font(.caption).foregroundColor(.red)
                }
            }
            .onAppear { launchManager.refresh() }

            Section("当前事项") {
                TextField("输入当前最重要的事项…", text: $state.currentTask)
                    .textFieldStyle(.roundedBorder)
                Picker("菜单栏颜色", selection: $state.currentTaskColorMode) {
                    ForEach(AppState.CurrentTaskColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("显示在菜单栏中，超过 \(StatusBarPresenter.maxTextLength) 字时自动截断。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("菜单栏") {
                Toggle("显示菜单栏文字", isOn: $state.showMenuBarText)
            }

            Section("鼠标滚轮方向") {
                Toggle("翻转外接鼠标滚轮方向", isOn: $state.scrollEnabled)
                Text(scrollStatusText)
                    .font(.caption)
                    .foregroundColor(scrollStatusColor)
            }

            Section("休息提醒") {
                Toggle("启用休息提醒", isOn: $state.breakEnabled)
                Stepper("专注时长：\(state.focusMinutes) 分钟", value: $state.focusMinutes, in: 10...120, step: 5)
                    .disabled(!state.breakEnabled)
                Stepper("休息时长：\(state.breakMinutes) 分钟", value: $state.breakMinutes, in: 5...60, step: 5)
                    .disabled(!state.breakEnabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollStatusText: String {
        if !state.scrollEnabled { return "已关闭。仅对外接鼠标生效，触控板不受影响。" }
        if scrollManager.isActive { return "已生效。外接鼠标滚轮方向已翻转，触控板不受影响。" }
        return "未生效，请在「系统设置 > 隐私与安全性 > 辅助功能」中授予权限。"
    }

    private var scrollStatusColor: Color {
        if !state.scrollEnabled { return .secondary }
        if scrollManager.isActive { return .green }
        return .orange
    }

    private var launchStatusColor: Color {
        switch launchManager.statusDescriptionColor {
        case .green:     return .green
        case .orange:    return .orange
        case .red:       return .red
        case .secondary: return .secondary
        }
    }
}

// MARK: - 快捷键录制状态机

private final class HotkeyRecorder: ObservableObject {
    @Published var recordingAction: HotkeyAction? = nil
    @Published var message: (text: String, isError: Bool)? = nil

    private var localMonitor: Any?
    private var globalMonitor: Any?

    func startRecording(_ action: HotkeyAction) {
        removeMonitors()
        message = nil
        recordingAction = action
        HotkeyManager.shared.stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
            return nil   // 录制期间消费事件，防止误触其他操作
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    func cancelRecording() {
        removeMonitors()
        recordingAction = nil
        HotkeyManager.shared.reloadAndReregister()
    }

    private func handleEvent(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        if event.type == .flagsChanged { return }   // 单独修饰键，忽略
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return }
        guard let binding = HotkeyBinding(event: event) else { return }
        finishRecording(action: action, newBinding: binding)
    }

    private func finishRecording(action: HotkeyAction, newBinding: HotkeyBinding) {
        removeMonitors()
        recordingAction = nil

        if let conflict = HotkeyStore.shared.conflictingAction(binding: newBinding, excludingAction: action) {
            message = (text: "与「\(conflict.label)」冲突，快捷键未更改。", isError: true)
            HotkeyManager.shared.reloadAndReregister()
            return
        }

        let oldBinding = HotkeyStore.shared.binding(for: action)
        HotkeyStore.shared.setBinding(newBinding, for: action)
        let failures = HotkeyManager.shared.reloadAndReregister()

        if failures.contains(action) {
            HotkeyStore.shared.setBinding(oldBinding, for: action)
            HotkeyManager.shared.reloadAndReregister()
            message = (text: "这个快捷键可能已被系统或其他 App 占用，已恢复原快捷键。", isError: false)
        }
    }

    private func removeMonitors() {
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}

// MARK: - 快捷键 Tab

private struct HotkeysTab: View {
    @StateObject private var recorder = HotkeyRecorder()
    @ObservedObject private var store = HotkeyStore.shared

    var body: some View {
        Form {
            Section("快捷键") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    HotkeyRow(
                        action: action,
                        binding: store.binding(for: action),
                        isRecording: recorder.recordingAction == action,
                        onRecord: { recorder.startRecording(action) },
                        onRestoreDefault: {
                            HotkeyStore.shared.restoreDefault(for: action)
                            HotkeyManager.shared.reloadAndReregister()
                        }
                    )
                }
            }

            if let msg = recorder.message {
                Text(msg.text)
                    .font(.caption)
                    .foregroundColor(msg.isError ? .red : .orange)
            }

            Button("恢复所有默认快捷键") {
                HotkeyStore.shared.restoreDefaults()
                HotkeyManager.shared.reloadAndReregister()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { recorder.cancelRecording() }
    }
}

private struct HotkeyRow: View {
    let action: HotkeyAction
    let binding: HotkeyBinding
    let isRecording: Bool
    let onRecord: () -> Void
    let onRestoreDefault: () -> Void

    var body: some View {
        LabeledContent(action.label) {
            HStack(spacing: 8) {
                if isRecording {
                    Text("录制中… 按下新快捷键，Esc 取消")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    Text(binding.displayString)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Button("录制", action: onRecord)
                        .accessibilityHint("按下后按下新快捷键来录制，Esc 取消")
                    Button(action: onRestoreDefault) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("恢复默认快捷键")
                }
            }
        }
    }
}

// MARK: - 权限

private struct PermissionsTab: View {
    @ObservedObject private var pm = PermissionsManager.shared

    var body: some View {
        Form {
            Section("权限状态") {
                PermissionRow(label: "屏幕录制",  status: pm.screenRecording, detail: "截图、OCR 功能需要")
                PermissionRow(label: "辅助功能",  status: pm.accessibility,   detail: "全局快捷键、鼠标事件需要")
                PermissionRow(label: "通知",      status: pm.notifications,   detail: "休息提醒需要")
            }
            Button("刷新权限状态") { pm.checkPermissions() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PermissionRow: View {
    let label: String
    let status: PermissionStatus
    let detail: String

    var body: some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                    Text(status.displayName).foregroundColor(.secondary)
                }
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
