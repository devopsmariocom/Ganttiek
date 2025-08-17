

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif


#if os(macOS)
extension View {
    /// Cross-version cursor modifier using NSCursor.set() so we don't rely on SwiftUI's `.cursor` API.
    func cursorCompat(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
#endif

struct GanttChartView: View {
    var items: [ResolvedTask]

    // Selection + actions injected z ContentView
    var selectedId: UUID?
    var onSelect: (UUID) -> Void
    var onMove: (_ id: UUID, _ deltaDays: Int) -> Void
    var onResize: (_ id: UUID, _ edge: ResizeEdge, _ deltaDays: Int) -> Void
    var onClearDependency: (_ id: UUID) -> Void
    var onSetDependencyFromSelected: (_ predecessorId: UUID) -> Void

    @State private var hoveredLinkId: UUID? = nil

    // DnD helpers
    private enum DragKind: String { case move, start, end }
    private let quarterSec: TimeInterval = 6 * 3600
    private func roundDownToQuarter(_ d: Date) -> Date {
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        let floored = (h / 6) * 6
        return cal.date(bySettingHour: floored, minute: 0, second: 0, of: d) ?? d
    }
    private func roundUpToQuarter(_ d: Date) -> Date {
        let down = roundDownToQuarter(d)
        if down == d { return down }
        return Calendar.current.date(byAdding: .hour, value: 6, to: down) ?? d
    }

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
        max(Int(ceil(maxDate.timeIntervalSince(minDate) / 86_400.0)), 1)
    }

    // layout
    private let rowH: CGFloat = 28
    private let rowSpacing: CGFloat = 8
    private let topPad: CGFloat = 8
    private let handleW: CGFloat = 8

    // MARK: - Decompose heavy body
    @ViewBuilder
    private func chartBody(width: CGFloat) -> some View {
        let pxPerDay = width / CGFloat(totalDays)
        let frames: [UUID: Frame] = makeFrames(pxPerDay: pxPerDay)

        ZStack(alignment: .topLeading) {
            // Grid + Connectors
            gridAndConnectors(frames: frames, totalDays: totalDays)

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
                    .zIndex(10)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, topPad)

            // Interactive overlays for dependency links (outside Canvas)
            dependencyOverlays(frames: frames)
                .zIndex(5)
        }
        // Enable drop anywhere over the chart using DropDelegate
        .onDrop(of: [UTType.text], delegate: ChartDropDelegate(
            minDate: minDate,
            pxPerDay: pxPerDay,
            items: items,
            onMove: onMove,
            onResize: onResize
        ))
    }



    // Helper types and methods for chartBody
    private typealias Frame = (x: CGFloat, w: CGFloat, yMid: CGFloat, yTop: CGFloat)
    private var daySec: Double { 86_400.0 }
    private func makeFrames(pxPerDay: CGFloat) -> [UUID: Frame] {
        var acc: [UUID: Frame] = [:]
        for (idx, r) in items.enumerated() {
            let startOffDays = CGFloat(max(0.0, r.scheduledStart.timeIntervalSince(minDate) / daySec))
            let durDays = max(CGFloat((r.scheduledEnd.timeIntervalSince(r.scheduledStart)) / daySec), 0.25)
            let x = startOffDays * pxPerDay
            let w = durDays * pxPerDay
            let yTop = topPad + CGFloat(idx) * (rowH + rowSpacing)
            let yMid = yTop + rowH / 2
            acc[r.id] = (x, w, yMid, yTop)
        }
        return acc
    }

    @ViewBuilder
    private func gridAndConnectors(frames: [UUID: Frame], totalDays: Int) -> some View {
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
    }

    @ViewBuilder
    private func dependencyOverlays(frames: [UUID: Frame]) -> some View {
        // Disabled interactive overlays to avoid blocking move/resize hovers
        EmptyView()
    }

    // MARK: - Drop delegate for drag & drop move/resize
    private struct ChartDropDelegate: DropDelegate {
        let minDate: Date
        let pxPerDay: CGFloat
        let items: [ResolvedTask]
        let onMove: (UUID, Int) -> Void
        let onResize: (UUID, ResizeEdge, Int) -> Void

        private let quarterSec: TimeInterval = 6 * 3600
        private let daySec: TimeInterval = 86_400.0

        private func roundDownToQuarter(_ d: Date) -> Date {
            let cal = Calendar.current
            let h = cal.component(.hour, from: d)
            let floored = (h / 6) * 6
            return cal.date(bySettingHour: floored, minute: 0, second: 0, of: d) ?? d
        }
        private func roundUpToQuarter(_ d: Date) -> Date {
            let down = roundDownToQuarter(d)
            if down == d { return down }
            return Calendar.current.date(byAdding: .hour, value: 6, to: down) ?? d
        }

