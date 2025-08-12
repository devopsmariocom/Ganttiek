import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pngImage = UTType.png
}

struct PNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pngImage] }
    static var writableContentTypes: [UTType] { [.pngImage] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
