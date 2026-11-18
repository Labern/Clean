import Foundation
import Security

// MARK: - Keychain

/// Secrets live in the Keychain on this phone only. Nothing is written to
/// the repo, to UserDefaults or to a backup that leaves the device.
nonisolated enum Keychain {
    private static let service = "com.labern.paradox.hq"

    @discardableResult
    static func set(_ value: String, for name: String) -> Bool {
        delete(name)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecValueData as String: Data(value.utf8),
            // After-first-unlock, so a background refresh can read the key while
            // the phone is locked. Still this device only, never in a backup.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ name: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// The same, for bytes rather than words (a compressed backup). `travels`
    /// lets it move to a new phone set up from this one's backup; keys never do.
    @discardableResult
    static func setData(_ value: Data, for name: String, travels: Bool = false) -> Bool {
        delete(name)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecValueData as String: value,
            kSecAttrAccessible as String: travels ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func data(_ name: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ name: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - What Stripe sends

nonisolated struct StripeList<T: Decodable & Sendable>: Decodable, Sendable {
    let data: [T]
    let hasMore: Bool
}

/// A field Stripe sends as an id unless it was expanded into the full object.
nonisolated struct Expandable<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

nonisolated struct StripeBilling: Decodable, Sendable {
    let name: String?
    let email: String?
}

nonisolated struct StripeCard: Decodable, Sendable {
    let brand: String?
    let last4: String?
}

nonisolated struct StripeMethod: Decodable, Sendable {
    let type: String?
    let card: StripeCard?
}

nonisolated struct StripeBalanceTransaction: Decodable, Sendable {
    let fee: Int
    let net: Int
}

nonisolated struct StripeCharge: Decodable, Sendable {
    let id: String
    let amount: Int
    let amountRefunded: Int
    let currency: String
    let created: Int
    let status: String
    let paid: Bool
    let refunded: Bool
    let disputed: Bool
    let description: String?
    let receiptEmail: String?
    let billingDetails: StripeBilling?
    let paymentMethodDetails: StripeMethod?
    let balanceTransaction: Expandable<StripeBalanceTransaction>?
}

nonisolated struct StripePayout: Decodable, Sendable {
    let id: String
    let amount: Int
    let currency: String
    let arrivalDate: Int
    let status: String
}

nonisolated struct StripeEvidence: Decodable, Sendable {
    let dueBy: Int?
}

nonisolated struct StripeDispute: Decodable, Sendable {
    let id: String
    let amount: Int
    let currency: String
    let status: String
    let reason: String?
    let created: Int
    let evidenceDetails: StripeEvidence?
}

nonisolated struct StripeFunds: Decodable, Sendable {
    let amount: Int
    let currency: String
}

nonisolated struct StripeBalance: Decodable, Sendable {
    let available: [StripeFunds]
    let pending: [StripeFunds]
}

nonisolated struct StripeRecurring: Decodable, Sendable {
    let interval: String
    let intervalCount: Int?
}

nonisolated struct StripePrice: Decodable, Sendable {
    let unitAmount: Int?
    let recurring: StripeRecurring?
}

nonisolated struct StripeSubscriptionItem: Decodable, Sendable {
    let quantity: Int?
    let price: StripePrice
}

nonisolated struct StripeSubscriptionItems: Decodable, Sendable {
    let data: [StripeSubscriptionItem]
}

nonisolated struct StripeSubscription: Decodable, Sendable {
    let id: String
    let items: StripeSubscriptionItems

    /// What this subscription is worth per month, in minor units.
    var monthly: Int {
        items.data.reduce(0) { sum, item in
            guard let amount = item.price.unitAmount, let recurring = item.price.recurring else { return sum }
            let every = Double(max(1, recurring.intervalCount ?? 1))
            let total = Double(amount * (item.quantity ?? 1))
            let perMonth: Double
            switch recurring.interval {
            case "day": perMonth = total * 365 / 12 / every
            case "week": perMonth = total * 52 / 12 / every
            case "year": perMonth = total / 12 / every
            default: perMonth = total / every
            }
            return sum + Int(perMonth.rounded())
        }
    }
}

nonisolated struct StripeFailureBody: Decodable, Sendable {
    let message: String?
}

nonisolated struct StripeFailure: Decodable, Sendable {
    let error: StripeFailureBody
}

nonisolated struct StripeError: Error, LocalizedError, Sendable {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

// MARK: - What the app shows

nonisolated enum PaymentStatus: String, Sendable {
    case succeeded, pending, failed, refunded, disputed

    var label: String {
        switch self {
        case .succeeded: "Succeeded"
        case .pending: "Pending"
        case .failed: "Failed"
        case .refunded: "Refunded"
        case .disputed: "Disputed"
        }
    }
}

nonisolated struct Payment: Identifiable, Hashable, Sendable {
    let id: String
    let amount: Int
    let refunded: Int
    let fee: Int?
    let net: Int?
    let currency: String
    let date: Date
    let status: PaymentStatus
    let who: String
    let what: String
    let method: String

    /// What this payment adds to revenue: money taken, less anything sent back.
    var counted: Int {
        switch status {
        case .succeeded, .refunded, .disputed: amount - refunded
        case .pending, .failed: 0
        }
    }

    init(id: String, amount: Int, refunded: Int = 0, fee: Int? = nil, net: Int? = nil, currency: String = "gbp",
         date: Date, status: PaymentStatus = .succeeded, who: String, what: String = "", method: String = "") {
        self.id = id
        self.amount = amount
        self.refunded = refunded
        self.fee = fee
        self.net = net
        self.currency = currency
        self.date = date
        self.status = status
        self.who = who
        self.what = what
        self.method = method
    }

    init(_ charge: StripeCharge) {
        let status: PaymentStatus
        if !charge.paid {
            status = charge.status == "pending" ? .pending : .failed
        } else if charge.disputed {
            status = .disputed
        } else if charge.refunded {
            status = .refunded
        } else {
            status = .succeeded
        }
        var method = ""
        if let card = charge.paymentMethodDetails?.card, let last4 = card.last4 {
            method = "\((card.brand ?? "Card").capitalized) ···· \(last4)"
        } else if let type = charge.paymentMethodDetails?.type {
            method = type.replacingOccurrences(of: "_", with: " ").capitalized
        }
        self.init(id: charge.id,
                  amount: charge.amount,
                  refunded: charge.amountRefunded,
                  fee: charge.balanceTransaction?.value?.fee,
                  net: charge.balanceTransaction?.value?.net,
                  currency: charge.currency,
                  date: Date(timeIntervalSince1970: TimeInterval(charge.created)),
                  status: status,
                  who: charge.billingDetails?.name ?? charge.billingDetails?.email ?? charge.receiptEmail ?? "Customer",
                  what: charge.description ?? "",
                  method: method)
    }
}

nonisolated struct Payout: Identifiable, Hashable, Sendable {
    let id: String
    let amount: Int
    let arrives: Date
    let status: String

    var label: String {
        switch status {
        case "paid": "Paid"
        case "in_transit": "On its way"
        case "pending": "Scheduled"
        case "failed": "Failed"
        case "canceled": "Cancelled"
        default: status.capitalized
        }
    }

    var isUpcoming: Bool { status == "in_transit" || status == "pending" }
}

nonisolated struct Dispute: Identifiable, Hashable, Sendable {
    let id: String
    let amount: Int
    let reason: String
    let due: Date?
    let status: String

    var needsResponse: Bool { status == "needs_response" || status == "warning_needs_response" }
}

nonisolated struct Snapshot: Sendable {
    var payments: [Payment] = []
    var payouts: [Payout] = []
    var disputes: [Dispute] = []
    var available = 0
    var pending = 0
    var subscribers: Int? = nil
    var mrr: Int? = nil
    var currency = "gbp"
}

// MARK: - The client

/// Reads the Stripe account with a restricted, read-only key.
/// It never writes: there is no call here that can move money.
nonisolated struct StripeClient: Sendable {
    let key: String

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func get<T: Decodable & Sendable>(_ path: String, _ query: [(String, String)] = []) async throws -> T {
        guard var components = URLComponents(string: "https://api.stripe.com/v1/\(path)") else {
            throw StripeError(code: 0, message: "Bad address.")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw StripeError(code: 0, message: "Bad address.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let said = (try? Self.decoder().decode(StripeFailure.self, from: data))?.error.message
            let fallback = code == 401 ? "Stripe didn't accept that key." : "Stripe returned \(code)."
            throw StripeError(code: code, message: said ?? fallback)
        }
        return try Self.decoder().decode(T.self, from: data)
    }

    func charges(since: Date, withFees: Bool, maxPages: Int = 20) async throws -> [StripeCharge] {
        var all: [StripeCharge] = []
        var after: String? = nil
        for _ in 0..<maxPages {
            var query = [("limit", "100"), ("created[gte]", String(Int(since.timeIntervalSince1970)))]
            if withFees { query.append(("expand[]", "data.balance_transaction")) }
            if let after { query.append(("starting_after", after)) }
            let page: StripeList<StripeCharge> = try await get("charges", query)
            all += page.data
            guard page.hasMore, let last = page.data.last else { break }
            after = last.id
        }
        return all
    }

    /// Everything the app shows, in one pass. Charges are required; the rest
    /// is left empty if the key isn't allowed to read it.
    func snapshot(since: Date) async throws -> Snapshot {
        var snapshot = Snapshot()

        let charges: [StripeCharge]
        do {
            charges = try await self.charges(since: since, withFees: true)
        } catch let error as StripeError where error.code == 403 {
            // The key can read charges but not their fees.
            charges = try await self.charges(since: since, withFees: false)
        }
        snapshot.payments = charges.map { Payment($0) }.sorted { $0.date > $1.date }
        if let first = charges.first { snapshot.currency = first.currency }

        if let balance: StripeBalance = try? await get("balance") {
            let currency = balance.available.first?.currency ?? snapshot.currency
            snapshot.currency = currency
            snapshot.available = balance.available.filter { $0.currency == currency }.reduce(0) { $0 + $1.amount }
            snapshot.pending = balance.pending.filter { $0.currency == currency }.reduce(0) { $0 + $1.amount }
        }
        if let payouts: StripeList<StripePayout> = try? await get("payouts", [("limit", "10")]) {
            snapshot.payouts = payouts.data.map {
                Payout(id: $0.id, amount: $0.amount,
                       arrives: Date(timeIntervalSince1970: TimeInterval($0.arrivalDate)), status: $0.status)
            }
        }
        if let disputes: StripeList<StripeDispute> = try? await get("disputes", [("limit", "20")]) {
            snapshot.disputes = disputes.data.map {
                Dispute(id: $0.id, amount: $0.amount,
                        reason: ($0.reason ?? "").replacingOccurrences(of: "_", with: " "),
                        due: $0.evidenceDetails?.dueBy.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                        status: $0.status)
            }
        }
        if let subscriptions: StripeList<StripeSubscription> = try? await get("subscriptions", [("status", "active"), ("limit", "100")]) {
            snapshot.subscribers = subscriptions.data.count
            snapshot.mrr = subscriptions.data.reduce(0) { $0 + $1.monthly }
        }
        return snapshot
    }
}
