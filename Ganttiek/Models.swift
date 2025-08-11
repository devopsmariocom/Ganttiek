import Foundation
import SwiftUI

// Models.swift (top, after imports)
enum ResizeEdge {
    case start
    case end
}

struct GanttTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var start: Date         // planned start
    var end: Date           // planned end (duration = end-start)
    var color: ColorCodable = .init(.blue)

    // Dependency (single predecessor FS + lag)
    var predecessorId: UUID? = nil
    var lagDays: Int = 0

    var clampedEnd: Date { max(start, end) }
    var durationDays: Int {
        max(Calendar.current.dateComponents([.day], from: start, to: clampedEnd).day ?? 0, 0)
    }
}

struct GanttProject: Codable {
    var title: String
    var tasks: [GanttTask]
}

// Result of scheduling with dependencies
struct ResolvedTask: Identifiable, Hashable {
    let id: UUID
    let task: GanttTask
    let scheduledStart: Date
    let scheduledEnd: Date
}

// SwiftUI Color <-> Codable (macOS+iOS)
struct ColorCodable: Codable, Hashable {
    let r: Double, g: Double, b: Double, a: Double

    init(_ color: Color) {
        #if os(macOS)
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ns.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r = .init(rr); g = .init(gg); b = .init(bb); a = .init(aa)
        #else
        let ui = UIColor(color)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r = .init(rr); g = .init(gg); b = .init(bb); a = .init(aa)
        #endif
    }

    var color: Color {
        #if os(macOS)
        Color(NSColor(deviceRed: r, green: g, blue: b, alpha: a))
        #else
        Color(UIColor(red: r, green: g, blue: b, alpha: a))
        #endif
    }
}
