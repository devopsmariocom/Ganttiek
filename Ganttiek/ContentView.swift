import SwiftUI

struct ContentView: View {
    // App name from bundle (used for titles/exports)
    private var appName: String {
        let n = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return n ?? "Ganttiek"
    }

    // Project state
    @State private var project = GanttProject(title: "Ganttiek", tasks: sampleTasks())

    // Add-task form state
    @State private var newName: String = ""
    @State private var newStart: Date = .now
    @State private var newEnd: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var newColor: Color = .blue
    @State private var newPredecessor: UUID? = nil
    @State private var newLagDays: Int = 0

    // iOS-only helpers
    #if os(iOS)
    @State private var isImporting = false
    #endif

    // Resolve dependencies to scheduled bars
    private var resolved: [ResolvedTask] {
        (try? DependencyResolver.resolve(project.tasks)) ?? project.tasks.map {
            ResolvedTask(id: $0.id, task: $0, scheduledStart: $0.start, scheduledEnd: $0.clampedEnd)
        }
    }

    var body: some View {
        NavigationView {
            Sidebar(tasks: $project.tasks,
                    onExportJSON: exportJSON,
                    onImportJSON: importJSON,
                    onExportPNG: exportPNG)
            .frame(minWidth: 280)

            VStack {
                GanttChartView(items: resolved)
                    .padding()
                Divider()
                addTaskForm
                    .padding()
            }
            .navigationTitle(project.title.isEmpty ? appName : project.title)
        }
        .frame(minWidth: 980, minHeight: 620)
        #if os(iOS)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result,
               let data = try? Data(contentsOf: url),
               let p = try? JSONDecoder().decode(GanttProject.self, from: data) {
                project = p
            }
        }
        #endif
    }

    // MARK: - Add task form
    var addTaskForm: some View {
        HStack(spacing: 12) {
            TextField("Task name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)

            DatePicker("Start", selection: $newStart, displayedComponents: .date)
            DatePicker("End", selection: $newEnd, displayedComponents: .date)

            ColorPicker("Color", selection: $newColor)

            Picker("Depends on", selection: $newPredecessor) {
                Text("None").tag(UUID?.none)
                ForEach(project.tasks) { t in
                    Text(t.name).tag(UUID?.some(t.id))
                }
            }
            .frame(minWidth: 160)

            Stepper("Lag \(newLagDays)d", value: $newLagDays, in: 0...60)

            Button("Add") {
                guard !newName.isEmpty, newEnd >= newStart else { return }
                project.tasks.append(.init(
                    name: newName,
                    start: newStart,
                    end: newEnd,
                    color: .init(newColor),
                    predecessorId: newPredecessor,
                    lagDays: newLagDays
                ))
                newName = ""; newLagDays = 0; newPredecessor = nil
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: - Import / Export JSON
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
        } catch {
            print("Export JSON error:", error)
        }
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

    // MARK: - Export PNG snapshot
    func exportPNG() {
        #if os(macOS)
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        contentView.cacheDisplay(in: bounds, to: rep)
        if let tiff = rep.tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (project.title.isEmpty ? appName : project.title) + ".png"
            if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
        }
        #else
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent((project.title.isEmpty ? appName : project.title) + ".png")
            try? data.write(to: tmp)
            presentShare(url: tmp)
        }
        #endif
    }

    #if os(iOS)
    private func presentShare(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true)
    }
    #endif
}

// MARK: - Sidebar (shared)
private struct Sidebar: View {
    @Binding var tasks: [GanttTask]
    var onExportJSON: () -> Void
    var onImportJSON: () -> Void
    var onExportPNG: () -> Void

    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tasks").font(.headline)
                Spacer()
                Button { onImportJSON() } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .help("Import project (JSON)")
                Button { onExportJSON() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Export project (JSON)")
            }

            List(selection: $selection) {
                ForEach(tasks) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.system(size: 13, weight: .medium))
                        Text(dateRange(t.start, t.clampedEnd)).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .tag(t.id)
                }
                .onDelete { idx in tasks.remove(atOffsets: idx) }
            }
            .listStyle(.inset)

            HStack {
                Button(role: .destructive) {
                    if let sel = selection, let i = tasks.firstIndex(where: { $0.id == sel }) {
                        tasks.remove(at: i); selection = nil
                    }
                } label: { Label("Delete", systemImage: "trash") }
                .disabled(selection == nil)

                Spacer()
                Button { onExportPNG() } label: { Label("Export PNG", systemImage: "photo.on.rectangle.angled") }
            }
        }
        .padding()
    }

    private func dateRange(_ s: Date, _ e: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .short
        return "\(df.string(from: s)) – \(df.string(from: e))"
    }
}
