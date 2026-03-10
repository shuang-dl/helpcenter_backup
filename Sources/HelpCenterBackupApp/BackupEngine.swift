import AppKit
import CoreText
import Foundation

struct BackupEngine {
    static func run(
        token: String,
        outputDirectory: URL,
        exportFormat: ExportFormat,
        includeImages: Bool,
        downloadMode: DownloadMode,
        progress: @escaping (String) -> Void
    ) async throws -> BackupStats {
        let client = IntercomClient(token: token)
        let metadataURL = outputDirectory.appendingPathComponent(".backup_metadata.json")
        let auditLogURL = outputDirectory.appendingPathComponent(".backup_history.log")
        let runID = UUID().uuidString.prefix(8)
        var metadata = loadMetadata(from: metadataURL)

        func emit(_ line: String) {
            progress(line)
            appendAuditLog(line: line, runID: String(runID), to: auditLogURL)
        }

        do {
            try ensureDirectoryExists(outputDirectory)
            emit("Starting backup run")
            emit("Fetching help centers...")
            let helpCenters = try await client.fetchHelpCenters()

            emit("Fetching collections...")
            let collections = try await client.fetchCollections()
            let collectionByID = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })

            emit("Fetching sections...")
            let sections: [SectionItem]
            do {
                sections = try await client.fetchSections()
            } catch {
                emit("Sections unavailable, continuing without section mapping: \(error.localizedDescription)")
                sections = []
            }
            let sectionByID = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })

            emit("Fetching articles...")
            let articles = try await client.fetchArticles()
            emit("Found \(articles.count) articles")
            emit("Export format: \(exportFormat.displayName), include images: \(includeImages ? "yes" : "no")")
            emit("Download mode: \(downloadMode == .fullDownload ? "full download" : "updates only")")

            var stats = BackupStats(total: articles.count, created: 0, modified: 0, unchanged: 0)

            for (index, article) in articles.enumerated() {
                let pathParts = pathHierarchy(
                    article: article,
                    collections: collectionByID,
                    sections: sectionByID,
                    helpCenters: helpCenters
                )

                let destinationDirectory = pathParts.reduce(outputDirectory) { partial, part in
                    partial.appendingPathComponent(part)
                }

                try ensureDirectoryExists(destinationDirectory)

                let articleID = article.id
                let latestUpdatedAt = article.updatedAt ?? 0
                let previous = metadata.articles[articleID]
                let baseFileName = sanitizeFileComponent(article.title ?? "Untitled")
                let outputFile = destinationDirectory.appendingPathComponent("\(baseFileName).\(exportFormat.fileExtension)")

                let isMatchingExportOptions = previous?.exportFormat == exportFormat.rawValue && previous?.includeImages == includeImages
                if downloadMode == .updatesOnly,
                   let previous,
                   previous.updatedAt >= latestUpdatedAt,
                   isMatchingExportOptions,
                   FileManager.default.fileExists(atPath: previous.filePath),
                   outputFile.path == previous.filePath {
                    stats.unchanged += 1
                    emit("[\(index + 1)/\(articles.count)] Unchanged: \(article.title ?? articleID)")
                    continue
                }

                let originalHTML = article.body ?? ""
                let imageAssets = includeImages
                    ? await downloadImages(from: originalHTML, in: destinationDirectory, assetDirectoryName: "\(baseFileName)_assets", progress: emit)
                    : []

                let renderedBodyHTML = includeImages
                    ? rewriteImageSources(in: originalHTML, with: imageAssets)
                    : removeImageTags(in: originalHTML)

                try writeArticle(
                    article: article,
                    outputFile: outputFile,
                    exportFormat: exportFormat,
                    renderedBodyHTML: renderedBodyHTML,
                    downloadedImages: imageAssets
                )

                if previous == nil {
                    stats.created += 1
                } else {
                    stats.modified += 1
                }

                metadata.articles[articleID] = BackupRecord(
                    updatedAt: latestUpdatedAt,
                    filePath: outputFile.path,
                    exportFormat: exportFormat.rawValue,
                    includeImages: includeImages
                )

                emit("[\(index + 1)/\(articles.count)] Saved: \(article.title ?? articleID)")
            }

            metadata.lastRunISO8601 = ISO8601DateFormatter().string(from: Date())
            let encodedMetadata = try JSONEncoder().encode(metadata)
            try encodedMetadata.write(to: metadataURL)

            emit("Backup finished. New: \(stats.created), Modified: \(stats.modified), Unchanged: \(stats.unchanged)")
            return stats
        } catch {
            emit("Backup failed: \(error.localizedDescription)")
            throw error
        }
    }

    private static func writeArticle(
        article: Article,
        outputFile: URL,
        exportFormat: ExportFormat,
        renderedBodyHTML: String,
        downloadedImages: [DownloadedImage]
    ) throws {
        switch exportFormat {
        case .json:
            let payload = JSONArticlePayload(
                id: article.id,
                title: article.title,
                description: article.description,
                state: article.state,
                url: article.url,
                createdAtISO8601: formatUnixDate(article.createdAt),
                updatedAtISO8601: formatUnixDate(article.updatedAt),
                bodyHTML: renderedBodyHTML,
                bodyText: htmlToText(renderedBodyHTML),
                images: downloadedImages.map { .init(remoteURL: $0.remoteURL, localPath: $0.localRelativePath) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: outputFile)

        case .markdown:
            let content = formatArticleMarkdown(article: article, bodyHTML: renderedBodyHTML, images: downloadedImages)
            try content.write(to: outputFile, atomically: true, encoding: .utf8)

        case .html:
            let content = formatArticleHTML(article: article, bodyHTML: renderedBodyHTML)
            try content.write(to: outputFile, atomically: true, encoding: .utf8)

        case .pdf:
            let text = formatArticleText(article: article, bodyText: htmlToText(renderedBodyHTML), images: downloadedImages)
            try writePDF(text: text, to: outputFile)

        case .txt:
            let text = formatArticleText(article: article, bodyText: htmlToText(renderedBodyHTML), images: downloadedImages)
            try text.write(to: outputFile, atomically: true, encoding: .utf8)
        }
    }

    private static func loadMetadata(from url: URL) -> BackupMetadata {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(BackupMetadata.self, from: data) else {
            return .empty
        }
        return decoded
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func appendAuditLog(line: String, runID: String, to url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let formatted = "[\(stamp)] [run:\(runID)] \(line)\n"
        let data = Data(formatted.utf8)

        if FileManager.default.fileExists(atPath: url.path) {
            guard let fileHandle = try? FileHandle(forWritingTo: url) else { return }
            do {
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                try fileHandle.close()
            } catch {
                try? fileHandle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }

    private static func pathHierarchy(
        article: Article,
        collections: [String: CollectionItem],
        sections: [String: SectionItem],
        helpCenters: [HelpCenter]
    ) -> [String] {
        let helpCenterByID = Dictionary(uniqueKeysWithValues: helpCenters.map { ($0.id, $0) })
        let parentCandidates = parentCandidateIDs(from: article)
        guard let parentID = parentCandidates.first(where: { collections[$0] != nil || sections[$0] != nil }) else {
            return ["_Standalone_Articles"]
        }

        var collectionChain: [CollectionItem] = []
        var sectionChain: [SectionItem] = []
        var discoveredHelpCenterID: String?
        var visitedIDs = Set<String>()

        if var section = sections[parentID] {
            while true {
                guard !visitedIDs.contains(section.id) else { break }
                visitedIDs.insert(section.id)
                sectionChain.insert(section, at: 0)

                if discoveredHelpCenterID == nil, let hcID = section.helpCenterID, !hcID.isEmpty {
                    discoveredHelpCenterID = hcID
                }

                if let nextID = section.parentID, let parentSection = sections[nextID] {
                    section = parentSection
                    continue
                }

                if let collectionID = section.collectionID, let collection = collections[collectionID] {
                    collectionChain = resolveCollectionChain(from: collection, collections: collections)
                } else if let parentID = section.parentID, let collection = collections[parentID] {
                    collectionChain = resolveCollectionChain(from: collection, collections: collections)
                }
                break
            }
        } else if let collection = collections[parentID] {
            collectionChain = resolveCollectionChain(from: collection, collections: collections)
        }

        if discoveredHelpCenterID == nil {
            discoveredHelpCenterID = collectionChain.first?.helpCenterID
        }

        var parts: [String] = []
        if let helpCenterID = discoveredHelpCenterID,
           let helpCenter = helpCenterByID[helpCenterID] {
            parts.append(sanitizeFileComponent(helpCenter.displayName ?? helpCenter.identifier ?? "HelpCenter_\(helpCenter.id)"))
        }

        for item in collectionChain {
            parts.append(sanitizeFileComponent(item.name ?? "Collection_\(item.id)"))
        }

        for item in sectionChain {
            parts.append(sanitizeFileComponent(item.name ?? "Section_\(item.id)"))
        }

        return parts.isEmpty ? ["_Standalone_Articles"] : parts
    }

    private static func resolveCollectionChain(
        from leaf: CollectionItem,
        collections: [String: CollectionItem]
    ) -> [CollectionItem] {
        var chain: [CollectionItem] = []
        var current: CollectionItem? = leaf
        var visitedIDs = Set<String>()

        while let node = current {
            guard !visitedIDs.contains(node.id) else { break }
            visitedIDs.insert(node.id)
            chain.insert(node, at: 0)

            guard let parentID = node.parentID, let parent = collections[parentID] else {
                break
            }
            current = parent
        }

        return chain
    }

    private static func parentCandidateIDs(from article: Article) -> [String] {
        var candidates: [String] = []
        if let parentID = article.parentID, !parentID.isEmpty {
            candidates.append(parentID)
        }

        if let parentIDs = article.parentIDs {
            for id in parentIDs where !id.isEmpty {
                candidates.append(id)
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func sanitizeFileComponent(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\":<>")
        let cleaned = input
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    private static func htmlToText(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }

        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func removeImageTags(in html: String) -> String {
        html.replacingOccurrences(of: "<img[^>]*>", with: "", options: .regularExpression)
    }

    private static func rewriteImageSources(in html: String, with images: [DownloadedImage]) -> String {
        var output = html
        for image in images {
            output = output.replacingOccurrences(of: image.remoteURL, with: image.localRelativePath)
        }
        return output
    }

    private static func extractImageURLs(from html: String) -> [String] {
        let pattern = #"<img[^>]+src=[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        let urls = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let srcRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return String(html[srcRange])
        }

        return Array(Set(urls)).sorted()
    }

    private static func downloadedFileExtension(from remoteURL: URL, mimeType: String?) -> String {
        let ext = remoteURL.pathExtension.lowercased()
        if !ext.isEmpty { return ext }

        switch mimeType?.lowercased() {
        case "image/jpeg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/svg+xml":
            return "svg"
        default:
            return "bin"
        }
    }

    private static func downloadImages(
        from html: String,
        in destinationDirectory: URL,
        assetDirectoryName: String,
        progress: @escaping (String) -> Void
    ) async -> [DownloadedImage] {
        let allSources = extractImageURLs(from: html)
        let remoteURLs = allSources.compactMap { URL(string: $0) }.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        if remoteURLs.isEmpty {
            return []
        }

        let assetsDirectory = destinationDirectory.appendingPathComponent(assetDirectoryName)
        try? ensureDirectoryExists(assetsDirectory)

        var output: [DownloadedImage] = []
        for (index, remoteURL) in remoteURLs.enumerated() {
            do {
                let (data, response) = try await URLSession.shared.data(from: remoteURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }

                let ext = downloadedFileExtension(from: remoteURL, mimeType: response.mimeType)
                let localFileName = "image_\(index + 1).\(ext)"
                let localURL = assetsDirectory.appendingPathComponent(localFileName)
                try data.write(to: localURL)

                output.append(DownloadedImage(
                    remoteURL: remoteURL.absoluteString,
                    localRelativePath: "\(assetDirectoryName)/\(localFileName)"
                ))
            } catch {
                progress("Image download failed: \(remoteURL.absoluteString)")
            }
        }

        return output
    }

    private static func formatArticleText(article: Article, bodyText: String, images: [DownloadedImage]) -> String {
        var lines = [
            String(repeating: "=", count: 64),
            "TITLE: \(article.title ?? "Untitled")",
            String(repeating: "=", count: 64),
            "",
            article.description.map { "SUBTITLE: \($0)" } ?? "",
            "",
            String(repeating: "-", count: 64),
            "BODY:",
            String(repeating: "-", count: 64),
            "",
            bodyText,
            "",
            String(repeating: "-", count: 64),
            "Article ID: \(article.id)",
            "State: \(article.state ?? "unknown")",
            "URL: \(article.url ?? "N/A")",
            "Created: \(formatUnixDate(article.createdAt))",
            "Updated: \(formatUnixDate(article.updatedAt))"
        ]

        if !images.isEmpty {
            lines.append("")
            lines.append("Downloaded Images:")
            for image in images {
                lines.append("- \(image.localRelativePath)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatArticleMarkdown(article: Article, bodyHTML: String, images: [DownloadedImage]) -> String {
        var lines = [
            "# \(article.title ?? "Untitled")",
            "",
            "- **Article ID:** \(article.id)",
            "- **State:** \(article.state ?? "unknown")",
            "- **URL:** \(article.url ?? "N/A")",
            "- **Created:** \(formatUnixDate(article.createdAt))",
            "- **Updated:** \(formatUnixDate(article.updatedAt))",
            "",
            "## Body",
            "",
            htmlToText(bodyHTML)
        ]

        if !images.isEmpty {
            lines.append("")
            lines.append("## Images")
            lines.append("")
            for image in images {
                lines.append("![](\(image.localRelativePath))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatArticleHTML(article: Article, bodyHTML: String) -> String {
        """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>\(escapeHTML(article.title ?? "Untitled"))</title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 840px; margin: 40px auto; line-height: 1.6; padding: 0 16px; }
              pre { white-space: pre-wrap; }
              .meta { color: #555; font-size: 14px; }
              img { max-width: 100%; height: auto; }
            </style>
          </head>
          <body>
            <h1>\(escapeHTML(article.title ?? "Untitled"))</h1>
            <p class="meta">Article ID: \(escapeHTML(article.id))</p>
            <p class="meta">State: \(escapeHTML(article.state ?? "unknown"))</p>
            <p class="meta">URL: \(escapeHTML(article.url ?? "N/A"))</p>
            <p class="meta">Created: \(escapeHTML(formatUnixDate(article.createdAt)))</p>
            <p class="meta">Updated: \(escapeHTML(formatUnixDate(article.updatedAt)))</p>
            <hr />
            \(bodyHTML)
          </body>
        </html>
        """
    }

    private static func writePDF(text: String, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "BackupEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to initialize PDF context"]) 
        }

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.textColor
            ]
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        var currentRange = CFRange(location: 0, length: 0)

        while currentRange.location < attributed.length {
            context.beginPDFPage(nil)
            context.textMatrix = .identity

            let pageRect = CGRect(x: 36, y: 36, width: mediaBox.width - 72, height: mediaBox.height - 72)
            let path = CGMutablePath()
            path.addRect(pageRect)

            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visibleRange.length
            context.endPDFPage()

            if visibleRange.length == 0 { break }
        }

        context.closePDF()
    }

    private static func escapeHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func formatUnixDate(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "N/A" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return ISO8601DateFormatter().string(from: date)
    }
}

private struct DownloadedImage {
    let remoteURL: String
    let localRelativePath: String
}

private struct JSONArticlePayload: Encodable {
    struct JSONImage: Encodable {
        let remoteURL: String
        let localPath: String
    }

    let id: String
    let title: String?
    let description: String?
    let state: String?
    let url: String?
    let createdAtISO8601: String
    let updatedAtISO8601: String
    let bodyHTML: String
    let bodyText: String
    let images: [JSONImage]
}
