
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State private var isExportingPNG = false
    @State private var exportDoc = PNGDocument(data: Data())   // <-- non-optional
    @State private var exportError: String? = nil
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var pasteError: String? = nil
    
    private var appName: String {
        let n = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return n ?? "Ganttiek"
    }

    @State private var project = GanttProject(title: "Ganttiek", tasks: sampleTasks())

    // Selection
    @State private var selectedTaskId: UUID? = nil

    // iOS importer helper
    #if os(iOS)
    @State private var isImporting = false
    #endif

    // MARK: - Time granularity: quarter-day (6 hours)
    private let quarterHours: Int = 6
    private let minTaskDuration: TimeInterval = 6 * 3600 // 1 quarter-day

    private func roundDownToQuarter(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        let hour = comps.hour ?? 0
        let flooredHour = (hour / quarterHours) * quarterHours
        return cal.date(bySettingHour: flooredHour, minute: 0, second: 0, of: date) ?? date
    }

    private func roundUpToQuarter(_ date: Date) -> Date {
        let cal = Calendar.current
        let down = roundDownToQuarter(date)
        if down == date { return down }
        return cal.date(byAdding: .hour, value: quarterHours, to: down) ?? date
    }

    private func addQuarterHours(_ date: Date, quarters: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: quarterHours * quarters, to: date) ?? date
    }

    /// Shift a task and all of its dependent successors by `delta` seconds.
    private func shiftTaskAndSuccessors(from startId: UUID, delta: TimeInterval) {
        guard delta != 0 else { return }
        // Build quick lookups
        var idToIndex: [UUID: Int] = [:]
        for (i, t) in project.tasks.enumerated() { idToIndex[t.id] = i }

        var visited: Set<UUID> = []
        var queue: [UUID] = [startId]
        while let current = queue.first {
            queue.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            if let idx = idToIndex[current] {
                project.tasks[idx].start = project.tasks[idx].start.addingTimeInterval(delta)
                project.tasks[idx].end   = project.tasks[idx].end.addingTimeInterval(delta)
            }
            // Enqueue direct successors
            for t in project.tasks where t.predecessorId == current {
                queue.append(t.id)
            }
        }
    }

    private var resolved: [ResolvedTask] {
        (try? DependencyResolver.resolve(project.tasks)) ?? project.tasks.map {
            ResolvedTask(id: $0.id, task: $0, scheduledStart: $0.start, scheduledEnd: $0.clampedEnd)
        }
    }

    var body: some View {
        NavigationView {
            Sidebar(tasks: $project.tasks,
                    selectedTaskId: $selectedTaskId,
                    onExportJSON: exportJSON,
                    onImportJSON: importJSON,
                    onExportPNG: exportPNG,
                    onPasteFromClipboard: importFromClipboardIndentedChecklist)
            .frame(minWidth: 320)

            // Chart + Inspector
            VStack(spacing: 0) {
                GanttChartView(
                    items: resolved,
                    selectedId: selectedTaskId,
                    onSelect: { selectedTaskId = $0 },
                    onMove: moveTask(id:deltaDays:),
                    onResize: resizeTask(id:edge:deltaDays:),
                    onClearDependency: clearDependency(of:),
                    onSetDependencyFromSelected: setDependencyFromSelected(toPredecessor:)
                )
                .padding()
                Divider()
                InspectorView(
                    project: $project,
                    selectedTaskId: $selectedTaskId,
                    onClearDependency: clearDependency(of:)
                )
                .padding()
            }
            .navigationTitle(project.title.isEmpty ? appName : project.title)
        }
        .frame(minWidth: 1100, minHeight: 680)
        #if os(iOS)
        .overlay(ActivityPresenter(show: $showShare, items: shareItems))
        #else
        .overlay(SharePresenter(show: $showShare, items: shareItems))
        #endif
        #if os(iOS)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result,
               let data = try? Data(contentsOf: url),
               let p = try? JSONDecoder().decode(GanttProject.self, from: data) {
                project = p
            }
        }
        #endif
        .alert("Paste failed", isPresented: Binding(
            get: { pasteError != nil },
            set: { _ in pasteError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pasteError ?? "")
        }
    }

    // MARK: - Mutations
    private func indexOf(_ id: UUID) -> Int? {
        project.tasks.firstIndex(where: { $0.id == id })
    }

    private func moveTask(id: UUID, deltaDays: Int) {
        guard let i = indexOf(id), deltaDays != 0 else { return }
        // Interpret `deltaDays` as number of quarter-day steps (for drag/drop fine control)
        let cal = Calendar.current
        let deltaHours = quarterHours * deltaDays
        project.tasks[i].start = addQuarterHours(roundDownToQuarter(project.tasks[i].start), quarters: deltaDays)
        project.tasks[i].end   = addQuarterHours(roundDownToQuarter(project.tasks[i].end),   quarters: deltaDays)
        // Ensure min duration
        if project.tasks[i].end.timeIntervalSince(project.tasks[i].start) < minTaskDuration {
            project.tasks[i].end = cal.date(byAdding: .second, value: Int(minTaskDuration), to: project.tasks[i].start) ?? project.tasks[i].start.addingTimeInterval(minTaskDuration)
        }
    }

    private func resizeTask(id: UUID, edge: ResizeEdge, deltaDays: Int) {
        guard let i = indexOf(id), deltaDays != 0 else { return }
        let cal = Calendar.current
        switch edge {
        case .start:
            let proposed = addQuarterHours(roundDownToQuarter(project.tasks[i].start), quarters: deltaDays)
            // clamp to not after end - min duration
            let latestAllowed = project.tasks[i].end.addingTimeInterval(-minTaskDuration)
            let clamped = min(proposed, latestAllowed)
            project.tasks[i].start = roundDownToQuarter(clamped)
        case .end:
            let proposed = addQuarterHours(roundDownToQuarter(project.tasks[i].end), quarters: deltaDays)
            // enforce minimum duration
            let earliestAllowed = project.tasks[i].start.addingTimeInterval(minTaskDuration)
            let clamped = max(proposed, earliestAllowed)
            project.tasks[i].end = roundUpToQuarter(clamped)
        }
    }

    private func clearDependency(of id: UUID) {
        guard let i = indexOf(id) else { return }
        project.tasks[i].predecessorId = nil
        project.tasks[i].lagDays = 0
    }

    /// Set "selected task" to depend on `predecessorId`
    private func setDependencyFromSelected(toPredecessor predecessorId: UUID) {
        guard let sel = selectedTaskId, let i = indexOf(sel), sel != predecessorId else { return }
        project.tasks[i].predecessorId = predecessorId
        // Move selected task to start right after predecessor (next quarter boundary)
        if let predIndex = indexOf(predecessorId) {
            let oldStart = project.tasks[i].start
            let newStart = roundUpToQuarter(project.tasks[predIndex].end)
            let delta = newStart.timeIntervalSince(oldStart)
            if delta != 0 {
                shiftTaskAndSuccessors(from: project.tasks[i].id, delta: delta)
            }
        }
        // preserve existing lagDays value
    }

    // MARK: - Import / Export JSON (same as before)
    func exportJSON() {
        do {
            let data = try JSONEncoder().encode(project)
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (project.title.isEmpty ? appName : project.title) + ".gantt.json"
            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url) }
            #else
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent((project.title.isEmpty ? appName : project.title) + ".gantt.json")
            try? data.write(to: tmp)
            presentShare(url: tmp)
            #endif
        } catch { print("Export JSON error:", error) }
    }

    func importJSON() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let p = try JSONDecoder().decode(GanttProject.self, from: data)
                self.project = p
            } catch { print("Import JSON error:", error) }
        }
        #else
        isImporting = true
        #endif
    }

    // MARK: - Paste from Clipboard (Indented Checklist)
    @MainActor
    func importFromClipboardIndentedChecklist() {
        #if os(macOS)
        guard let text = NSPasteboard.general.string(forType: .string) else {
            pasteError = "Clipboard is empty or not text."; return
        }
        #else
        guard let text = UIPasteboard.general.string else {
            pasteError = "Clipboard is empty or not text."; return
        }
        #endif
        let parsed = ChecklistParser.parseIndentedChecklist(text)
        self.project = parsed
    }

    /// Pure function used by tests to render the chart into PNG data.
    /// Runs on main actor because it touches UI objects.
    @MainActor
    static func renderChartPNG(items: [ResolvedTask], size: CGSize) -> Data? {
        let chart = GanttChartView(
            items: items,
            selectedId: nil,
            onSelect: { _ in }, onMove: {_,_ in}, onResize: {_,_,_ in},
            onClearDependency: { _ in }, onSetDependencyFromSelected: { _ in }
        )
        .frame(width: size.width, height: size.height)
        .padding()

        #if os(macOS)
        // Off-screen window snapshot (robust for tests too)
        let host = NSHostingView(rootView: chart)
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.orderOut(nil)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            win.contentView = nil; win.close(); return nil
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        win.contentView = nil
        win.close()
        return data
        #else
        if #available(iOS 16.0, *) {
            let r = ImageRenderer(content: chart); r.scale = 2
            return r.uiImage?.pngData()
        } else {
            let vc = UIHostingController(rootView: chart)
            vc.view.bounds = CGRect(origin: .zero, size: size)
            vc.view.backgroundColor = .clear
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2
            let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                vc.view.drawHierarchy(in: vc.view.bounds, afterScreenUpdates: true)
            }
            return img.pngData()
        }
        #endif
    }

    @MainActor
    func exportPNG() {
        let exportSize = CGSize(width: 1600, height: 900)
        guard let data = ContentView.renderChartPNG(items: resolved, size: exportSize) else {
            exportError = "Failed to render PNG data"; return
        }
#if os(macOS)
        if let img = NSImage(data: data) {
            shareItems = [img]
        } else {
            shareItems = [data]
        }
        showShare = true
#else
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent((project.title.isEmpty ? appName : project.title) + ".png")
        try? data.write(to: tmp)
        shareItems = [tmp]
        showShare = true
#endif
    }

    #if os(iOS)
    private func presentShare(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true)
    }
    #endif
}

