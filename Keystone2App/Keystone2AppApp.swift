import SwiftUI

@main
struct Keystone2AppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 设置窗口由 SettingsWindowController 管理，不使用 SwiftUI Settings scene
    var body: some Scene {
        Settings { EmptyView() }
    }
}