        func performDrop(info: DropInfo) -> Bool {
            guard info.hasItemsConforming(to: [UTType.text]) else { return false }
            let providers = info.itemProviders(for: [UTType.text])
            guard let provider = providers.first else { return false }

            provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let ns = obj as? NSString else { return }
                let s: String = ns as String
                let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let kind = DragKind(rawValue: parts[0]),
                      let id = UUID(uuidString: parts[1]) else { return }

                let x = info.location.x
                let days = max(0.0, Double(x / pxPerDay))
                let target = minDate.addingTimeInterval(days * daySec)

                guard let r = items.first(where: { $0.id == id }) else { return }

                switch kind {
                case .move:
                    let newStart = roundDownToQuarter(target)
                    let deltaQ = Int((newStart.timeIntervalSince(r.scheduledStart)) / quarterSec)
                    if deltaQ != 0 { DispatchQueue.main.async { onMove(id, deltaQ) } }
                case .start:
                    let newStart = roundDownToQuarter(target)
                    let deltaQ = Int((newStart.timeIntervalSince(r.scheduledStart)) / quarterSec)
                    if deltaQ != 0 { DispatchQueue.main.async { onResize(id, .start, deltaQ) } }
                case .end:
                    let newEnd = roundUpToQuarter(target)
                    let deltaQ = Int((newEnd.timeIntervalSince(r.scheduledEnd)) / quarterSec)
                    if deltaQ != 0 { DispatchQueue.main.async { onResize(id, .end, deltaQ) } }
                }
            }
            return true
        }
    }

    var body: some View {
        GeometryReader { geo in
            chartBody(width: geo.size.width)
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

    #if os(macOS)
    @State private var isMoving: Bool = false
    @State private var isResizingStart: Bool = false
    @State private var isResizingEnd: Bool = false
    #endif

    @State private var moveStepsSent: Int = 0
    @State private var resizeStartStepsSent: Int = 0
    @State private var resizeEndStepsSent: Int = 0

    var body: some View {
        GeometryReader { geo in
            let daySec: Double = 86_400.0
            let totalDays = max(Int(ceil(maxDate.timeIntervalSince(minDate) / daySec)), 1)
            let pxPerDay = geo.size.width / CGFloat(totalDays)
            let startOffDays = CGFloat(max(0.0, start.timeIntervalSince(minDate) / daySec))
            let durDays = max(CGFloat((end.timeIntervalSince(start)) / daySec), 0.25)
            let x = startOffDays * pxPerDay
            let w = durDays * pxPerDay

            let base = RoundedRectangle(cornerRadius: 6)
            let stroke = base.strokeBorder(color.opacity(0.95), lineWidth: isSelected ? 2 : 1)

            ZStack(alignment: .leading) {
                // Main bar (drag to move)
                base.fill(color.opacity(0.85))
                    .frame(width: w)
                    .overlay(stroke)
                    .offset(x: x)
                    #if os(macOS)
                    .cursorCompat(isMoving ? NSCursor.closedHand : NSCursor.openHand)
                    #endif
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                #if os(macOS)
                                if !isMoving { isMoving = true }
                                #endif
                                let quartersFloat = (g.translation.width / pxPerDay) * 4.0
                                let quarters = Int(quartersFloat.rounded(.towardZero))
                                let inc = quarters - moveStepsSent
                                if inc != 0 {
                                    onMoveDays(inc)
                                    moveStepsSent += inc
                                }
                            }
                            .onEnded { _ in
                                moveStepsSent = 0
                                #if os(macOS)
                                isMoving = false
                                #endif
                            }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded { onSelect(id) }
                    )
                    .contextMenu {
                        Button("Set as predecessor of selected") { onSetAsPredecessorOfSelected() }
                        Button("Clear dependency") { onClearDependency() }
                    }
                    .onDrag {
                        NSItemProvider(object: NSString(string: "move:\(id.uuidString)"))
                    }

                // Left handle (resize start)
                Rectangle()
                    .fill(Color.black.opacity(0.0001)) // hit area
                    .frame(width: handleW, height: 28)
                    .offset(x: x)
                    #if os(macOS)
                    .cursorCompat(NSCursor.resizeLeftRight)
                    #endif
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                #if os(macOS)
                                if !isResizingStart { isResizingStart = true }
                                #endif
                                let quartersFloat = (g.translation.width / pxPerDay) * 4.0
                                let quarters = Int(quartersFloat.rounded(.towardZero))
                                let inc = quarters - resizeStartStepsSent
                                if inc != 0 {
                                    onResizeDays(.start, inc)
                                    resizeStartStepsSent += inc
                                }
                            }
                            .onEnded { _ in
                                resizeStartStepsSent = 0
                                #if os(macOS)
                                isResizingStart = false
                                #endif
                            }
                    )
                    .onDrag {
                        NSItemProvider(object: NSString(string: "start:\(id.uuidString)"))
                    }

                // Right handle (resize end)
                Rectangle()
                    .fill(Color.black.opacity(0.0001))
                    .frame(width: handleW, height: 28)
                    .offset(x: x + w - handleW)
                    #if os(macOS)
                    .cursorCompat(NSCursor.resizeLeftRight)
                    #endif
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                #if os(macOS)
                                if !isResizingEnd { isResizingEnd = true }
                                #endif
                                let quartersFloat = (g.translation.width / pxPerDay) * 4.0
                                let quarters = Int(quartersFloat.rounded(.towardZero))
                                let inc = quarters - resizeEndStepsSent
                                if inc != 0 {
                                    onResizeDays(.end, inc)
                                    resizeEndStepsSent += inc
                                }
                            }
                            .onEnded { _ in
                                resizeEndStepsSent = 0
                                #if os(macOS)
                                isResizingEnd = false
                                #endif
                            }
                    )
                    .onDrag {
                        NSItemProvider(object: NSString(string: "end:\(id.uuidString)"))
                    }

                // Label
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .offset(x: max(x + 2, 2))
            }
#if os(macOS)
            .cursorCompat(isMoving ? NSCursor.closedHand : NSCursor.openHand)
#endif
            .contentShape(Rectangle())
        }
    }
}

