import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case httpError(Int, Data)
    case decodingError(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code, let data):
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            return "HTTP \(code): \(msg)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .notAuthenticated: return "Not authenticated"
        }
    }
}

// Endpoint construction
extension String {
    var apiURL: URL? {
        URL(string: NetworkService.baseURL + self)
    }
}

actor NetworkService {
    static let shared = NetworkService()

    /// Runtime-configurable backend URL.
    /// Priority order:
    ///   1. UserDefaults["backend_url"]  (user-edited in Settings)
    ///   2. Info.plist["BackendBaseURL"]  (build-time inject from run-on-device.sh)
    ///   3. Localhost fallback (works for simulator only)
    static var baseURL: String {
        if let user = UserDefaults.standard.string(forKey: "backend_url"), !user.isEmpty {
            return user
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           !plist.isEmpty, plist != "$(BACKEND_BASE_URL)" {
            return plist
        }
        return "http://localhost:8000/api/v1"
    }

    static func setBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "backend_url")
    }

    static func resetBaseURL() {
        UserDefaults.standard.removeObject(forKey: "backend_url")
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    // MARK: - Generic request

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: Self.baseURL + path) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated {
            let token = try await AuthService.shared.accessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: req)
        let http = response as! HTTPURLResponse

        if http.statusCode == 401 && authenticated {
            // Attempt token refresh once
            let newToken = try await AuthService.shared.refreshIfNeeded(network: self)
            req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: req)
            let http2 = response2 as! HTTPURLResponse
            guard (200..<300).contains(http2.statusCode) else {
                throw NetworkError.httpError(http2.statusCode, data2)
            }
            return try decodeResponse(data2)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode, data)
        }

        return try decodeResponse(data)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable, authenticated: Bool = true) async throws -> T {
        try await request(path, method: "POST", body: body, authenticated: authenticated)
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await request(path, method: "PATCH", body: body)
    }

    func delete(_ path: String) async throws {
        guard let url = URL(string: Self.baseURL + path) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let token = try await AuthService.shared.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: req)
        let http = response as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.httpError(http.statusCode, Data())
        }
    }

    private func decodeResponse<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}
