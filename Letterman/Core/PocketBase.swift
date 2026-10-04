import Foundation

/// An error message from the server, ready to show to the user.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Minimal client for the PocketBase REST API (https://pocketbase.io/docs/api-records/).
/// There is no official Swift SDK, and the app only needs a handful of calls.
final class PocketBase {
    static let shared = PocketBase()

    /// The signed-in user's token. Set and cleared by `Session`.
    var token: String?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = PBDate.parse(raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
            }
            return date
        }
        return d
    }()

    // MARK: Records

    func list<T: Decodable>(_ collection: String, filter: String? = nil, sort: String? = nil, expand: String? = nil) async throws -> [T] {
        let perPage = 500
        var all: [T] = []
        var page = 1
        while true {
            var query = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(perPage)),
                URLQueryItem(name: "skipTotal", value: "1"),
            ]
            if let filter { query.append(URLQueryItem(name: "filter", value: filter)) }
            if let sort { query.append(URLQueryItem(name: "sort", value: sort)) }
            if let expand { query.append(URLQueryItem(name: "expand", value: expand)) }
            let result: ListResult<T> = try await send("GET", "/api/collections/\(collection)/records", query: query)
            all += result.items
            if result.items.count < perPage { return all }
            page += 1
        }
    }

    func create<T: Decodable>(_ collection: String, _ body: [String: Any]) async throws -> T {
        try await send("POST", "/api/collections/\(collection)/records", body: body)
    }

    func update<T: Decodable>(_ collection: String, id: String, _ body: [String: Any]) async throws -> T {
        try await send("PATCH", "/api/collections/\(collection)/records/\(id)", body: body)
    }

    func delete(_ collection: String, id: String) async throws {
        let _: Empty = try await send("DELETE", "/api/collections/\(collection)/records/\(id)")
    }

    // MARK: Transport

    @discardableResult
    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> T {
        var components = URLComponents(url: Config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: data) }
        if data.isEmpty, let empty = Empty() as? T { return empty }
        return try decoder.decode(T.self, from: data)
    }

    /// Turns PocketBase's error JSON into one readable sentence.
    private static func apiError(status: Int, data: Data) -> APIError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var message = json?["message"] as? String ?? "Something went wrong (error \(status))."
        // Field problems look like {"data": {"email": {"message": "..."}}}.
        if let fields = json?["data"] as? [String: Any],
           let (field, info) = fields.sorted(by: { $0.key < $1.key }).first,
           let detail = (info as? [String: Any])?["message"] as? String {
            message = "\(field.replacingOccurrences(of: "_", with: " ").capitalized): \(detail)"
        }
        if status == 429 { message = "Too many tries. Wait a few seconds and try again." }
        return APIError(status: status, message: message)
    }
}

struct ListResult<T: Decodable>: Decodable {
    let items: [T]
}

struct Empty: Decodable {}

/// PocketBase stores dates as UTC strings like "2026-10-10 14:00:00.000Z".
enum PBDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS'Z'"
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        if raw.isEmpty { return nil }
        if let d = formatter.date(from: raw) { return d }
        // Some values come back without milliseconds.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss'Z'"
        return f.date(from: raw)
    }

    static func string(_ date: Date) -> String { formatter.string(from: date) }
}
