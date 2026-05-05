import AppKit

private final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // Allow the pin to be positioned in the menu bar area and dragged there.
    // Default constrainFrameRect keeps windows below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

private final class PinImageView: NSImageView {
    var onClose: (() -> Void)?
    var originalSize: NSSize = .zero
    var currentScale: CGFloat = 1.0

    override var acceptsFirstResponder: Bool { true }

    private var isDragging = false
    private var dragStartOrigin: NSPoint = .zero
    private var dragStartMouseScreen: NSPoint = .zero
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onClose?()
            return
        }
        window?.makeKey()
        window?.makeFirstResponder(self)
        isDragging = true
        dragStartOrigin = window?.frame.origin ?? .zero
        dragStartMouseScreen = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let win = window else { return }
        let current = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + current.x - dragStartMouseScreen.x,
            y: dragStartOrigin.y + current.y - dragStartMouseScreen.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let win = window, originalSize.width > 0 else { return }
        let delta = event.deltaY
        guard abs(delta) > 0 else { return }

        let factor = pow(1.1, delta / 3.0)
        let newScale = min(4.0, max(0.25, currentScale * factor))
        guard abs(newScale - currentScale) > 0.001 else { return }
        currentScale = newScale

        let newW = (originalSize.width * newScale).rounded()
        let newH = (originalSize.height * newScale).rounded()
        let cx = win.frame.midX
        let cy = win.frame.midY
        let newFrame = NSRect(
            x: (cx - newW / 2).rounded(),
            y: (cy - newH / 2).rounded(),
            width: newW,
            height: newH
        )
        win.setFrame(newFrame, display: true)
    }

    override func rightMouseUp(with event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "复制", action: #selector(doCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭", action: #selector(doClose), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func doCopy() {
        guard let img = image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
    }

    @objc private func doClose() { onClose?() }
}

final class PinWindowController: NSWindowController {
    var onClose: (() -> Void)?

    init(image: NSImage, screenFrame: NSRect? = nil) {
        let contentRect = screenFrame ?? NSRect(origin: .zero, size: image.size)
        let win = PinPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // statusWindow level (25) is one above mainMenuWindow (24), allowing pins
        // to appear in and be dragged into the menu bar area.
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hasShadow = true
        win.backgroundColor = .clear
        win.isOpaque = false

        let imageView = PinImageView(frame: NSRect(origin: .zero, size: contentRect.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        imageView.originalSize = contentRect.size
        win.contentView = imageView

        super.init(window: win)
        if screenFrame == nil { win.center() }

        imageView.onClose = { [weak self] in
            self?.window?.close()
            self?.onClose?()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.orderFront(nil)
    }
}
