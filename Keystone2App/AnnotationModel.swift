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
