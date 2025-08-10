import Foundation
import SwiftUI

func sampleTasks() -> [GanttTask] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    return [
        GanttTask(name: "Analýza", start: today, end: cal.date(byAdding: .day, value: 3, to: today)!, color: .init(.blue)),
        GanttTask(name: "Design", start: cal.date(byAdding: .day, value: 2, to: today)!, end: cal.date(byAdding: .day, value: 7, to: today)!, color: .init(.purple)),
        GanttTask(name: "Implementace", start: cal.date(byAdding: .day, value: 6, to: today)!, end: cal.date(byAdding: .day, value: 14, to: today)!, color: .init(.green)),
        GanttTask(name: "Testování", start: cal.date(byAdding: .day, value: 12, to: today)!, end: cal.date(byAdding: .day, value: 18, to: today)!, color: .init(.orange))
    ]
}
