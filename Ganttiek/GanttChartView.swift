import SwiftUI

struct GanttChartView: View {
    var items: [ResolvedTask]

    private var minDate: Date {
        let s = items.map(\.scheduledStart).min() ?? Date()
        return Calendar.current.date(byAdding: .day, value: -2, to: s) ?? s
    }
    private var maxDate: Date {
        let e = items.map(\.scheduledEnd).max() ?? Date()
        return Calendar.current.date(byAdding: .day, value: 2, to: e) ?? e
    }
    private var totalDays: Int {
        max(Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 1, 1)
    }

    // layout
    private let rowH: CGFloat = 28
    private let rowSpacing: CGFloat = 8
    private let topPad: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let pxPerDay = width / CGFloat(totalDays)

            // Precompute bar frames to draw connectors
            let frames: [UUID: (x: CGFloat, w: CGFloat, yMid: CGFloat)] = {
                var acc: [UUID: (CGFloat, CGFloat, CGFloat)] = [:]
                for (idx, r) in items.enumerated() {
                    let startOff = Calendar.current.dateComponents([.day], from: minDate, to: r.scheduledStart).day ?? 0
                    let dur = max(Calendar.current.dateComponents([.day], from: r.scheduledStart, to: r.scheduledEnd).day ?? 1, 1)
                    let x = CGFloat(startOff) * pxPerDay
                    let w = CGFloat(dur) * pxPerDay
                    let yMid = topPad + CGFloat(idx) * (rowH + rowSpacing) + rowH/2
                    acc[r.id] = (x, w, yMid)
                }
                return acc
            }()

            ZStack(alignment: .topLeading) {
                // Grid
                Canvas { ctx, size in
                    let line = Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: 0, y: size.height))
                    }
                    for d in 0...totalDays {
                        let x = CGFloat(d) * (size.width / CGFloat(totalDays))
                        ctx.stroke(line.applying(.init(translationX: x, y: 0)),
                                   with: .color(.gray.opacity(0.18)),
                                   lineWidth: d % 7 == 0 ? 1.2 : 0.5)
                    }

                    // Connectors (elbow: right → down/up → right)
                    for (idx, r) in items.enumerated() {
                        guard let pred = r.task.predecessorId,
                              let from = frames[pred],
                              let to = frames[r.id] else { continue }

                        let startPt = CGPoint(x: from.x + from.w, y: from.yMid)
                        let endPt = CGPoint(x: to.x, y: to.yMid)
                        let midX = (startPt.x + endPt.x) / 2

                        var path = Path()
                        path.move(to: startPt)
                        path.addLine(to: CGPoint(x: midX, y: startPt.y))
                        path.addLine(to: CGPoint(x: midX, y: endPt.y))
                        path.addLine(to: endPt)

                        ctx.stroke(path, with: .color(.secondary), lineWidth: 1)

                        // Arrow head at end
                        let arrow: Path = {
                            var p = Path()
                            let ah: CGFloat = 6
                            p.move(to: endPt)
                            p.addLine(to: CGPoint(x: endPt.x - ah, y: endPt.y - ah/2))
                            p.move(to: endPt)
                            p.addLine(to: CGPoint(x: endPt.x - ah, y: endPt.y + ah/2))
                            return p
                        }()
                        ctx.stroke(arrow, with: .color(.secondary), lineWidth: 1)
                    }
                }

                // Bars
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, r in
                        GanttRow(name: r.task.name,
                                 color: r.task.color.color,
                                 start: r.scheduledStart,
                                 end: r.scheduledEnd,
                                 minDate: minDate,
                                 maxDate: maxDate)
                        .frame(height: rowH)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, topPad)
            }
            .frame(width: width, height: height)
        }
    }
}

private struct GanttRow: View {
    let name: String
    let color: Color
    let start: Date
    let end: Date
    let minDate: Date
    let maxDate: Date

    var body: some View {
        GeometryReader { geo in
            let totalDays = max(Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 1, 1)
            let pxPerDay = geo.size.width / CGFloat(totalDays)
            let startOffset = Calendar.current.dateComponents([.day], from: minDate, to: start).day ?? 0
            let duration = max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1, 1)

            let x = CGFloat(startOffset) * pxPerDay
            let w = CGFloat(duration) * pxPerDay

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.85))
                    .frame(width: w)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.95), lineWidth: 1))
                    .offset(x: x)

                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .offset(x: max(x + 2, 2))
            }
        }
    }
}
