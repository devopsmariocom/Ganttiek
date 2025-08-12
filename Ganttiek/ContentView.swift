
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
        let cal = Calendar.current
        project.tasks[i].start = cal.date(byAdding: .day, value: deltaDays, to: project.tasks[i].start) ?? project.tasks[i].start
        project.tasks[i].end   = cal.date(byAdding: .day, value: deltaDays, to: project.tasks[i].end)   ?? project.tasks[i].end
    }

    private func resizeTask(id: UUID, edge: ResizeEdge, deltaDays: Int) {
        guard let i = indexOf(id), deltaDays != 0 else { return }
        let cal = Calendar.current
        switch edge {
        case .start:
            let newStart = cal.date(byAdding: .day, value: deltaDays, to: project.tasks[i].start) ?? project.tasks[i].start
            // clamp to not after end
            project.tasks[i].start = min(newStart, project.tasks[i].end)
        case .end:
            let newEnd = cal.date(byAdding: .day, value: deltaDays, to: project.tasks[i].end) ?? project.tasks[i].end
            project.tasks[i].end = max(newEnd, project.tasks[i].start.addingTimeInterval(24*3600)) // min 1 den
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
        // ponecháme existující lagDays
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
        let df = DateFormatter(); df.dateStyle = .short
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
                    DatePicker("Start", selection: binding.start, displayedComponents: .date)
                    DatePicker("End", selection: binding.end, displayedComponents: .date)
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
        var currentStart = now

        for raw in lines {
            let line = raw.replacingOccurrences(of: "\t", with: "    ") // tabs → 4 spaces
            guard let range = line.range(of: "- [ ]") else { continue }

            let indent = line.distance(from: line.startIndex, to: range.lowerBound)
            let level = indent / 4 // 4 spaces per level

            let name = line[range.upperBound...].trimmingCharacters(in: .whitespaces)

            let id = UUID()
            var predecessorId: UUID? = nil
            if let pred = lastAtLevel[level - 1] {
                predecessorId = pred
            }

            // Dummy duration: 1 day
            let end = Calendar.current.date(byAdding: .day, value: 1, to: currentStart) ?? currentStart

            tasks.append(GanttTask(
                id: id,
                name: name,
                start: currentStart,
                end: end,
                color: .init(.blue),
                predecessorId: predecessorId,
                lagDays: 0
            ))

            lastAtLevel[level] = id
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
