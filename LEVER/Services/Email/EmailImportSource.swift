import Foundation

/// One inbox message reduced to what the parser needs. Bodies are HTML-stripped before parsing.
struct EmailMessage: Identifiable, Equatable, Sendable {
    var id: String
    var subject: String
    var from: String
    var date: Date
    var bodyText: String
}

/// An inbox LEVER can scan for order confirmations, receipts and renewals. Read-only, opt-in, on-device parsing.
protocol EmailImportSource: AnyObject {
    var providerName: String { get }
    var isConfigured: Bool { get }
    var isConnected: Bool { get }
    var accountLabel: String? { get }
    func connect() async throws
    func disconnect()
    func fetchCandidateMessages(days: Int) async throws -> [EmailMessage]
}

enum EmailImportError: LocalizedError {
    case notConfigured, cancelled, authFailed(String), network(String), tokenExpired

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add a Google OAuth client ID in Settings → Email import first."
        case .cancelled: "Sign-in was cancelled."
        case .authFailed(let m): "Google sign-in failed: \(m)"
        case .network(let m): "Couldn't reach Gmail: \(m)"
        case .tokenExpired: "Your Gmail session expired. Connect again."
        }
    }
}

/// The Gmail search LEVER uses. Purchases only — no personal mail is requested beyond what matches.
enum EmailQuery {
    static func gmail(days: Int) -> String {
        "newer_than:\(days)d (subject:(receipt OR invoice OR \"order confirmation\" OR \"your order\" OR renewal OR subscription OR booking OR \"payment received\" OR \"tax invoice\" OR warranty) OR from:(amazon OR flipkart OR netflix OR spotify OR apple OR myntra OR makemytrip OR booking.com OR airbnb OR uber OR swiggy OR zomato OR airtel OR jio)) -category:promotions"
    }
}