// MARK: - Sidebar with selection + quick add
private struct Sidebar: View {
    @Binding var tasks: [GanttTask]
    @Binding var selectedTaskId: UUID?
    var onExportJSON: () -> Void
    var onImportJSON: () -> Void
    var onExportPNG: () -> Void
    var onPasteFromClipboard: () -> Void

    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tasks").font(.headline)
                Spacer()
                Button { onImportJSON() } label: { Image(systemName: "square.and.arrow.down.on.square") }
                Button { onPasteFromClipboard() } label: { Image(systemName: "doc.on.clipboard") }
                    .help("Paste from clipboard")
                Button { onExportPNG() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Share PNG")
            }

            List(selection: $selectedTaskId) {
                ForEach(tasks) { t in
                    HStack {
                        Circle().fill(t.color.color).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.system(size: 13, weight: .medium))
                            Text(dateRange(t.start, t.clampedEnd)).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    .tag(t.id)
                    .contextMenu {
                        Button("Remove dependency") {
                            if let i = tasks.firstIndex(where: {$0.id == t.id}) {
                                tasks[i].predecessorId = nil; tasks[i].lagDays = 0
                            }
                        }
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { tasks[$0].id }
                    tasks.remove(atOffsets: idx)
                    if let sel = selectedTaskId, ids.contains(sel) { selectedTaskId = nil }
                }
            }
            .listStyle(.inset)

            HStack {
                TextField("New task…", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    guard !draftName.isEmpty else { return }
                    let now = Calendar.current.startOfDay(for: Date())
                    let t = GanttTask(name: draftName,
                                      start: now, end: Calendar.current.date(byAdding: .day, value: 3, to: now)!,
                                      color: .init(.blue))
                    tasks.append(t)
                    draftName = ""; selectedTaskId = t.id
                }
            }
            HStack {
                Button(role: .destructive) {
                    if let sel = selectedTaskId,
                       let i = tasks.firstIndex(where: { $0.id == sel }) {
                        tasks.remove(at: i); selectedTaskId = nil
                    }
                } label: { Label("Delete", systemImage: "trash") }
                .disabled(selectedTaskId == nil)

                Spacer()
            }
        }
        .padding()
    }

    private func dateRange(_ s: Date, _ e: Date) -> String {
        let df = DateFormatter();
        df.dateStyle = .short
        df.timeStyle = .short
        return "\(df.string(from: s)) – \(df.string(from: e))"
    }
}

