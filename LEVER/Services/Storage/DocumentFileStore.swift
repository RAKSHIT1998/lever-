import Foundation

/// Stores captured originals on disk with complete file protection. Never leaves the device.
struct DocumentFileStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("LEVER/Documents", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
    }

    func write(_ data: Data, extension ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    func read(_ fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
    }

    var totalBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// A captured payload plus how to store it.
struct CaptureFile: Sendable {
    let data: Data
    let kind: StoredDocument.Kind
    let fileExtension: String

    static func image(_ data: Data) -> CaptureFile { CaptureFile(data: data, kind: .image, fileExtension: "jpg") }
    static func pdf(_ data: Data) -> CaptureFile { CaptureFile(data: data, kind: .pdf, fileExtension: "pdf") }
}
