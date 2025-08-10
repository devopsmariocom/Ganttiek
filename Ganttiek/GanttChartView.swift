import SwiftUI

struct GanttChartView: View {
    var tasks: [GanttTask]

    private var minDate: Date {
        let s = tasks.map(\.start).min() ?? Date()
        return Calendar.current.date(byAdding: .day, value: -2, to: s) ?? s
    }
    private var maxDate: Date {
        let e = tasks.map(\.clampedEnd).max() ?? Date()
        return Calendar.current.date(byAdding: .day, value: 2, to: e) ?? e
    }
    private var totalDays: Int {
        max(Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Mřížka po dnech
                Canvas { ctx, size in
                    let dayWidth = size.width / CGFloat(totalDays)
                    let line = Path { p in
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: 0, y: size.height))
                    }
                    for d in 0...totalDays {
                        let x = CGFloat(d) * dayWidth
                        let lw: CGFloat = d % 7 == 0 ? 1.2 : 0.5
                        ctx.stroke(line.applying(.init(translationX: x, y: 0)),
                                   with: .color(.gray.opacity(0.18)),
                                   lineWidth: lw)
                    }
                }

                // Úkoly
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, t in
                        GanttRow(task: t, minDate: minDate, maxDate: maxDate, index: idx)
                            .frame(height: 28)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct GanttRow: View {
    let task: GanttTask
    let minDate: Date
    let maxDate: Date
    let index: Int

    var body: some View {
        GeometryReader { geo in
            let totalDays = max(Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 1, 1)
            let pxPerDay = geo.size.width / CGFloat(totalDays)
            let startOffset = Calendar.current.dateComponents([.day], from: minDate, to: task.start).day ?? 0
            let duration = max(Calendar.current.dateComponents([.day], from: task.start, to: task.clampedEnd).day ?? 1, 1)

            let x = CGFloat(startOffset) * pxPerDay
            let w = CGFloat(duration) * pxPerDay

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(task.color.color.opacity(0.85))
                    .frame(width: w)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(task.color.color.opacity(0.95), lineWidth: 1)
                    )
                    .offset(x: x)

                Text(task.name)
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
