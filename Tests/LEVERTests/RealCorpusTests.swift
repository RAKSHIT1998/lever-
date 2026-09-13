import XCTest
@testable import LEVER

/// Replays real-world documents from Tests/Fixtures/real through the on-device parser.
/// Add `<name>.txt` (recognised text) and optionally `<name>.expected.json`; the test reports every miss.
final class RealCorpusTests: XCTestCase {
    struct Expected: Decodable {
        var merchant: String?
        var amount: Decimal?
        var purchaseDate: String?
        var documentType: String?
        var renewalDate: String?
        var returnDeadline: String?
    }

    private var corpusURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/real")
    }

    func testRealCorpus() throws {
        let files = ((try? FileManager.default.contentsOfDirectory(at: corpusURL, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "txt" }
        guard !files.isEmpty else { throw XCTSkip("No real samples yet — export from LEVER → Privacy Center → Export parsing samples") }
        let parser = DocumentParser()
        var report: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let doc = parser.parse(RecognizedText(lines: text.components(separatedBy: .newlines), averageConfidence: 0.95), currencyCode: "INR")
            var line = "\(file.lastPathComponent): merchant=\(doc.merchant ?? "∅") amount=\(doc.amount.map { "\($0)" } ?? "∅") date=\(doc.purchaseDate?.leverShort ?? "∅") type=\(doc.documentType.rawValue) conf=\(doc.overallConfidence.rawValue)"
            let expectedURL = file.deletingPathExtension().appendingPathExtension("expected.json")
            if let data = try? Data(contentsOf: expectedURL), let expected = try? JSONDecoder().decode(Expected.self, from: data) {
                var misses: [String] = []
                if let m = expected.merchant, doc.merchant?.lowercased() != m.lowercased() { misses.append("merchant≠\(m)") }
                if let a = expected.amount, doc.amount != a { misses.append("amount≠\(a)") }
                if let d = expected.purchaseDate, iso(doc.purchaseDate) != d { misses.append("date≠\(d)") }
                if let t = expected.documentType, doc.documentType.rawValue != t { misses.append("type≠\(t)") }
                if let r = expected.renewalDate, iso(doc.renewalDate ?? doc.subscription?.nextBillingDate) != r { misses.append("renewal≠\(r)") }
                if let r = expected.returnDeadline, iso(doc.returnDeadline) != r { misses.append("return≠\(r)") }
                line += misses.isEmpty ? "  ✓" : "  ✗ " + misses.joined(separator: ", ")
                XCTAssertTrue(misses.isEmpty, "\(file.lastPathComponent): \(misses.joined(separator: ", "))")
            }
            report.append(line)
        }
        print("REAL CORPUS REPORT\n" + report.joined(separator: "\n"))
    }

    private func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
