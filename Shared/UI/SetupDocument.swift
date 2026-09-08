import SwiftUI
import UniformTypeIdentifiers

/// A setup file on its way through `fileExporter`, which wants a `FileDocument` and not a
/// `Data`. It reads as well as writes: nothing opens one of these yet, but the read half is
/// three lines and leaving it out would only mean writing it again for the import side.
struct SetupDocument: FileDocument {
    static let readableContentTypes = [UTType.json]

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
