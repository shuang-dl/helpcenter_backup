import Foundation

enum IntercomClientError: LocalizedError {
    case invalidURL(String)
    case requestFailed(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(path):
            return "Invalid Intercom URL path: \(path)"
        case let .requestFailed(status, body):
            return "Intercom API request failed (\(status)): \(body)"
        case let .decodingFailed(message):
            return "Failed to decode Intercom response: \(message)"
        }
    }
}

struct IntercomClient {
    private let token: String
    private let apiVersion: String
    private let baseURL = URL(string: "https://api.intercom.io")!

    init(token: String, apiVersion: String = "2.14") {
        self.token = token
        self.apiVersion = apiVersion
    }

    func fetchHelpCenters() async throws -> [HelpCenter] {
        try await fetchAll(path: "/help_center/help_centers")
    }

    func fetchCollections() async throws -> [CollectionItem] {
        try await fetchAll(path: "/help_center/collections")
    }

    func fetchSections() async throws -> [SectionItem] {
        try await fetchAll(path: "/help_center/sections")
    }

    func fetchArticles() async throws -> [Article] {
        try await fetchAll(path: "/articles")
    }

    private func fetchAll<T: Decodable>(path: String) async throws -> [T] {
        var output: [T] = []
        var currentPath: String? = path

        while let activePath = currentPath {
            let page: IntercomListResponse<T> = try await request(path: activePath)
            output.append(contentsOf: page.data)

            guard let next = page.pages?.next else {
                currentPath = nil
                continue
            }

            switch next {
            case let .url(nextURLString):
                guard let fullURL = URL(string: nextURLString), let components = URLComponents(url: fullURL, resolvingAgainstBaseURL: false) else {
                    currentPath = nil
                    continue
                }
                var joined = components.path
                if let query = components.query, !query.isEmpty {
                    joined += "?\(query)"
                }
                currentPath = joined
            case let .cursor(cursor):
                guard let startingAfter = cursor.startingAfter, !startingAfter.isEmpty else {
                    currentPath = nil
                    continue
                }
                currentPath = appendQuery(path: path, name: "starting_after", value: startingAfter)
            }
        }

        return output
    }

    private func appendQuery(path: String, name: String, value: String) -> String {
        let separator = path.contains("?") ? "&" : "?"
        return "\(path)\(separator)\(name)=\(value)"
    }

    private func request<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw IntercomClientError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "Intercom-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()

        guard let httpResponse = response as? HTTPURLResponse else {
            return try decoder.decode(T.self, from: data)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty body>"
            throw IntercomClientError.requestFailed(httpResponse.statusCode, body)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw IntercomClientError.decodingFailed(describe(decodingError: error))
        } catch {
            throw error
        }
    }

    private func describe(decodingError: DecodingError) -> String {
        switch decodingError {
        case let .dataCorrupted(context):
            return "Data corrupted at \(pathString(context.codingPath)): \(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "Missing key '\(key.stringValue)' at \(pathString(context.codingPath)): \(context.debugDescription)"
        case let .typeMismatch(_, context):
            return "Type mismatch at \(pathString(context.codingPath)): \(context.debugDescription)"
        case let .valueNotFound(_, context):
            return "Value not found at \(pathString(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error"
        }
    }

    private func pathString(_ codingPath: [CodingKey]) -> String {
        if codingPath.isEmpty {
            return "<root>"
        }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }
}

private struct IntercomListResponse<T: Decodable>: Decodable {
    let data: [T]
    let pages: IntercomPages?
}

private struct IntercomPages: Decodable {
    let next: IntercomNextPage?
}

private enum IntercomNextPage: Decodable {
    case url(String)
    case cursor(IntercomCursor)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .url(value)
            return
        }

        if let cursor = try? container.decode(IntercomCursor.self) {
            self = .cursor(cursor)
            return
        }

        throw DecodingError.typeMismatch(
            IntercomNextPage.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported Intercom next page value")
        )
    }
}

private struct IntercomCursor: Decodable {
    let startingAfter: String?

    enum CodingKeys: String, CodingKey {
        case startingAfter = "starting_after"
    }
}
