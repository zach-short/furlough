import SwiftUI
import UniformTypeIdentifiers

/// Bridges to `Data` for `fileExporter`, which wants a `FileDocument`. Read support included
/// even though nothing uses it yet — cheap now, needed later for import.
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