// MARK: - Inspector (manual edits)
private struct InspectorView: View {
    @Binding var project: GanttProject
    @Binding var selectedTaskId: UUID?
    var onClearDependency: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspector").font(.headline)
            if let id = selectedTaskId,
               let idx = project.tasks.firstIndex(where: {$0.id == id}) {
                let binding = $project.tasks[idx]
                TextField("Name", text: binding.name)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    DatePicker("Start", selection: binding.start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: binding.end, displayedComponents: [.date, .hourAndMinute])
                }
                ColorPicker("Color", selection: Binding(
                    get: { binding.wrappedValue.color.color },
                    set: { binding.wrappedValue.color = .init($0) }
                ))

                // Dependency
                Picker("Depends on", selection: Binding(
                    get: { binding.wrappedValue.predecessorId },
                    set: { binding.wrappedValue.predecessorId = $0 }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(project.tasks.filter { $0.id != id }) { t in
                        Text(t.name).tag(UUID?.some(t.id))
                    }
                }
                HStack {
                    Stepper("Lag \(binding.lagDays.wrappedValue)d", value: binding.lagDays, in: 0...60)
                    Spacer()
                    Button("Remove dependency") { onClearDependency(id) }
                        .disabled(binding.predecessorId.wrappedValue == nil)
                }
            } else {
                Text("Select a task to edit").foregroundColor(.secondary)
            }
        }
    }
}

