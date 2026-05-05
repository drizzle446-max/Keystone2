import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
        PermissionsManager.shared.checkPermissions()
        _ = ScrollManager.shared
        setupHotkeyManager()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        ScrollManager.shared.stop()
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
