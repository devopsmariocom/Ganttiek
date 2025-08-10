import Foundation
import SwiftUI

struct GanttTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var start: Date
    var end: Date
    var color: ColorCodable = .init(.blue)

    var clampedEnd: Date { max(start, end) }
    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: start, to: clampedEnd).day ?? 0
    }
}

struct GanttProject: Codable {
    var title: String
    var tasks: [GanttTask]
}

// Cross-platform Color <-> Codable
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
        return Color(NSColor(deviceRed: r, green: g, blue: b, alpha: a))
        #else
        return Color(UIColor(red: r, green: g, blue: b, alpha: a))
        #endif
    }
}
