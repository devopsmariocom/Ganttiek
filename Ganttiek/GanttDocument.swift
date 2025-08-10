import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var ganttJSON: UTType = UTType(exportedAs: "com.ganttiek.project", conformingTo: .json)
}

struct GanttDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.ganttJSON, .json] }
    static var writableContentTypes: [UTType] { [.ganttJSON] }

    var project: GanttProject

    init(project: GanttProject) { self.project = project }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.project = try JSONDecoder().decode(GanttProject.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(project)
        return .init(regularFileWithContents: data)
    }
}
