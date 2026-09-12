import Foundation

/// Pulls items dropped by the Share Extension into capture inputs.
struct InboxImporter {
    let store = InboxStore()

    func pending() -> [InboxItem] { store.load().sorted { $0.createdAt < $1.createdAt } }

    func captureInput(for item: InboxItem) -> (CaptureInput, CaptureFile?)? {
        switch item.kind {
        case .image:
            guard let url = item.fileURL, let data = try? Data(contentsOf: url) else { return nil }
            return (.image(data), .image(data))
        case .pdf:
            guard let url = item.fileURL, let data = try? Data(contentsOf: url) else { return nil }
            return (.pdf(data), .pdf(data))
        case .text:
            guard let text = item.text, !text.isEmpty else { return nil }
            return (.text(text), nil)
        case .url:
            guard let text = item.text, let url = URL(string: text) else { return nil }
            return (.url(url), nil)
        }
    }

    func consume(_ item: InboxItem) { store.remove(item) }
}
