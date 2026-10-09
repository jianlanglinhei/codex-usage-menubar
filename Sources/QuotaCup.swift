import SwiftUI

/// A calibrated cup: the liquid surface and scale share the same 0–100 axis.
struct QuotaCup: View {
    let remaining: Int

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 100, y: size.height / 140)
            let ink = Color(red: 0.34, green: 0.19, blue: 0.10)
            let coffee = Color(red: 0.86, green: 0.55, blue: 0.25)
            let fraction = CGFloat(min(100, max(0, remaining))) / 100
            let surface = 121 - 87 * fraction
            let cup = Path { p in
                p.move(to: CGPoint(x: 14, y: 28))
                p.addLine(to: CGPoint(x: 86, y: 28))
                p.addLine(to: CGPoint(x: 76, y: 123))
                p.addQuadCurve(to: CGPoint(x: 24, y: 123), control: CGPoint(x: 50, y: 136))
                p.closeSubpath()
            }
            context.fill(cup, with: .color(Color(red: 0.98, green: 0.94, blue: 0.85)))
            var liquid = context
            liquid.clip(to: cup)
            if fraction > 0 {
                liquid.fill(Path(CGRect(x: 12, y: surface, width: 76, height: 140 - surface)), with: .color(coffee))
                liquid.fill(Path(ellipseIn: CGRect(x: 12, y: surface - 2, width: 76, height: 4)), with: .color(Color(red: 0.96, green: 0.72, blue: 0.43)))
            }
            context.stroke(cup, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            // Straw and lid sit above the calibrated usable volume.
            let straw = Path { p in
                p.move(to: CGPoint(x: 48, y: 26))
                p.addLine(to: CGPoint(x: 43, y: 5))
            }
            context.stroke(straw, with: .color(ink), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            context.stroke(straw, with: .color(.init(red: 1, green: 0.96, blue: 0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            let lid = Path(roundedRect: CGRect(x: 10, y: 23, width: 80, height: 8), cornerRadius: 4)
            context.fill(lid, with: .color(.init(red: 0.96, green: 0.86, blue: 0.70)))
            context.stroke(lid, with: .color(ink), lineWidth: 2)
            for value in [0, 25, 50, 75, 100] {
                let y = 121 - 87 * CGFloat(value) / 100
                let x = 19 + (y - 34) * 0.10
                let tick = Path { p in
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + 6, y: y))
                }
                context.stroke(tick, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                context.draw(Text("\(value)").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(ink), at: CGPoint(x: x + 9, y: y), anchor: .leading)
            }
            // A small face keeps the cup recognizable without obscuring its scale.
            for x in [CGFloat(60), CGFloat(72)] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 83, width: 3, height: 5)), with: .color(ink))
            }
            let smile = Path { p in
                p.move(to: CGPoint(x: 60, y: 93))
                p.addQuadCurve(to: CGPoint(x: 74, y: 93), control: CGPoint(x: 67, y: 104))
            }
            context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityLabel(tr("剩余额度", "Remaining quota"))
        .accessibilityValue("\(min(100, max(0, remaining)))%")
    }
}
