import AppKit

enum AnnotationKind {
    case rectangle
    case arrow
    case pen
    case text       // 占位，暂不实现
    case highlight  // 半透明粗线高亮
}

struct Annotation {
    var kind: AnnotationKind
    var rect: CGRect         // rectangle 使用
    var points: [CGPoint]    // pen / arrow 使用
    var text: String         // text 使用
    var color: NSColor
    var lineWidth: CGFloat

    init(kind: AnnotationKind,
         rect: CGRect = .zero,
         points: [CGPoint] = [],
         text: String = "",
         color: NSColor = .systemRed,
         lineWidth: CGFloat = 2) {
        self.kind = kind
        self.rect = rect
        self.points = points
        self.text = text
        self.color = color
        self.lineWidth = lineWidth
    }
}

// 手动历史栈，同时支持 undo 和 redo
class AnnotationHistory {
    private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ annotation: Annotation) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations.append(annotation)
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func clear() {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations.removeAll()
    }

    func translateAnnotations(dx: CGFloat, dy: CGFloat) {
        func translate(_ anns: [Annotation]) -> [Annotation] {
            anns.map { ann in
                var a = ann
                a.rect = a.rect.offsetBy(dx: dx, dy: dy)
                a.points = a.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                return a
            }
        }
        annotations = translate(annotations)
        undoStack = undoStack.map(translate)
        redoStack = redoStack.map(translate)
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let cgImg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImg)
        return rep.representation(using: .png, properties: [:])
    }
}

enum AnnotationDrawing {
    static func drawSolidArrow(from start: CGPoint,
                               to end: CGPoint,
                               color: NSColor,
                               lineWidth: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(lineWidth * 6, 18)
        let headWidth = max(lineWidth * 4.5, 14)
        let shaftEnd = CGPoint(
            x: end.x - headLength * 0.72 * cos(angle),
            y: end.y - headLength * 0.72 * sin(angle)
        )
        let halfWidth = headWidth / 2
        let left = CGPoint(
            x: shaftEnd.x + halfWidth * cos(angle + .pi / 2),
            y: shaftEnd.y + halfWidth * sin(angle + .pi / 2)
        )
        let right = CGPoint(
            x: shaftEnd.x + halfWidth * cos(angle - .pi / 2),
            y: shaftEnd.y + halfWidth * sin(angle - .pi / 2)
        )

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }
}
