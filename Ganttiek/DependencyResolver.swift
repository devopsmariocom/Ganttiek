import Foundation

enum ScheduleError: Error, LocalizedError {
    case cycleDetected([UUID])
    var errorDescription: String? {
        switch self {
        case .cycleDetected(let path): return "Dependency cycle detected: \(path.map { $0.uuidString }.joined(separator: " -> "))"
        }
    }
}

struct DependencyResolver {
    static func resolve(_ tasks: [GanttTask]) throws -> [ResolvedTask] {
        let cal = Calendar.current
        let dict = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var memo = [UUID: (Date, Date)]()
        var visiting = Set<UUID>()
        var result = [ResolvedTask]()

        func schedule(_ id: UUID) throws -> (Date, Date) {
            if let v = memo[id] { return v }
            guard let t = dict[id] else { return (Date(), Date()) }
            if visiting.contains(id) { throw ScheduleError.cycleDetected([id]) }
            visiting.insert(id)

            // planned
            let duration = max(t.durationDays, 1)
            var start = t.start

            if let predId = t.predecessorId, let pred = dict[predId] {
                let (ps, pe) = try schedule(pred.id) // recurse
                // Finish→Start with lag days
                let fs = cal.date(byAdding: .day, value: t.lagDays, to: pe) ?? pe
                start = max(t.start, fs)
                _ = ps // silence unused
            }

            let end = cal.date(byAdding: .day, value: duration, to: start) ?? start
            visiting.remove(id)
            memo[id] = (start, end)
            return (start, end)
        }

        for t in tasks {
            let (s, e) = try schedule(t.id)
            result.append(.init(id: t.id, task: t, scheduledStart: s, scheduledEnd: e))
        }
        // Stable order: by scheduledStart then name
        result.sort {
            $0.scheduledStart == $1.scheduledStart ? $0.task.name < $1.task.name : $0.scheduledStart < $1.scheduledStart
        }
        return result
    }
}
