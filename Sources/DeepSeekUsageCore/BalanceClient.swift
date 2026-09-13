import Foundation

public enum BalanceError: Error, LocalizedError, Equatable, Sendable {
    case missingAPIKey
    /// 401 — Authentication Fails.
    case invalidAPIKey
    /// 402 — Insufficient Balance.
    case insufficientBalance
    /// 429 — Rate Limit Reached (concurrency, not a spending limit).
    case rateLimited
    /// 5xx — Server Error / Server Overloaded.
    case serverError(Int)
    case http(Int, String)
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key yet — add one in Settings."
        case .invalidAPIKey:
            return "API key rejected (401). Check that the key is correct."
        case .insufficientBalance:
            return "DeepSeek reports insufficient balance (402)."
        case .rateLimited:
            return "Rate limited (429). Will retry on the next refresh."
        case .serverError(let status):
            return "DeepSeek server error (\(status)). Will retry on the next refresh."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Unexpected HTTP \(status)." : "HTTP \(status): \(detail)"
        case .transport(let message):
            return "Network error: \(message)"
        case .decoding(let message):
            return "Could not read the balance response: \(message)"
        }
    }
}

/// Client for the only account endpoint DeepSeek documents for API keys:
/// `GET /user/balance`. It reads account metadata — it does not run inference and
/// therefore bills no tokens.
public struct BalanceClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = BalanceClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Pure status-code mapping, split out so it can be verified offline.
    public static func error(forStatusCode status: Int, body: String) -> BalanceError? {
        switch status {
        case 200..<300: return nil
        case 401: return .invalidAPIKey
        case 402: return .insufficientBalance
        case 429: return .rateLimited
        case 500..<600: return .serverError(status)
        default: return .http(status, body)
        }
    }

    public func fetchBalance(apiKey: String) async throws -> BalanceResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("user/balance"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BalanceError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BalanceError.transport("Malformed HTTP response")
        }

        if let error = BalanceClient.error(forStatusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "") {
            throw error
        }

        do {
            return try JSONDecoder().decode(BalanceResponse.self, from: data)
        } catch {
            throw BalanceError.decoding(String(describing: error))
        }
    }
}
