import Foundation

/// A capture handed to the app by the Share Extension (or another entry point) and waiting to be processed.
struct InboxItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case image
        case pdf
        case text
        case url
    }

    var id: UUID
    var kind: Kind
    /// File name inside `AppGroup.inboxURL` for image/pdf payloads.
    var fileName: String?
    /// Inline payload for text/url kinds.
    var text: String?
    var createdAt: Date
    var sourceApp: String?

    init(id: UUID = UUID(), kind: Kind, fileName: String? = nil, text: String? = nil, createdAt: Date = .now, sourceApp: String? = nil) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.text = text
        self.createdAt = createdAt
        self.sourceApp = sourceApp
    }

    var fileURL: URL? {
        guard let fileName else { return nil }
        return AppGroup.inboxURL.appendingPathComponent(fileName)
    }
}

/// Thin file-based queue in the app group container. Safe to use from the extension and the app.
struct InboxStore {
    private let directory: URL
    private let manifestName = "manifest.json"

    init(directory: URL = AppGroup.inboxURL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var manifestURL: URL { directory.appendingPathComponent(manifestName) }

    func load() -> [InboxItem] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder.lever.decode([InboxItem].self, from: data)) ?? []
    }

    func save(_ items: [InboxItem]) {
        guard let data = try? JSONEncoder.lever.encode(items) else { return }
        try? data.write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    func append(_ item: InboxItem) {
        var items = load()
        items.append(item)
        save(items)
    }

    /// Writes binary payload into the inbox and returns the created item.
    func store(data: Data, kind: InboxItem.Kind, fileExtension: String, sourceApp: String? = nil) -> InboxItem? {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension)"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        let item = InboxItem(id: id, kind: kind, fileName: fileName, sourceApp: sourceApp)
        append(item)
        return item
    }

    func remove(_ item: InboxItem) {
        var items = load()
        items.removeAll { $0.id == item.id }
        save(items)
        if let url = item.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeAll() {
        for item in load() { remove(item) }
        save([])
    }
}

extension JSONEncoder {
    static var lever: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var lever: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
