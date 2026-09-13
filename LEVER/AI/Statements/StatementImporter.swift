import Foundation

/// One line from a bank or card statement.
struct StatementTransaction: Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var description: String
    var amount: Decimal
    var currencyCode: String
    var isDebit: Bool
    /// Cleaned merchant guess ("NETFLIX.COM MUMBAI 8821" → "Netflix").
    var merchantName: String
    var category: MerchantCategory
}

/// Parses CSV exports and text from PDF statements into transactions. Works fully offline.
/// Handles the common Indian/US/EU bank layouts: date + description + debit/credit columns, or a single signed amount.
struct StatementImporter: Sendable {
    private static let lineAmount = Pattern(#"(-?\(?\d{1,3}(?:[,\s]\d{2,3})*(?:\.\d{1,2})?\)?)\s*(dr|cr|debit|credit|d|c)?\s*$"#)
    private static let noise = Pattern(#"\b(pos|upi|neft|imps|ach|ecs|atm|txn|ref|auto[- ]?debit|debit|card|purchase|payment|paid|to|at|via|intl|international|online|www\.|\.com|\.in|\.co|#\d+|\d{4,})\b"#)

    func looksLikeStatement(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasStatementWords = lower.containsAny(["statement", "account number", "opening balance", "closing balance", "transaction date", "withdrawal", "deposit", "debit", "credit", "balance"])
        return hasStatementWords && parse(text).count >= 4
    }

    func parse(_ text: String, defaultCurrency: String = Money.defaultCurrencyCode) -> [StatementTransaction] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let csv = parseCSV(lines, currency: defaultCurrency), csv.count >= 2 { return csv }
        return parseFreeform(lines, currency: defaultCurrency)
    }

    // MARK: - CSV

    private func parseCSV(_ lines: [String], currency: String) -> [StatementTransaction]? {
        guard let headerIndex = lines.firstIndex(where: { line in
            let lower = line.lowercased()
            return (lower.contains(",") || lower.contains(";") || lower.contains("\t")) && lower.contains("date") && (lower.contains("amount") || lower.contains("debit") || lower.contains("withdrawal"))
        }) else { return nil }
        let separator: Character = lines[headerIndex].contains("\t") ? "\t" : (lines[headerIndex].contains(";") ? ";" : ",")
        let header = split(lines[headerIndex], separator).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Names are in priority order: the first name that matches any header wins (so Paytm's "Source/Destination"
        // beats its vaguer "Activity" column).
        func column(_ names: [String]) -> Int? {
            for name in names { if let i = header.firstIndex(where: { $0.contains(name) }) { return i } }
            return nil
        }
        guard let dateCol = column(["date"]) else { return nil }
        let descCol = column(["source/destination", "to/from", "payee", "merchant", "transaction details", "narration", "particulars", "description", "details", "memo", "remarks", "name", "activity"]) ?? (dateCol + 1)
        let typeCol = column(["type", "transaction type", "dr/cr", "debit/credit", "status"])
        let debitCol = column(["debit", "withdrawal", "paid out", "money out"])
        let creditCol = column(["credit", "deposit", "paid in", "money in"])
        let amountCol = column(["amount"])
        let currencyCol = column(["currency", "ccy"])

        // A single signed "Amount" column: if any value is negative, the sign tells debit from credit.
        let rows = lines[(headerIndex + 1)...].map { split($0, separator) }
        let signed = amountCol.map { col in rows.contains { $0.count > col && (Self.number($0[col]) ?? 0) < 0 } } ?? false

        var results: [StatementTransaction] = []
        for cells in rows {
            guard cells.count > max(dateCol, descCol), let date = DateParser.explicitDates(in: cells[dateCol]).first ?? DateParser.detectorDates(in: cells[dateCol]).first else { continue }
            var amount: Decimal?
            var isDebit = true
            if let debitCol, debitCol < cells.count, let v = Self.number(cells[debitCol]), v != 0 { amount = abs(v); isDebit = true }
            else if let creditCol, creditCol < cells.count, let v = Self.number(cells[creditCol]), v != 0 { amount = abs(v); isDebit = false }
            else if let amountCol, amountCol < cells.count, let v = Self.number(cells[amountCol]) {
                amount = abs(v)
                if signed {
                    isDebit = v < 0
                } else if let typeCol, typeCol < cells.count {
                    // Payment-app exports: "DEBIT"/"CREDIT", "Paid"/"Received", "Sent"/"Received".
                    let t = cells[typeCol].lowercased()
                    isDebit = !(t.contains("credit") || t.contains("received") || t.contains("refund") || t.contains("cashback"))
                } else {
                    let typeHint = cells.joined(separator: " ").lowercased()
                    isDebit = typeHint.contains("debit") || typeHint.contains(" dr") || !(typeHint.contains("credit") || typeHint.contains(" cr"))
                }
            }
            guard let amount, amount > 0 else { continue }
            let code = currencyCol.flatMap { $0 < cells.count ? cells[$0].trimmingCharacters(in: .whitespaces).uppercased() : nil }.flatMap { $0.count == 3 ? $0 : nil } ?? currency
            results.append(make(date: date, description: cells[descCol], amount: amount, currency: code, isDebit: isDebit))
        }
        return results
    }

    private func split(_ line: String, _ separator: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == separator && !inQuotes { cells.append(current); current = "" } else { current.append(ch) }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - PDF / pasted text

    private func parseFreeform(_ lines: [String], currency: String) -> [StatementTransaction] {
        var results: [StatementTransaction] = []
        for line in lines {
            guard let date = DateParser.explicitDates(in: line).first else { continue }
            guard let m = Self.lineAmount.firstMatch(in: line), let raw = m[1], let value = Self.number(raw) else { continue }
            let marker = (m.count > 2 ? m[2] : nil)?.lowercased()
            let lower = line.lowercased()
            if lower.containsAny(["opening balance", "closing balance", "balance b/f", "balance c/f", "total"]) { continue }
            let isCredit = marker == "cr" || marker == "credit" || marker == "c" || lower.containsAny([" cr ", "credit", "refund", "reversal", "salary", "deposit"])
            let isDebit = !isCredit || value < 0
            // Description = the line without the date and the trailing amount.
            var description = line
            if let range = description.range(of: raw) { description.removeSubrange(range.lowerBound..<description.endIndex) }
            description = description.replacingOccurrences(of: #"\b\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4}\b"#, with: " ", options: .regularExpression).squashedWhitespace
            guard description.count >= 3 else { continue }
            results.append(make(date: date, description: description, amount: abs(value), currency: currency, isDebit: isDebit))
        }
        return results
    }

    // MARK: - Helpers

    private func make(date: Date, description: String, amount: Decimal, currency: String, isDebit: Bool) -> StatementTransaction {
        let (merchant, category) = Self.merchant(from: description)
        return StatementTransaction(date: date, description: description.squashedWhitespace, amount: amount, currencyCode: currency, isDebit: isDebit, merchantName: merchant, category: category)
    }

    static func number(_ raw: String) -> Decimal? {
        var cleaned = raw.trimmingCharacters(in: .whitespaces)
        let negative = cleaned.hasPrefix("-") || cleaned.hasPrefix("(")
        cleaned = cleaned.replacingOccurrences(of: #"[()\-₹$€£\s]|Rs\.?|INR|USD"#, with: "", options: .regularExpression)
        guard let value = AmountParser.parseDecimal(cleaned) else { return nil }
        return negative ? -value : value
    }

    /// Normalises a raw statement description into a merchant name and category.
    static func merchant(from description: String) -> (String, MerchantCategory) {
        let directory = MerchantDirectory()
        if let entry = directory.match(in: description) { return (entry.name, entry.category) }
        // Payment-app rows: "Paid to Blue Tokai Coffee" / "Payment to …"
        if let m = Pattern(#"(?:paid to|payment to|sent to|transfer to)\s+(.+)$"#).firstMatch(in: description), let name = m[1]?.squashedWhitespace, name.count >= 3 {
            return (name.replacingOccurrences(of: #"\s+(via|using|upi).*$"#, with: "", options: [.regularExpression, .caseInsensitive]).capitalized, .other)
        }
        // A bare VPA in the description ("netflix.upi@icici") → merchant handle.
        if let m = Pattern(#"\b([a-z0-9._-]{2,}@[a-z][a-z0-9]{1,})\b"#).firstMatch(in: description.lowercased()), let vpa = m[1], let name = PaymentMessageParser.merchantName(fromVPA: vpa) {
            return (name, directory.entry(named: name)?.category ?? .other)
        }
        var cleaned = description.lowercased()
        cleaned = cleaned.replacingOccurrences(of: #"[^a-z\s&.]"#, with: " ", options: .regularExpression)
        var previous = ""
        while previous != cleaned {
            previous = cleaned
            cleaned = noise.regex?.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ") ?? cleaned
        }
        let words = cleaned.squashedWhitespace.split(separator: " ").prefix(3).map { $0.capitalized }
        let name = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return (name.isEmpty ? description.squashedWhitespace : name, .other)
    }
}

/// A merchant that appears to charge on a schedule.
struct RecurringCandidate: Equatable, Identifiable, Sendable {
    var id: String { "\(merchantName.lowercased())|\(cycle.rawValue)" }
    var merchantName: String
    var category: MerchantCategory
    var typicalAmount: Decimal
    var latestAmount: Decimal
    var previousAmount: Decimal?
    var currencyCode: String
    var cycle: BillingCycle
    var occurrences: Int
    var lastDate: Date
    var nextDate: Date?
    var confidence: Confidence

    var annualCost: Decimal? { SubscriptionMath.annualCost(price: latestAmount, cycle: cycle) }
}

/// Finds repeating charges: same merchant, similar amount, regular gaps. Pure so it's easy to test.
enum RecurringChargeDetector {
    static func detect(_ transactions: [StatementTransaction], now: Date = .now, calendar: Calendar = .current) -> [RecurringCandidate] {
        let debits = transactions.filter(\.isDebit)
        let groups = Dictionary(grouping: debits) { $0.merchantName.lowercased() }
        var candidates: [RecurringCandidate] = []
        for (_, items) in groups where items.count >= 2 {
            let sorted = items.sorted { $0.date < $1.date }
            let gaps = zip(sorted, sorted.dropFirst()).map { DateMath.days(from: $0.date, to: $1.date, calendar: calendar) }
            guard let cycle = cycle(forGaps: gaps) else { continue }
            let amounts = sorted.map(\.amount)
            let median = amounts.sorted()[amounts.count / 2]
            // Prices creep up; allow ±30% around the median so an increase still reads as the same subscription.
            guard median > 0, amounts.allSatisfy({ abs($0 - median) / median <= Decimal(sign: .plus, exponent: -1, significand: 3) }) else { continue }
            guard let last = sorted.last else { continue }
            // "Previous price" = the most recent charge that differed from the current one (price rises stick for months).
            let previous = sorted.dropLast().last { $0.amount != last.amount }?.amount
            let next = SubscriptionMath.nextBillingDate(after: last.date, cycle: cycle, calendar: calendar, now: now)
            let confidence: Confidence = sorted.count >= 3 ? .high : .medium
            candidates.append(RecurringCandidate(
                merchantName: last.merchantName, category: last.category, typicalAmount: median, latestAmount: last.amount,
                previousAmount: previous, currencyCode: last.currencyCode, cycle: cycle,
                occurrences: sorted.count, lastDate: last.date, nextDate: next, confidence: confidence
            ))
        }
        return candidates.sorted { ($0.annualCost ?? 0) > ($1.annualCost ?? 0) }
    }

    static func cycle(forGaps gaps: [Int]) -> BillingCycle? {
        guard !gaps.isEmpty else { return nil }
        func fits(_ target: Int, tolerance: Int) -> Bool { gaps.allSatisfy { abs($0 - target) <= tolerance } }
        if fits(7, tolerance: 1) { return .weekly }
        if fits(30, tolerance: 4) { return .monthly }
        if fits(91, tolerance: 7) { return .quarterly }
        if fits(365, tolerance: 12) { return .yearly }
        return nil
    }
}
