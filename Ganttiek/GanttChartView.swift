import SwiftUI

struct GanttChartView: View {
    var items: [ResolvedTask]

    // Selection + actions injected z ContentView
    var selectedId: UUID?
    var onSelect: (UUID) -> Void
    var onMove: (_ id: UUID, _ deltaDays: Int) -> Void
    var onResize: (_ id: UUID, _ edge: ResizeEdge, _ deltaDays: Int) -> Void
    var onClearDependency: (_ id: UUID) -> Void
    var onSetDependencyFromSelected: (_ predecessorId: UUID) -> Void

    // timeline
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
    private let handleW: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let pxPerDay = width / CGFloat(totalDays)

            // Precompute frames
            let frames: [UUID: (x: CGFloat, w: CGFloat, yMid: CGFloat, yTop: CGFloat)] = {
                var acc: [UUID: (CGFloat, CGFloat, CGFloat, CGFloat)] = [:]
                for (idx, r) in items.enumerated() {
                    let startOff = Calendar.current.dateComponents([.day], from: minDate, to: r.scheduledStart).day ?? 0
                    let dur = max(Calendar.current.dateComponents([.day], from: r.scheduledStart, to: r.scheduledEnd).day ?? 1, 1)
                    let x = CGFloat(startOff) * pxPerDay
                    let w = CGFloat(dur) * pxPerDay
                    let yTop = topPad + CGFloat(idx) * (rowH + rowSpacing)
                    let yMid = yTop + rowH/2
                    acc[r.id] = (x, w, yMid, yTop)
                }
                return acc
            }()

            ZStack(alignment: .topLeading) {
                // Grid + Connectors
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
                    // connectors
                    for r in items {
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

                        var arrow = Path()
                        let ah: CGFloat = 6
                        arrow.move(to: endPt)
                        arrow.addLine(to: CGPoint(x: endPt.x - ah, y: endPt.y - ah/2))
                        arrow.move(to: endPt)
                        arrow.addLine(to: CGPoint(x: endPt.x - ah, y: endPt.y + ah/2))
                        ctx.stroke(arrow, with: .color(.secondary), lineWidth: 1)
                    }
                }

                // Bars with interactions
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(items) { r in
                        InteractiveBar(
                            id: r.id,
                            name: r.task.name,
                            color: r.task.color.color,
                            start: r.scheduledStart,
                            end: r.scheduledEnd,
                            minDate: minDate,
                            maxDate: maxDate,
                            isSelected: r.id == selectedId,
                            handleW: handleW,
                            onSelect: onSelect,
                            onMoveDays: { deltaDays in onMove(r.id, deltaDays) },
                            onResizeDays: { edge, delta in onResize(r.id, edge, delta) },
                            onClearDependency: { onClearDependency(r.id) },
                            onSetAsPredecessorOfSelected: { onSetDependencyFromSelected(r.id) }
                        )
                        .frame(height: rowH)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, topPad)
            }
        }
    }
}

// MARK: - Interactive bar (drag, resize, context menu)
private struct InteractiveBar: View {
    let id: UUID
    let name: String
    let color: Color
    let start: Date
    let end: Date
    let minDate: Date
    let maxDate: Date
    let isSelected: Bool
    let handleW: CGFloat

    var onSelect: (UUID) -> Void
    var onMoveDays: (Int) -> Void
    var onResizeDays: (ResizeEdge, Int) -> Void
    var onClearDependency: () -> Void
    var onSetAsPredecessorOfSelected: () -> Void

    @State private var dragAccumPx: CGFloat = 0
    @State private var resizeAccumPx: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalDays = max(Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 1, 1)
            let pxPerDay = geo.size.width / CGFloat(totalDays)
            let startOffset = Calendar.current.dateComponents([.day], from: minDate, to: start).day ?? 0
            let duration = max(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1, 1)
            let x = CGFloat(startOffset) * pxPerDay
            let w = CGFloat(duration) * pxPerDay

            let base = RoundedRectangle(cornerRadius: 6)
            let stroke = base.strokeBorder(color.opacity(0.95), lineWidth: isSelected ? 2 : 1)

            ZStack(alignment: .leading) {
                // Main bar (drag to move)
                base.fill(color.opacity(0.85))
                    .frame(width: w)
                    .overlay(stroke)
                    .offset(x: x)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                dragAccumPx += g.translation.width
                                let days = Int(dragAccumPx / pxPerDay)
                                if days != 0 {
                                    onMoveDays(days)
                                    dragAccumPx -= CGFloat(days) * pxPerDay
                                }
                            }
                            .onEnded { _ in dragAccumPx = 0 }
                    )
                    .onTapGesture { onSelect(id) }
                    .contextMenu {
                        Button("Set as predecessor of selected") { onSetAsPredecessorOfSelected() }
                        Button("Clear dependency") { onClearDependency() }
                    }

                // Left handle (resize start)
                Rectangle()
                    .fill(Color.black.opacity(0.0001)) // hit area
                    .frame(width: handleW, height: 28)
                    .offset(x: x)
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                resizeAccumPx += g.translation.width
                                let days = Int(resizeAccumPx / pxPerDay)
                                if days != 0 {
                                    onResizeDays(.start, days)
                                    resizeAccumPx -= CGFloat(days) * pxPerDay
                                }
                            }
                            .onEnded { _ in resizeAccumPx = 0 }
                    )

                // Right handle (resize end)
                Rectangle()
                    .fill(Color.black.opacity(0.0001))
                    .frame(width: handleW, height: 28)
                    .offset(x: x + w - handleW)
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                resizeAccumPx += g.translation.width
                                let days = Int(resizeAccumPx / pxPerDay)
                                if days != 0 {
                                    onResizeDays(.end, days)
                                    resizeAccumPx -= CGFloat(days) * pxPerDay
                                }
                            }
                            .onEnded { _ in resizeAccumPx = 0 }
                    )

                // Label
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
