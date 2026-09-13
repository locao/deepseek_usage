import Foundation

/// A decimal that DeepSeek may encode either as a JSON string (`"110.00"`) or as a
/// JSON number (`110.0`). The official docs show strings, but decoding defensively
/// costs nothing and avoids a total failure if the representation ever changes.
public struct LenientDecimal: Decodable, Sendable, Equatable {
    public let value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let text = try? container.decode(String.self) {
            guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not a decimal string: \(text)"
                )
            }
            value = decimal
            return
        }

        if let double = try? container.decode(Double.self) {
            value = Decimal(double)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a decimal value")
    }
}

/// One currency bucket inside `balance_infos`.
public struct BalanceInfo: Decodable, Sendable, Equatable, Identifiable {
    public let currency: String
    public let totalBalance: Decimal
    public let grantedBalance: Decimal
    public let toppedUpBalance: Decimal

    public var id: String { currency }

    private enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    public init(currency: String, totalBalance: Decimal, grantedBalance: Decimal, toppedUpBalance: Decimal) {
        self.currency = currency
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Never throw on a missing money field: an unknown/renamed field should degrade
        // to zero rather than blank the whole menu bar item.
        currency = (try? container.decodeIfPresent(String.self, forKey: .currency)) ?? nil ?? "CNY"
        totalBalance = BalanceInfo.money(container, .totalBalance)
        grantedBalance = BalanceInfo.money(container, .grantedBalance)
        toppedUpBalance = BalanceInfo.money(container, .toppedUpBalance)
    }

    private static func money(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Decimal {
        // `decodeIfPresent` returns an optional and `try?` flattens it, so a missing
        // field simply falls through to zero.
        guard let decoded = try? container.decodeIfPresent(LenientDecimal.self, forKey: key) else { return 0 }
        return decoded.value
    }
}

/// Response of `GET https://api.deepseek.com/user/balance`.
public struct BalanceResponse: Decodable, Sendable, Equatable {
    public let isAvailable: Bool?
    public let balanceInfos: [BalanceInfo]

    /// The first bucket is the account's primary currency.
    public var primary: BalanceInfo? { balanceInfos.first }

    private enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    public init(isAvailable: Bool?, balanceInfos: [BalanceInfo]) {
        self.isAvailable = isAvailable
        self.balanceInfos = balanceInfos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable)
        balanceInfos = try container.decodeIfPresent([BalanceInfo].self, forKey: .balanceInfos) ?? []
    }
}

public enum MoneyFormatter {
    public static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        default: return ""
        }
    }

    /// Locale-independent formatting: the menu bar must not change shape with the
    /// user's regional settings, and money must not go through `Double`.
    public static func string(_ value: Decimal, currency: String, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits

        let text = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        let symbol = symbol(for: currency)
        return symbol.isEmpty ? "\(text) \(currency.uppercased())" : "\(symbol)\(text)"
    }
}
