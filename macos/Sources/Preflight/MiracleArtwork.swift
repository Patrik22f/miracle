import AppKit

enum MiracleArtwork {
    static func drawMark(in context: CGContext, bounds: CGRect, color: CGColor) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
        }
        let path = CGMutablePath()
        path.move(to: point(0.16, 0.20))
        path.addLine(to: point(0.16, 0.57))
        path.addCurve(to: point(0.50, 0.57), control1: point(0.16, 0.88), control2: point(0.50, 0.88))
        path.addLine(to: point(0.50, 0.20))
        path.move(to: point(0.50, 0.57))
        path.addCurve(to: point(0.84, 0.57), control1: point(0.50, 0.88), control2: point(0.84, 0.88))
        path.addLine(to: point(0.84, 0.20))
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(bounds.width * 0.115)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    @MainActor static func menuImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawMark(in: context, bounds: rect, color: CGColor(gray: 0, alpha: 1))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Miracle"
        return image
    }
}
