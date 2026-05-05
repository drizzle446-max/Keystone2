import AppKit

final class ScreenAnnotationView: NSView {
    var activeTool: AnnotationKind = .pen
    var onExit: (() -> Void)?

    private let history = AnnotationHistory()
    private var inProgress: Annotation?
    private var dragStart: CGPoint?
    private var isMouseHighlightEnabled = false
    private var mouseHighlightPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    // Same as SelectionView — first click on a non-key screen's overlay should
    // immediately start drawing, not just activate the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func clearAnnotations() {
        history.clear()
        needsDisplay = true
    }

    func setTool(_ tool: AnnotationKind) {
        activeTool = tool
    }

    func setMouseHighlightEnabled(_ enabled: Bool) {
        isMouseHighlightEnabled = enabled
        if !enabled { mouseHighlightPoint = nil }
        needsDisplay = true
    }

    func updateMouseHighlightLocation(_ point: CGPoint) {
        guard isMouseHighlightEnabled else { return }
        mouseHighlightPoint = clampedPoint(point)
        needsDisplay = true
    }

    func clearMouseHighlightDot() {
        mouseHighlightPoint = nil
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() } else { super.keyDown(with: event) }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateMouseHighlightLocation(pt)
        dragStart = pt
        switch activeTool {
        case .pen:
            inProgress = Annotation(kind: .pen, points: [pt], color: .systemRed, lineWidth: 3)
        case .arrow:
            inProgress = Annotation(kind: .arrow, points: [pt, pt], color: .systemRed, lineWidth: 3)
        case .rectangle:
            inProgress = Annotation(kind: .rectangle, rect: CGRect(origin: pt, size: .zero),
                                    color: .systemRed, lineWidth: 3)
        case .highlight:
            inProgress = Annotation(kind: .highlight, points: [pt],
                                    color: .systemYellow, lineWidth: 14)
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var ann = inProgress else { return }
        let pt = convert(event.locationInWindow, from: nil)
        updateMouseHighlightLocation(pt)
        switch ann.kind {
        case .pen, .highlight:
            ann.points.append(pt)
        case .arrow:
            if ann.points.count >= 2 { ann.points[1] = pt }
        case .rectangle:
            if let start = dragStart {
                ann.rect = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y),
                                  width: abs(pt.x - start.x), height: abs(pt.y - start.y))
            }
        case .text:
            break
        }
        inProgress = ann
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        updateMouseHighlightLocation(convert(event.locationInWindow, from: nil))
        guard let ann = inProgress else { return }
        inProgress = nil
        dragStart = nil
        switch ann.kind {
        case .pen, .highlight:
            if ann.points.count >= 2 { history.add(ann) }
        case .arrow:
            if ann.points.count >= 2 {
                let dx = ann.points[1].x - ann.points[0].x
                let dy = ann.points[1].y - ann.points[0].y
                if sqrt(dx * dx + dy * dy) > 5 { history.add(ann) }
            }
        case .rectangle:
            if ann.rect.width > 5 && ann.rect.height > 5 { history.add(ann) }
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateMouseHighlightLocation(convert(event.locationInWindow, from: nil))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()
        for ann in history.annotations { drawAnnotation(ann) }
        if let ann = inProgress { drawAnnotation(ann) }
        drawMouseHighlightIfNeeded()
    }

    private func drawMouseHighlightIfNeeded() {
        guard isMouseHighlightEnabled, let point = mouseHighlightPoint else { return }
        let radius: CGFloat = 22
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.systemYellow.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.systemYellow.setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.black.withAlphaComponent(0.45).setStroke()
        let outer = NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1))
        outer.lineWidth = 1
        outer.stroke()
    }

    private func drawAnnotation(_ ann: Annotation) {
        switch ann.kind {
        case .pen:
            guard ann.points.count >= 2 else { return }
            let path = NSBezierPath()
            path.move(to: ann.points[0])
            ann.points.dropFirst().forEach { path.line(to: $0) }
            path.lineWidth = ann.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            ann.color.setStroke()
            path.stroke()

        case .arrow:
            guard ann.points.count >= 2 else { return }
            let start = ann.points[0], end = ann.points[1]
            ann.color.setStroke()
            let line = NSBezierPath()
            line.move(to: start); line.line(to: end)
            line.lineWidth = ann.lineWidth
            line.lineCapStyle = .round
            line.stroke()
            drawArrowHead(from: start, to: end, lineWidth: ann.lineWidth, color: ann.color)

        case .rectangle:
            let path = NSBezierPath(rect: ann.rect)
            path.lineWidth = ann.lineWidth
            ann.color.setStroke()
            path.stroke()

        case .highlight:
            guard ann.points.count >= 2 else { return }
            let path = NSBezierPath()
            path.move(to: ann.points[0])
            ann.points.dropFirst().forEach { path.line(to: $0) }
            path.lineWidth = ann.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            ann.color.withAlphaComponent(0.35).setStroke()
            path.stroke()

        case .text:
            break
        }
    }

    private func drawArrowHead(from start: CGPoint, to end: CGPoint,
                               lineWidth: CGFloat, color: NSColor) {
        let dx = end.x - start.x, dy = end.y - start.y
        guard sqrt(dx * dx + dy * dy) > 1 else { return }
        let angle = atan2(dy, dx)
        let headLen = max(lineWidth * 4, 14)
        let spread: CGFloat = .pi / 6

        let p1 = CGPoint(x: end.x - headLen * cos(angle - spread),
                         y: end.y - headLen * sin(angle - spread))
        let p2 = CGPoint(x: end.x - headLen * cos(angle + spread),
                         y: end.y - headLen * sin(angle + spread))

        let path = NSBezierPath()
        path.move(to: end); path.line(to: p1)
        path.move(to: end); path.line(to: p2)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
