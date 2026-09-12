import Foundation
#if canImport(FinanceKit)
import FinanceKit
#endif

/// Apple Wallet transactions (Apple Card, Apple Cash, and cards with issuer support) via FinanceKit.
/// Requires iOS 17.4+ and Apple's `com.apple.developer.financekit` entitlement, granted per app on request.
/// Without the entitlement the API refuses authorization and LEVER reports it honestly instead of failing silently.
struct WalletTransactionSource: Sendable {
    enum Status: Equatable { case unavailable(String), notDetermined, denied, authorized }

    var status: Status {
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            guard FinanceStore.isDataAvailable(.financialData) else { return .unavailable("Wallet transaction data isn't available on this device.") }
            return .notDetermined
        }
        #endif
        return .unavailable("Requires iOS 17.4 or later.")
    }

    func requestAccess() async -> Status {
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            do {
                let result = try await FinanceStore.shared.requestAuthorization()
                switch result {
                case .authorized: return .authorized
                case .denied: return .denied
                case .notDetermined: return .notDetermined
                @unknown default: return .denied
                }
            } catch {
                return .unavailable("Wallet access isn't enabled for this build of LEVER yet (FinanceKit entitlement pending).")
            }
        }
        #endif
        return .unavailable("Requires iOS 17.4 or later.")
    }

    /// Debit transactions from the last `days`, mapped into the same shape as statement imports.
    func recentTransactions(days: Int = 90) async throws -> [StatementTransaction] {
        #if canImport(FinanceKit)
        if #available(iOS 17.4, *) {
            let since = DateMath.adding(days: -days, to: .now) ?? .now
            let predicate = #Predicate<FinanceKit.Transaction> { $0.transactionDate >= since }
            let query = TransactionQuery(sortDescriptors: [SortDescriptor(\.transactionDate, order: .reverse)], predicate: predicate, limit: 1000, offset: nil)
            let transactions = try await FinanceStore.shared.transactions(query: query)
            return transactions.map { t in
                let description = t.merchantName ?? t.transactionDescription
                let (merchant, category) = StatementImporter.merchant(from: description)
                return StatementTransaction(
                    date: t.transactionDate,
                    description: description,
                    amount: t.transactionAmount.amount,
                    currencyCode: t.transactionAmount.currencyCode,
                    isDebit: t.creditDebitIndicator == .debit,
                    merchantName: merchant,
                    category: category
                )
            }
        }
        #endif
        return []
    }
}
