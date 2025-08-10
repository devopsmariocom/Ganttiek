import SwiftUI

struct ContentView: View {
    private var appName: String {
        let n = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return n ?? "Ganttiek"
    }

    @State private var project = GanttProject(title: "Ganttiek", tasks: sampleTasks())

    // File import/export state
    @State private var isImporting = false
    @State private var isExporting = false

    var body: some View {
        NavigationView {
            Sidebar(tasks: $project.tasks,
                    onExportJSON: { isExporting = true },
                    onImportJSON: { isImporting = true },
                    onExportPNG: exportPNG)
            .frame(minWidth: 280)

            VStack {
                GanttChartView(tasks: project.tasks)
                    .padding()
                Divider()
                addTaskForm
                    .padding()
            }
            .navigationTitle(project.title.isEmpty ? appName : project.title)
        }
        .frame(minWidth: 980, minHeight: 620)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.ganttJSON, .json]) { result in
            if case let .success(url) = result, let data = try? Data(contentsOf: url),
               let p = try? JSONDecoder().decode(GanttProject.self, from: data) {
                project = p
            }
        }
        .fileExporter(isPresented: $isExporting,
                      document: GanttDocument(project: project),
                      contentType: .ganttJSON,
                      defaultFilename: (project.title.isEmpty ? appName : project.title) + ".gantt") { _ in }
    }

    private var addTaskForm: some View {
        @State var newName: String = ""
        @State var newStart: Date = .now
        @State var newEnd: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
        @State var newColor: Color = .blue

        return HStack(spacing: 12) {
            TextField("Název úkolu", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            DatePicker("Od", selection: $newStart, displayedComponents: .date)
            DatePicker("Do", selection: $newEnd, displayedComponents: .date)
            ColorPicker("Barva", selection: $newColor)
            Button("Přidat") {
                guard !newName.isEmpty, newEnd >= newStart else { return }
                project.tasks.append(.init(name: newName, start: newStart, end: newEnd, color: .init(newColor)))
                newName = ""
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func exportPNG() {
        #if os(macOS)
        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        contentView.cacheDisplay(in: bounds, to: rep)
        if let tiff = rep.tiffRepresentation,
           let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            saveData(data, suggested: (project.title.isEmpty ? appName : project.title) + ".png")
        }
        #else
        // iOS snapshot celé okno a otevření share sheetu
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { ctx in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            presentShare(data: data, filename: (project.title.isEmpty ? appName : project.title) + ".png")
        }
        #endif
    }

    #if os(macOS)
    private func saveData(_ data: Data, suggested: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
    #else
    private func presentShare(data: Data, filename: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tmp)
        let vc = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true)
    }
    #endif
}

private struct Sidebar: View {
    @Binding var tasks: [GanttTask]
    var onExportJSON: () -> Void
    var onImportJSON: () -> Void
    var onExportPNG: () -> Void

    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Úkoly").font(.headline)
                Spacer()
                Button { onImportJSON() } label: { Image(systemName: "square.and.arrow.down.on.square") }
                    .help("Importovat projekt (JSON)")
                Button { onExportJSON() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Exportovat projekt (JSON)")
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
                } label: { Label("Smazat", systemImage: "trash") }
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