#if os(iOS)
private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}
#endif

struct ChecklistParser {
    static func parseIndentedChecklist(_ text: String) -> GanttProject {
        var tasks: [GanttTask] = []
        var lastAtLevel: [Int: UUID] = [:]
        let lines = text.components(separatedBy: .newlines)

        let now = Date()
        // Start at the next quarter boundary from now
        var currentStart = Calendar.current.startOfDay(for: now)
        let cal = Calendar.current
        func roundUp(_ d: Date) -> Date {
            let hour = cal.component(.hour, from: d)
            let floored = (hour / 6) * 6
            let base = cal.date(bySettingHour: floored, minute: 0, second: 0, of: d) ?? d
            return base == d ? base : cal.date(byAdding: .hour, value: 6, to: base) ?? d
        }
        currentStart = roundUp(currentStart)

        for raw in lines {
            let line = raw.replacingOccurrences(of: "\t", with: "    ") // tabs → 4 spaces
            guard let range = line.range(of: "- [ ]") else { continue }

            let indent = line.distance(from: line.startIndex, to: range.lowerBound)
            let level = indent / 4 // 4 spaces per level

            let name = line[range.upperBound...].trimmingCharacters(in: .whitespaces)

            let id = UUID()
            var predecessorId: UUID? = nil
            if let pred = lastAtLevel[level - 1] { predecessorId = pred }

            // Quarter-day duration (6 hours)
            let end = cal.date(byAdding: .hour, value: 6, to: currentStart) ?? currentStart

            // Generate a random color for each task
            let randomColor = Color(hue: Double.random(in: 0...1), saturation: 0.7, brightness: 0.9)

            tasks.append(GanttTask(
                id: id,
                name: name,
                start: currentStart,
                end: end,
                color: .init(randomColor),
                predecessorId: predecessorId,
                lagDays: 0
            ))

            lastAtLevel[level] = id
            // Next task starts right after this one, on a quarter boundary
            currentStart = end
        }

        return GanttProject(title: "Imported Checklist", tasks: tasks)
    }
}


#if os(iOS)
import UIKit
struct ActivityPresenter: UIViewControllerRepresentable {
    @Binding var show: Bool
    let items: [Any]
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        if show && vc.presentedViewController == nil {
            let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
            vc.present(av, animated: true)
            DispatchQueue.main.async { self.show = false }
        }
    }
}
#elseif os(macOS)
struct SharePresenter: NSViewRepresentable {
    @Binding var show: Bool
    let items: [Any]
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        if show {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            DispatchQueue.main.async { self.show = false }
        }
    }
}
#endif
