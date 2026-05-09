import AppKit

private final class InlineAnnotationCanvasView: NSView, NSTextFieldDelegate {
    private var capturedImage: NSImage
    private let history = AnnotationHistory()
    private var inProgress: Annotation?
    private var dragStart: NSPoint?
    private var currentPoints: [CGPoint] = []
    private var activeTextField: NSTextField?

    var activeTool: AnnotationKind = .rectangle
    var onChange: (() -> Void)?
    var onCancel: (() -> Void)?
    /// 回调新的 overlay-local selection rect（屏幕本地坐标）
    var onSelectionChanged: ((NSRect) -> Void)?

    private var selHandle: SelHandle?
    private var selDragStartFrame: NSRect = .zero
    private let handleRadius: CGFloat = 4
    private let handleTouch: CGFloat = 8

    private enum SelHandle { case nw, n, ne, e, se, s, sw, w }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if bounds.insetBy(dx: -handleTouch, dy: -handleTouch).contains(localPoint) {
            return self
        }
        return nil
    }

    init(frame: NSRect, image: NSImage) {
        capturedImage = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() { commitActiveText(); history.undo(); needsDisplay = true; onChange?() }
    func redo() { commitActiveText(); history.redo(); needsDisplay = true; onChange?() }

    func replaceImage(_ newImage: NSImage, newFrame: NSRect) {
        let dx = frame.origin.x - newFrame.origin.x
        let dy = frame.origin.y - newFrame.origin.y
        if dx != 0 || dy != 0 {
            history.translateAnnotations(dx: dx, dy: dy)
        }
        capturedImage = newImage
        frame = newFrame
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) { redo() } else { undo() }; return
        }
        if event.keyCode == 53 { cancelActiveText(); onCancel?() }
        else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        commitActiveText()
        let pt = convert(event.locationInWindow, from: nil)
        if let h = selHandle(at: pt) {
            selHandle = h
            selDragStartFrame = frame
            return
        }
        let cp = clampedPoint(pt)
        dragStart = cp; inProgress = nil; currentPoints = [cp]
        if activeTool == .text { beginTextInput(at: cp) }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let h = selHandle {
            selApplyDrag(h, localPt: pt)
            return
        }
        guard activeTool != .text, let start = dragStart else { return }
        let cp = clampedPoint(pt)
        switch activeTool {
        case .rectangle: inProgress = Annotation(kind: .rectangle, rect: normRect(from: start, to: cp))
        case .arrow:     inProgress = Annotation(kind: .arrow, points: [start, cp], lineWidth: 3)
        case .pen:       currentPoints.append(cp); inProgress = Annotation(kind: .pen, points: currentPoints, lineWidth: 3)
        default: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selHandle != nil { selHandle = nil; return }
        guard activeTool != .text else { return }
        if let ann = inProgress { history.add(ann); inProgress = nil; dragStart = nil; currentPoints = []; onChange?() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        capturedImage.draw(in: bounds)
        for ann in history.annotations { drawAnnotation(ann) }
        if let ann = inProgress { drawAnnotation(ann) }
        drawHandles()
    }

    func renderedImage() -> NSImage {
        commitActiveText()
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        capturedImage.draw(in: NSRect(origin: .zero, size: bounds.size))
        for ann in history.annotations { drawAnnotation(ann) }
        image.unlockFocus()
        return image
    }

    // MARK: - Text

    private func beginTextInput(at point: NSPoint) {
        let w: CGFloat = max(140, bounds.width - point.x - 12)
        let field = NSTextField(frame: NSRect(x: point.x, y: max(0, point.y - 28), width: min(w, 260), height: 28))
        field.font = .systemFont(ofSize: 18, weight: .semibold)
        field.textColor = .systemRed
        field.backgroundColor = .clear; field.isBordered = false; field.focusRingType = .none
        field.placeholderString = "文字"; field.delegate = self
        field.target = self; field.action = #selector(commitTextAction)
        addSubview(field); activeTextField = field
        window?.makeFirstResponder(field)
    }

    @objc private func commitTextAction() { commitActiveText() }
    func controlTextDidEndEditing(_ obj: Notification) { commitActiveText() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelActiveText(); onCancel?(); return true }
        return false
    }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { history.add(Annotation(kind: .text, rect: field.frame, text: text, lineWidth: 1)); onChange?() }
        field.removeFromSuperview(); needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func cancelActiveText() { activeTextField?.removeFromSuperview(); activeTextField = nil; needsDisplay = true; window?.makeFirstResponder(self) }

    // MARK: - Draw annotations

    private func drawAnnotation(_ ann: Annotation) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        switch ann.kind {
        case .rectangle: ctx.setStrokeColor(ann.color.cgColor); ctx.setLineWidth(ann.lineWidth); ctx.stroke(ann.rect)
        case .arrow:
            guard ann.points.count >= 2 else { return }
            drawArrow(from: ann.points[0], to: ann.points[1], color: ann.color, lw: ann.lineWidth)
        case .pen:
            guard ann.points.count > 1 else { return }
            ctx.setStrokeColor(ann.color.cgColor); ctx.setLineWidth(ann.lineWidth); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.beginPath(); ctx.move(to: ann.points[0])
            for p in ann.points.dropFirst() { ctx.addLine(to: p) }; ctx.strokePath()
        case .text:
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: ann.color]
            (ann.text as NSString).draw(in: ann.rect.insetBy(dx: 2, dy: 2), withAttributes: a)
        case .highlight: break
        }
    }

    private func drawArrow(from s: CGPoint, to e: CGPoint, color: NSColor, lw: CGFloat) {
        AnnotationDrawing.drawSolidArrow(from: s, to: e, color: color, lineWidth: lw)
    }

    // MARK: - Selection handles (always visible)

    private func drawHandles() {
        let r = bounds
        let pts: [(CGFloat, CGFloat)] = [
            (r.minX, r.minY), (r.midX, r.minY), (r.maxX, r.minY),
            (r.maxX, r.midY), (r.maxX, r.maxY), (r.midX, r.maxY),
            (r.minX, r.maxY), (r.minX, r.midY),
        ]
        for (x, y) in pts {
            let hr = NSRect(x: x - handleRadius, y: y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
            let p = NSBezierPath(ovalIn: hr)
            NSColor.white.withAlphaComponent(0.8).setFill(); p.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke(); p.lineWidth = 1; p.stroke()
        }
    }

    private func selHandle(at pt: NSPoint) -> SelHandle? {
        let r = bounds
        let handles: [(CGFloat, CGFloat, SelHandle)] = [
            (r.minX, r.minY, .nw), (r.midX, r.minY, .n), (r.maxX, r.minY, .ne),
            (r.maxX, r.midY, .e),  (r.maxX, r.maxY, .se), (r.midX, r.maxY, .s),
            (r.minX, r.maxY, .sw), (r.minX, r.midY, .w),
        ]
        for (hx, hy, h) in handles {
            if NSRect(x: hx - handleTouch, y: hy - handleTouch, width: handleTouch * 2, height: handleTouch * 2).contains(pt) { return h }
        }
        return nil
    }

    /// 手柄拖拽：以 drag 起点 frame 为基准，将 localPt 转 overlay-local 后计算新 rect
    private func selApplyDrag(_ h: SelHandle, localPt: NSPoint) {
        let overlayPt = convert(localPt, to: superview)
        var r = selDragStartFrame
        let minW: CGFloat = 10; let minH: CGFloat = 10
        switch h {
        case .nw: r = selNorm(CGPoint(x: overlayPt.x, y: r.maxY), CGPoint(x: r.maxX, y: overlayPt.y))
        case .n:  r = selNorm(CGPoint(x: r.minX, y: r.maxY),  CGPoint(x: r.maxX, y: overlayPt.y))
        case .ne: r = selNorm(CGPoint(x: r.minX, y: r.maxY),  CGPoint(x: overlayPt.x, y: overlayPt.y))
        case .e:  r = selNorm(CGPoint(x: r.minX, y: r.minY),  CGPoint(x: overlayPt.x, y: r.maxY))
        case .se: r = selNorm(CGPoint(x: r.minX, y: r.minY),  CGPoint(x: overlayPt.x, y: overlayPt.y))
        case .s:  r = selNorm(CGPoint(x: r.minX, y: r.minY),  CGPoint(x: r.maxX, y: overlayPt.y))
        case .sw: r = selNorm(CGPoint(x: overlayPt.x, y: r.minY), CGPoint(x: r.maxX, y: overlayPt.y))
        case .w:  r = selNorm(CGPoint(x: overlayPt.x, y: r.minY), CGPoint(x: r.maxX, y: r.maxY))
        }
        guard r.width >= minW, r.height >= minH else { return }
        onSelectionChanged?(r)
    }

    private func selNorm(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func normRect(from s: CGPoint, to e: CGPoint) -> CGRect {
        CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
    }

    private func clampedPoint(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: min(max(pt.x, bounds.minX), bounds.maxX), y: min(max(pt.y, bounds.minY), bounds.maxY))
    }
}

