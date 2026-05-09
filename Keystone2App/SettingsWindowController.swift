import AppKit
import SwiftUI

class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let windowSize = NSSize(width: 760, height: 590)

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.isReleasedWhenClosed = false  // 防止关闭后 AppKit 释放 window 对象导致 EXC_BAD_ACCESS
            w.title = "Keystone2 设置"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.minSize = windowSize
            w.maxSize = windowSize
            w.contentView = NSHostingView(rootView: SettingsView())
            w.delegate = self
            w.center()
            window = w
        } else if let window {
            window.minSize = windowSize
            window.maxSize = windowSize
            window.setContentSize(windowSize)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        windowSize
    }
}
