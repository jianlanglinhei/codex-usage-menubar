import AppKit

/// Keep the percentage beside a small calibrated cup, filled from the bottom.
func quotaImage(remaining: Int?, stale: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 20), flipped: false) { _ in
        let alpha: CGFloat = stale ? 0.45 : 1
        let outline = NSColor.labelColor.withAlphaComponent(alpha)
        let cup = NSBezierPath()
        cup.move(to: NSPoint(x: 3, y: 15))
        cup.line(to: NSPoint(x: 15, y: 15))
        cup.line(to: NSPoint(x: 13.5, y: 2))
        cup.curve(to: NSPoint(x: 4.5, y: 2), controlPoint1: NSPoint(x: 11, y: 0.5), controlPoint2: NSPoint(x: 7, y: 0.5))
        cup.close()
        if let remaining, remaining > 0 {
            let fraction = CGFloat(min(100, remaining)) / 100
            let color: NSColor
            switch QuotaLevel(remaining: remaining) {
            case .healthy: color = NSColor(srgbRed: 0.83, green: 0.53, blue: 0.24, alpha: alpha)
            case .low: color = .systemOrange.withAlphaComponent(alpha)
            case .critical: color = .systemRed.withAlphaComponent(alpha)
            }
            NSGraphicsContext.saveGraphicsState()
            cup.addClip()
            color.setFill()
            NSBezierPath(rect: NSRect(x: 2, y: 0, width: 14, height: 2 + 12 * fraction)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        outline.setStroke()
        cup.lineWidth = 1.2
        cup.lineJoinStyle = .round
        cup.stroke()
        let details = NSBezierPath()
        details.move(to: NSPoint(x: 2, y: 15.5))
        details.line(to: NSPoint(x: 16, y: 15.5))
        details.move(to: NSPoint(x: 9, y: 16))
        details.line(to: NSPoint(x: 8, y: 19))
        for y: CGFloat in [5, 8, 11] {
            details.move(to: NSPoint(x: 11, y: y))
            details.line(to: NSPoint(x: 13, y: y))
        }
        details.lineWidth = 1
        details.lineCapStyle = .round
        details.stroke()
        if remaining == nil {
            let dot = NSBezierPath(ovalIn: NSRect(x: 7.5, y: 7, width: 2, height: 2))
            outline.setFill()
            dot.fill()
        }
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = tr("Codex 剩余额度", "Codex usage remaining")
    return image
}
