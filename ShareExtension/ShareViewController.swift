import UIKit
import UniformTypeIdentifiers

/// Receives images, PDFs, files, text and web pages from the system share sheet and drops them into the
/// app-group inbox. The main app processes them on next launch. Nothing is uploaded from here.
final class ShareViewController: UIViewController {
    private let store = InboxStore()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var pendingLoads = 0
    private var savedCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        ingest()
    }

    private func buildUI() {
        view.backgroundColor = .clear
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let title = UILabel()
        title.text = "LEVER"
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textColor = .secondaryLabel

        statusLabel.text = "Saving to your vault…"
        statusLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        spinner.startAnimating()

        let stack = UIStackView(arrangedSubviews: [title, spinner, statusLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
        ])
    }

    private func ingest() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { return finish(message: "Nothing to save.") }
        pendingLoads = providers.count
        for provider in providers { load(provider) }
    }

    private func load(_ provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { [weak self] data, _ in
                self?.handle(data: data, kind: .pdf, ext: "pdf")
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                // Normalise to JPEG so the app has one image format to deal with.
                let jpeg = data.flatMap { UIImage(data: $0)?.jpegData(compressionQuality: 0.9) }
                self?.handle(data: jpeg ?? data, kind: .image, ext: "jpg")
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, _ in
                guard let url = item as? URL, let data = try? Data(contentsOf: url) else { return self?.loadFinished() ?? () }
                let ext = url.pathExtension.lowercased()
                if ext == "leverpurchase" { self?.handle(data: data, kind: .transfer, ext: "leverpurchase") }
                else if ext == "pdf" { self?.handle(data: data, kind: .pdf, ext: "pdf") }
                else if ["jpg", "jpeg", "png", "heic"].contains(ext) { self?.handle(data: data, kind: .image, ext: "jpg") }
                else if let text = String(data: data, encoding: .utf8) { self?.handle(text: text, kind: .text) }
                else { self?.loadFinished() }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                self?.handle(text: (item as? URL)?.absoluteString, kind: .url)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                self?.handle(text: item as? String, kind: .text)
            }
        } else {
            loadFinished()
        }
    }

    private func handle(data: Data?, kind: InboxItem.Kind, ext: String) {
        if let data, store.store(data: data, kind: kind, fileExtension: ext, sourceApp: nil) != nil {
            savedCount += 1
        }
        loadFinished()
    }

    private func handle(text: String?, kind: InboxItem.Kind) {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.append(InboxItem(kind: kind, text: text))
            savedCount += 1
        }
        loadFinished()
    }

    private func loadFinished() {
        DispatchQueue.main.async { [self] in
            pendingLoads -= 1
            guard pendingLoads <= 0 else { return }
            let message = savedCount > 0 ? "Saved. Open LEVER to see what it finds." : "LEVER couldn't read this item."
            finish(message: message)
        }
    }

    private func finish(message: String) {
        spinner.stopAnimating()
        spinner.isHidden = true
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
