import Foundation

enum ExportFormat: String, CaseIterable, Codable, Identifiable {
    case json
    case markdown
    case html
    case pdf

    var id: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .markdown:
            return "md"
        case .html:
            return "html"
        case .pdf:
            return "pdf"
        }
    }
}

enum DownloadMode: String, CaseIterable, Codable, Identifiable {
    case fullDownload
    case updatesOnly

    var id: String { rawValue }
}

struct HelpCenter: Decodable {
    let id: String
    let displayName: String?
    let identifier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case identifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
    }
}

struct CollectionItem: Decodable {
    let id: String
    let name: String?
    let parentID: String?
    let helpCenterID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parent_id"
        case helpCenterID = "help_center_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        parentID = try container.decodeFlexibleStringIfPresent(forKey: .parentID)
        helpCenterID = try container.decodeFlexibleStringIfPresent(forKey: .helpCenterID)
    }
}

struct SectionItem: Decodable {
    let id: String
    let name: String?
    let parentID: String?
    let collectionID: String?
    let helpCenterID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID = "parent_id"
        case collectionID = "collection_id"
        case helpCenterID = "help_center_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        parentID = try container.decodeFlexibleStringIfPresent(forKey: .parentID)
        collectionID = try container.decodeFlexibleStringIfPresent(forKey: .collectionID)
        helpCenterID = try container.decodeFlexibleStringIfPresent(forKey: .helpCenterID)
    }
}

struct Article: Decodable {
    let id: String
    let title: String?
    let description: String?
    let body: String?
    let state: String?
    let url: String?
    let createdAt: Int64?
    let updatedAt: Int64?
    let parentID: String?
    let parentIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case body
        case state
        case url
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case parentID = "parent_id"
        case parentIDs = "parent_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        createdAt = try container.decodeFlexibleInt64IfPresent(forKey: .createdAt)
        updatedAt = try container.decodeFlexibleInt64IfPresent(forKey: .updatedAt)
        parentID = try container.decodeFlexibleStringIfPresent(forKey: .parentID)
        parentIDs = try container.decodeFlexibleStringArrayIfPresent(forKey: .parentIDs)
    }
}

struct BackupMetadata: Codable {
    var articles: [String: BackupRecord]
    var lastRunISO8601: String?

    static let empty = BackupMetadata(articles: [:], lastRunISO8601: nil)
}

struct BackupRecord: Codable {
    let updatedAt: Int64
    let filePath: String
    let exportFormat: String?
    let includeImages: Bool?
}

struct BackupStats {
    var total: Int = 0
    var created: Int = 0
    var modified: Int = 0
    var unchanged: Int = 0
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(Int64(value)) }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected string-like value")
        )
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if !contains(key) { return nil }
        if (try? decodeNil(forKey: key)) == true { return nil }

        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(Int64(value)) }
        return nil
    }

    func decodeFlexibleInt64IfPresent(forKey key: Key) throws -> Int64? {
        if !contains(key) { return nil }
        if (try? decodeNil(forKey: key)) == true { return nil }

        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decode(Double.self, forKey: key) { return Int64(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }

    func decodeFlexibleStringArrayIfPresent(forKey key: Key) throws -> [String]? {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let values = try? decodeIfPresent([Int].self, forKey: key) {
            return values.map(String.init)
        }
        if let values = try? decodeIfPresent([Int64].self, forKey: key) {
            return values.map(String.init)
        }
        return nil
    }
}
