import Foundation

/// Tiny wrapper over NSRegularExpression so parsers read cleanly and never crash on a bad pattern.
struct Pattern {
    let regex: NSRegularExpression?

    init(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
        regex = try? NSRegularExpression(pattern: pattern, options: options)
    }

    func firstMatch(in text: String) -> [String?]? {
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return groups(of: match, in: text)
    }

    func allMatches(in text: String) -> [[String?]] {
        guard let regex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { groups(of: $0, in: text) }
    }

    func matches(_ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func groups(of match: NSTextCheckingResult, in text: String) -> [String?] {
        (0..<match.numberOfRanges).map { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
            return String(text[range])
        }
    }
}

extension String {
    var squashedWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func containsAny(_ needles: [String]) -> Bool {
        let lower = lowercased()
        return needles.contains { lower.contains($0) }
    }
}
