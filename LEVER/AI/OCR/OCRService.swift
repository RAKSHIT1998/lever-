import Foundation
@preconcurrency import Vision
import PDFKit
import UIKit

/// On-device text recognition with Vision, plus native PDF text extraction (falling back to OCR for scanned PDFs).
struct OCRService: TextRecognizing {
    func recognizeText(in imageData: Data) async throws -> RecognizedText {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw IntelligenceError.unreadable
        }
        return try await recognize(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    func extractText(fromPDF data: Data) async throws -> RecognizedText {
        guard let document = PDFDocument(data: data) else { throw IntelligenceError.unreadable }
        var lines: [String] = []
        var confidences: [Double] = []
        let pageCount = min(document.pageCount, 12)
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let native = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if native.count > 40 {
                lines.append(contentsOf: native.components(separatedBy: .newlines))
                confidences.append(1.0)
            } else {
                // Scanned PDF — render and OCR the page.
                let bounds = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: bounds.width * scale, height: bounds.height * scale))
                let image = renderer.image { ctx in
                    UIColor.white.set()
                    ctx.fill(CGRect(origin: .zero, size: ctx.format.bounds.size))
                    ctx.cgContext.translateBy(x: 0, y: bounds.height * scale)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                if let cg = image.cgImage {
                    let result = try await recognize(cgImage: cg, orientation: .up)
                    lines.append(contentsOf: result.lines)
                    confidences.append(result.averageConfidence)
                }
            }
        }
        let avg = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return RecognizedText(lines: lines, averageConfidence: avg, pageCount: max(pageCount, 1))
    }

    private func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> RecognizedText {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Sort top-to-bottom, then left-to-right so the text reads like the document.
                let sorted = observations.sorted {
                    let dy = $1.boundingBox.midY - $0.boundingBox.midY
                    if abs(dy) > 0.012 { return $0.boundingBox.midY > $1.boundingBox.midY }
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                var lines: [String] = []
                var confidences: [Double] = []
                for observation in sorted {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    confidences.append(Double(candidate.confidence))
                }
                let avg = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
                continuation.resume(returning: RecognizedText(lines: lines, averageConfidence: avg))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-IN", "en-US", "en-GB"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