final class InlineScreenshotEditorView: NSView {
    private var selectionRect: NSRect
    private let fullSnapshot: NSImage
    private let screen: NSScreen
    private let canvasView: InlineAnnotationCanvasView
    private let toolbarView = NSView()
    private var toolButtons: [AnnotationKind: NSButton] = [:]

    var onCopy: ((NSImage) -> Void)?
    var onSave: ((NSImage) -> Void)?
    var onPin: ((NSImage, NSRect) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, image: NSImage, selectionRect: NSRect,
         fullSnapshot: NSImage, screen: NSScreen) {
        self.selectionRect = selectionRect
        self.fullSnapshot = fullSnapshot
        self.screen = screen
        canvasView = InlineAnnotationCanvasView(frame: selectionRect, image: image)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(canvasView)
        buildToolbar()
        canvasView.onCancel = { [weak self] in self?.onCancel?() }
        canvasView.onSelectionChanged = { [weak self] newRect in
            self?.applySelectionChange(newRect)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) { canvasView.redo() } else { canvasView.undo() }
            return
        }
        if event.keyCode == 53 { onCancel?() }
        else if event.keyCode == 36 || event.keyCode == 76 { pinImage() }
        else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 2; border.stroke()
    }

    // MARK: - Selection change: crop from frozen full snapshot

    private func applySelectionChange(_ newRect: NSRect) {
        let clamped = newRect.intersection(NSRect(origin: .zero, size: fullSnapshot.size))
        guard clamped.width >= 10, clamped.height >= 10, clamped != selectionRect else { return }
        selectionRect = clamped
        let cropped = cropFromSnapshot(clamped)
        canvasView.replaceImage(cropped, newFrame: clamped)
        repositionToolbar()
        needsDisplay = true
    }

    private func cropFromSnapshot(_ rect: NSRect) -> NSImage {
        let image = NSImage(size: rect.size)
        image.lockFocus()
        fullSnapshot.draw(in: NSRect(origin: NSPoint(x: -rect.minX, y: -rect.minY), size: fullSnapshot.size))
        image.unlockFocus()
        return image
    }

    // MARK: - Toolbar

    private func buildToolbar() {
        toolbarView.wantsLayer = true
        toolbarView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        toolbarView.layer?.cornerRadius = 8
        toolbarView.layer?.borderColor = NSColor.separatorColor.cgColor
        toolbarView.layer?.borderWidth = 1

        let items: [(String, Selector, AnnotationKind?)] = [
            ("矩形", #selector(selectRectangle), .rectangle),
            ("箭头", #selector(selectArrow), .arrow),
            ("画笔", #selector(selectPen), .pen),
            ("文字", #selector(selectText), .text),
            ("钉图", #selector(pinImage), nil),
            ("保存", #selector(saveImage), nil),
            ("复制", #selector(copyImage), nil)
        ]

        var x: CGFloat = 8
        let height: CGFloat = 34
        for item in items {
            let b = NSButton(title: item.0, target: self, action: item.1)
            b.bezelStyle = .rounded; b.font = .systemFont(ofSize: 12)
            if item.2 != nil { b.setButtonType(.toggle) }
            b.sizeToFit()
            b.frame = NSRect(x: x, y: 5, width: max(b.frame.width, 44), height: 24)
            toolbarView.addSubview(b)
            if let tool = item.2 { toolButtons[tool] = b }
            x += b.frame.width + 6
        }
        let w = x + 2
        let yBelow = selectionRect.minY - height - 8
        let yAbove = selectionRect.maxY + 8
        let ty = yBelow >= 8 ? yBelow : min(bounds.maxY - height - 8, yAbove)
        let tx = toolbarX(width: w)
        toolbarView.frame = NSRect(x: tx, y: ty, width: w, height: height)
        addSubview(toolbarView)
        selectTool(.rectangle)
    }

    private func repositionToolbar() {
        let height: CGFloat = 34
        let w = toolbarView.frame.width
        let yBelow = selectionRect.minY - height - 8
        let yAbove = selectionRect.maxY + 8
        let ty = yBelow >= 8 ? yBelow : min(bounds.maxY - height - 8, yAbove)
        let tx = toolbarX(width: w)
        toolbarView.setFrameOrigin(NSPoint(x: tx, y: ty))
    }

    private func toolbarX(width: CGFloat) -> CGFloat {
        let rightAligned = selectionRect.maxX - width
        return min(max(rightAligned, 8), bounds.maxX - width - 8)
    }

    private func selectTool(_ tool: AnnotationKind) {
        canvasView.activeTool = tool
        for (kind, b) in toolButtons { b.state = (kind == tool) ? .on : .off }
        window?.makeFirstResponder(canvasView)
    }

    @objc private func selectRectangle() { selectTool(.rectangle) }
    @objc private func selectArrow() { selectTool(.arrow) }
    @objc private func selectPen() { selectTool(.pen) }
    @objc private func selectText() { selectTool(.text) }
    @objc private func copyImage() { onCopy?(canvasView.renderedImage()) }
    @objc private func saveImage() { onSave?(canvasView.renderedImage()) }
    @objc private func pinImage() {
        let screenFrame = NSRect(
            x: (selectionRect.minX + screen.frame.minX).rounded(),
            y: (selectionRect.minY + screen.frame.minY).rounded(),
            width: selectionRect.width.rounded(),
            height: selectionRect.height.rounded()
        )
        onPin?(canvasView.renderedImage(), screenFrame)
    }
}
