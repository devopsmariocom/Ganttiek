import Foundation
import SwiftUI

func sampleTasks() -> [GanttTask] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())

    let a = GanttTask(
        name: "Analýza",
        start: today,
        end: cal.date(byAdding: .day, value: 3, to: today)!,
        color: .init(.blue)
    )
    let b = GanttTask(
        name: "Design",
        start: cal.date(byAdding: .day, value: 2, to: today)!,
        end: cal.date(byAdding: .day, value: 7, to: today)!,
        color: .init(.purple),
        predecessorId: a.id, lagDays: 1
    )
    let c = GanttTask(
        name: "Implementace",
        start: cal.date(byAdding: .day, value: 6, to: today)!,
        end: cal.date(byAdding: .day, value: 14, to: today)!,
        color: .init(.green),
        predecessorId: b.id, lagDays: 0
    )
    let d = GanttTask(
        name: "Testování",
        start: cal.date(byAdding: .day, value: 12, to: today)!,
        end: cal.date(byAdding: .day, value: 18, to: today)!,
        color: .init(.orange),
        predecessorId: c.id, lagDays: 2
    )
    return [a, b, c, d]
}
