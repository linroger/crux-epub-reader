import Foundation
import Compression

enum EPUBParserError: Error, LocalizedError {
    case invalidEPUB
    case missingContainer
    case missingOPF
    case parsingFailed(String)
    case unsupportedCompression(Int)
    case decompressionFailed
    case invalidEncoding
    case corruptedFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidEPUB:
            return "The file is not a valid EPUB"
        case .missingContainer:
            return "Missing container.xml in EPUB"
        case .missingOPF:
            return "Missing OPF file in EPUB"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .unsupportedCompression(let method):
            return "Unsupported compression method: \(method)"
        case .decompressionFailed:
            return "Failed to decompress file data"
        case .invalidEncoding:
            return "Unable to decode file content - invalid character encoding"
        case .corruptedFile(let detail):
            return "EPUB file appears to be corrupted: \(detail)"
        }
    }
}

actor EPUBParser {
    private let fileManager = FileManager.default
    
    /// Supported text encodings to try when reading files
    private let supportedEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .isoLatin1,
        .windowsCP1252,
        .ascii
    ]

    func parse(url: URL) async throws -> Book {
        // Diagnostics: log the file we're about to parse so issues found
        // weeks later can be cross-referenced with Console logs.
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        AppLog.parser.info("Parsing EPUB \(url.lastPathComponent, privacy: .public) size=\(fileSize, privacy: .public)")

        // Create temp directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Extract EPUB (it's a ZIP file)
        do {
            try await extractZip(from: url, to: tempDir)
        } catch {
            AppLog.parser.error("Extract failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Parse container.xml to find OPF location
        // Try multiple possible locations for container.xml (some EPUBs have case variations)
        let containerPaths = [
            "META-INF/container.xml",
            "meta-inf/container.xml",
            "META-INF/Container.xml",
            "OEBPS/container.xml"  // Non-standard but sometimes seen
        ]

        var containerURL: URL?
        for path in containerPaths {
            let candidatePath = tempDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: candidatePath.path) {
                containerURL = candidatePath
                break
            }
        }

        // If not found in standard locations, search recursively
        if containerURL == nil {
            AppLog.parser.notice("container.xml not at standard path — searching recursively")
            containerURL = findFile(named: "container.xml", in: tempDir)
        }

        guard let finalContainerURL = containerURL else {
            AppLog.parser.error("Missing container.xml entirely; treating as invalid EPUB")
            throw EPUBParserError.missingContainer
        }

        let containerData = try Data(contentsOf: finalContainerURL)
        let opfPath = try parseContainer(containerData)

        // Parse OPF file - handle URL-encoded paths
        let decodedOPFPath = opfPath.removingPercentEncoding ?? opfPath
        var opfURL = tempDir.appendingPathComponent(decodedOPFPath)

        // If OPF not found at expected path, try to find it
        if !fileManager.fileExists(atPath: opfURL.path) {
            if let foundOPF = findFile(withExtension: "opf", in: tempDir) {
                AppLog.parser.notice("OPF declared at \(decodedOPFPath, privacy: .public) but recovered via recursive search")
                opfURL = foundOPF
            } else {
                AppLog.parser.error("Missing OPF file — declared path \(decodedOPFPath, privacy: .public)")
                throw EPUBParserError.missingOPF
            }
        }

        let opfData = try Data(contentsOf: opfURL)
        let opfDirectory = opfURL.deletingLastPathComponent()

        let book = try parseOPF(opfData, baseURL: opfDirectory, fileURL: url)
        AppLog.parser.info("Parsed \(book.chapters.count, privacy: .public) chapters from \(url.lastPathComponent, privacy: .public)")
        return book
    }
    
    /// Finds a file with the given name recursively in a directory
    private func findFile(named name: String, in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.lastPathComponent.lowercased() == name.lowercased() {
                return fileURL
            }
        }
        return nil
    }
    
    /// Finds a file with the given extension recursively in a directory
    private func findFile(withExtension ext: String, in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == ext.lowercased() {
                return fileURL
            }
        }
        return nil
    }
    
    /// Reads string content from data, trying multiple encodings
    private func readString(from data: Data) -> String? {
        // First, try to detect encoding from BOM or XML declaration
        if let detected = detectEncoding(from: data), let string = String(data: data, encoding: detected) {
            return string
        }
        
        // Try each supported encoding
        for encoding in supportedEncodings {
            if let string = String(data: data, encoding: encoding) {
                // Verify it contains valid XML-like content
                if string.contains("<") || string.contains("<?xml") {
                    return string
                }
            }
        }
        
        // Last resort: lossy conversion
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
    
    /// Attempts to detect encoding from BOM or XML declaration
    private func detectEncoding(from data: Data) -> String.Encoding? {
        // Check for BOM
        if data.count >= 3 {
            let bytes = Array(data.prefix(3))
            if bytes == [0xEF, 0xBB, 0xBF] {
                return .utf8
            }
        }
        if data.count >= 2 {
            let bytes = Array(data.prefix(2))
            if bytes == [0xFE, 0xFF] {
                return .utf16BigEndian
            }
            if bytes == [0xFF, 0xFE] {
                return .utf16LittleEndian
            }
        }
        
        // Try to read as ASCII and check for encoding declaration
        if let asciiString = String(data: data.prefix(1000), encoding: .ascii) {
            if asciiString.lowercased().contains("encoding=\"utf-16\"") {
                return .utf16
            }
            if asciiString.lowercased().contains("encoding=\"iso-8859-1\"") {
                return .isoLatin1
            }
            if asciiString.lowercased().contains("encoding=\"windows-1252\"") {
                return .windowsCP1252
            }
        }
        
        return nil
    }

    private func extractZip(from zipURL: URL, to destination: URL) async throws {
        let zipData = try Data(contentsOf: zipURL)
        try extractZipData(zipData, to: destination)
    }

    // MARK: - Pure Swift ZIP Extraction

    private func extractZipData(_ data: Data, to destination: URL) throws {
        var offset = 0
        var fileCount = 0
        let maxFiles = 10000 // Safety limit to prevent zip bombs
        var extractionErrors: [String] = []

        while offset + 30 <= data.count && fileCount < maxFiles {
            // Check for local file header signature: 0x04034b50 (little-endian: 50 4b 03 04)
            guard offset + 4 <= data.count else { break }
            let sig = data.subdata(in: offset..<offset+4)
            
            // Check for end-of-central-directory or central directory header
            if sig == Data([0x50, 0x4b, 0x01, 0x02]) || sig == Data([0x50, 0x4b, 0x05, 0x06]) {
                // Central directory or end - stop processing
                break
            }
            
            guard sig == Data([0x50, 0x4b, 0x03, 0x04]) else {
                // Not a recognized header - try to find next valid header
                if let nextHeader = findNextZipHeader(in: data, from: offset + 1) {
                    offset = nextHeader
                    continue
                }
                break
            }

            // Parse local file header with bounds checking
            guard offset + 30 <= data.count else {
                extractionErrors.append("Truncated local file header at offset \(offset)")
                break
            }
            
            let generalPurpose = readUInt16(data, at: offset + 6)
            let compressionMethod = readUInt16(data, at: offset + 8)
            let compressedSize = readUInt32(data, at: offset + 18)
            let uncompressedSize = readUInt32(data, at: offset + 22)
            let fileNameLength = Int(readUInt16(data, at: offset + 26))
            let extraFieldLength = Int(readUInt16(data, at: offset + 28))

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + fileNameLength

            guard fileNameEnd <= data.count else {
                extractionErrors.append("Invalid filename length at offset \(offset)")
                break
            }

            let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
            
            // Try multiple encodings for filename
            var fileName: String?
            for encoding in [String.Encoding.utf8, .isoLatin1, .windowsCP1252, .ascii] {
                if let name = String(data: fileNameData, encoding: encoding) {
                    fileName = name
                    break
                }
            }
            
            guard let validFileName = fileName else {
                // Skip this file but continue
                extractionErrors.append("Unable to decode filename at offset \(offset)")
                offset = fileNameEnd + extraFieldLength + Int(compressedSize)
                continue
            }
            
            // Sanitize filename to prevent directory traversal attacks
            let sanitizedFileName = sanitizeFilePath(validFileName)

            let dataStart = fileNameEnd + extraFieldLength

            // Handle data descriptor (bit 3 of general purpose flag)
            var actualCompressedSize = Int(compressedSize)
            let actualUncompressedSize = Int(uncompressedSize)

            if (generalPurpose & 0x08) != 0 && compressedSize == 0 {
                // Data descriptor follows - need to find it by scanning
                if let nextHeader = findNextZipHeader(in: data, from: dataStart) {
                    actualCompressedSize = nextHeader - dataStart
                    // Check if there's a data descriptor (12 or 16 bytes before next header)
                    if nextHeader >= dataStart + 16 {
                        let potentialSig = data.subdata(in: (nextHeader - 16)..<(nextHeader - 12))
                        if potentialSig == Data([0x50, 0x4b, 0x07, 0x08]) {
                            actualCompressedSize = nextHeader - 16 - dataStart
                        }
                    }
                } else {
                    // Try to find by looking at end of archive
                    actualCompressedSize = data.count - dataStart
                }
            }

            let dataEnd = min(dataStart + actualCompressedSize, data.count)

            guard dataEnd <= data.count && dataStart <= dataEnd else {
                extractionErrors.append("Invalid data range for file \(sanitizedFileName)")
                offset = dataStart + 1
                continue
            }

            let compressedData = data.subdata(in: dataStart..<dataEnd)

            // Create file path
            let filePath = destination.appendingPathComponent(sanitizedFileName)

            // Handle directories
            if sanitizedFileName.hasSuffix("/") || (compressionMethod == 0 && compressedSize == 0 && uncompressedSize == 0) {
                try? fileManager.createDirectory(at: filePath, withIntermediateDirectories: true)
            } else {
                // Ensure parent directory exists
                let parentDir = filePath.deletingLastPathComponent()
                try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                // Decompress and write file
                do {
                    let decompressedData: Data

                    switch compressionMethod {
                    case 0: // Stored (no compression)
                        decompressedData = compressedData
                    case 8: // Deflate
                        decompressedData = try decompressDeflate(compressedData, expectedSize: actualUncompressedSize > 0 ? actualUncompressedSize : max(compressedData.count * 4, 65536))
                    case 9: // Deflate64 - try with larger buffer
                        decompressedData = try decompressDeflate(compressedData, expectedSize: max(actualUncompressedSize, compressedData.count * 8))
                    default:
                        extractionErrors.append("Skipping \(sanitizedFileName): unsupported compression method \(compressionMethod)")
                        offset = dataEnd
                        fileCount += 1
                        continue
                    }

                    try decompressedData.write(to: filePath)
                } catch {
                    extractionErrors.append("Failed to decompress \(sanitizedFileName): \(error.localizedDescription)")
                    // Continue with other files
                }
            }

            offset = dataEnd
            fileCount += 1
        }
        
        // If we couldn't extract any files, report an error
        if fileCount == 0 && !extractionErrors.isEmpty {
            throw EPUBParserError.corruptedFile(extractionErrors.joined(separator: "; "))
        }
    }
    
    /// Sanitizes a file path to prevent directory traversal attacks
    private func sanitizeFilePath(_ path: String) -> String {
        var sanitized = path
        
        // Remove leading slashes and ".." components
        sanitized = sanitized.replacingOccurrences(of: "../", with: "")
        sanitized = sanitized.replacingOccurrences(of: "..\\", with: "")
        
        // Remove leading slashes
        while sanitized.hasPrefix("/") || sanitized.hasPrefix("\\") {
            sanitized = String(sanitized.dropFirst())
        }
        
        // Replace backslashes with forward slashes
        sanitized = sanitized.replacingOccurrences(of: "\\", with: "/")
        
        return sanitized
    }

    private func findNextZipHeader(in data: Data, from start: Int) -> Int? {
        var i = start
        while i + 4 <= data.count {
            let sig = data.subdata(in: i..<i+4)
            // Local file header or central directory header
            if sig == Data([0x50, 0x4b, 0x03, 0x04]) || sig == Data([0x50, 0x4b, 0x01, 0x02]) {
                return i
            }
            i += 1
        }
        return data.count
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
               (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) |
               (UInt32(data[offset + 3]) << 24)
    }

    private func decompressDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        // Handle empty data
        if data.isEmpty {
            return Data()
        }
        
        // Use raw DEFLATE (no zlib header) - ZIP uses raw deflate
        // Try progressively larger buffer sizes if needed
        let bufferSizes = [
            max(expectedSize, 65536),
            expectedSize * 2,
            expectedSize * 4,
            1024 * 1024,  // 1MB
            4 * 1024 * 1024  // 4MB max
        ]
        
        for bufferSize in bufferSizes {
            var decompressed = Data(count: bufferSize)

            let result = data.withUnsafeBytes { sourcePtr -> Int in
                decompressed.withUnsafeMutableBytes { destPtr -> Int in
                    guard let sourceBase = sourcePtr.baseAddress,
                          let destBase = destPtr.baseAddress else { return 0 }

                    let decodedSize = compression_decode_buffer(
                        destBase.assumingMemoryBound(to: UInt8.self),
                        bufferSize,
                        sourceBase.assumingMemoryBound(to: UInt8.self),
                        data.count,
                        nil,
                        COMPRESSION_ZLIB  // Note: This handles raw deflate
                    )
                    return decodedSize
                }
            }

            if result > 0 {
                decompressed.removeSubrange(result..<decompressed.count)
                return decompressed
            }
            
            // If we got exactly the buffer size, we might need a larger buffer
            if result == bufferSize && bufferSize < bufferSizes.last! {
                continue
            }
        }
        
        throw EPUBParserError.decompressionFailed
    }

    private func parseContainer(_ data: Data) throws -> String {
        guard let content = readString(from: data) else {
            throw EPUBParserError.parsingFailed("Cannot read container.xml")
        }

        // Try multiple patterns to extract rootfile path (some EPUBs use single quotes or have extra whitespace)
        let patterns = [
            #"full-path="([^"]+)""#,
            #"full-path='([^']+)'"#,
            #"full-path\s*=\s*"([^"]+)""#,
            #"full-path\s*=\s*'([^']+)'"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return decodeHTMLEntities(String(content[range]))
            }
        }
        
        // Fallback: try to find any .opf reference
        let opfPattern = #"[\"']([^\"']+\.opf)[\"']"#
        if let regex = try? NSRegularExpression(pattern: opfPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return decodeHTMLEntities(String(content[range]))
        }

        throw EPUBParserError.missingOPF
    }

    private func parseOPF(_ data: Data, baseURL: URL, fileURL: URL) throws -> Book {
        guard let content = readString(from: data) else {
            throw EPUBParserError.parsingFailed("Cannot read OPF file")
        }

        // Extract metadata with fallbacks for different namespace patterns
        let title = extractMetadata(from: content, tag: "dc:title") 
            ?? extractMetadata(from: content, tag: "title")
            ?? extractTitleFromFilename(fileURL)
            ?? "Unknown Title"
        
        let author = extractMetadata(from: content, tag: "dc:creator")
            ?? extractMetadata(from: content, tag: "creator")
        
        let language = extractMetadata(from: content, tag: "dc:language")
            ?? extractMetadata(from: content, tag: "language")
        
        let publisher = extractMetadata(from: content, tag: "dc:publisher")
            ?? extractMetadata(from: content, tag: "publisher")
        
        let description = extractMetadata(from: content, tag: "dc:description")
            ?? extractMetadata(from: content, tag: "description")

        // Build manifest (id -> href mapping)
        let manifest = parseManifest(content)

        // Try to parse TOC from NCX (EPUB 2) or nav.xhtml (EPUB 3)
        var chapters = try parseTOC(content, manifest: manifest, baseURL: baseURL)

        // If no TOC found, fall back to spine-based chapters
        if chapters.isEmpty {
            chapters = try parseSpineFallback(content, manifest: manifest, baseURL: baseURL)
        }
        
        // If still no chapters, try to find any HTML/XHTML files
        if chapters.isEmpty {
            chapters = try findHTMLChaptersFallback(baseURL: baseURL)
        }

        // Every strategy failed. Surface a clear error instead of importing a
        // book that would open to an empty reader with no explanation.
        guard !chapters.isEmpty else {
            throw EPUBParserError.parsingFailed("No readable chapters were found in this EPUB.")
        }

        // Try to find cover image with multiple strategies
        let coverImage = findCoverImage(content, manifest: manifest, baseURL: baseURL)

        return Book(
            fileURL: fileURL,
            title: title,
            author: author,
            coverImage: coverImage,
            chapters: chapters,
            metadata: BookMetadata(
                language: language,
                publisher: publisher,
                description: description
            )
        )
    }
    
    /// Extracts a reasonable title from the filename
    private func extractTitleFromFilename(_ url: URL) -> String? {
        let filename = url.deletingPathExtension().lastPathComponent
        // Replace common separators with spaces and clean up
        let cleaned = filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned.isEmpty ? nil : cleaned
    }
    
    /// Last resort fallback: find any HTML/XHTML files and create chapters from them
    private func findHTMLChaptersFallback(baseURL: URL) throws -> [Chapter] {
        var chapters: [Chapter] = []
        
        guard let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var htmlFiles: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "html" || ext == "xhtml" || ext == "htm" {
                htmlFiles.append(fileURL)
            }
        }
        
        // Sort by filename
        htmlFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        for (index, htmlURL) in htmlFiles.enumerated() {
            let contentData = try? Data(contentsOf: htmlURL)
            let contentString = contentData.flatMap { readString(from: $0) } ?? ""
            let title = extractChapterTitle(from: contentString) ?? htmlURL.deletingPathExtension().lastPathComponent
            
            // Get relative path from baseURL
            let relativePath = htmlURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
            
            chapters.append(Chapter(
                id: "fallback-\(index)",
                title: title,
                href: relativePath,
                content: contentString,
                order: index,
                depth: 0
            ))
        }
        
        return chapters
    }

    private func extractMetadata(from content: String, tag: String) -> String? {
        // Try multiple patterns to handle different XML formatting styles
        let patterns = [
            // Standard: <dc:title>Content</dc:title>
            "<\(tag)[^>]*>([^<]+)</\(tag)>",
            // With CDATA: <dc:title><![CDATA[Content]]></dc:title>
            "<\(tag)[^>]*><!\\[CDATA\\[([^\\]]+)\\]\\]></\(tag)>",
            // Self-closing with content attribute: <dc:title content="value"/>
            "<\(tag)[^>]+content=[\"']([^\"']+)[\"']",
            // With nested tags (common in some EPUBs): <dc:title><span>Content</span></dc:title>
            "<\(tag)[^>]*>\\s*<[^>]+>([^<]+)</[^>]+>\\s*</\(tag)>"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                let extracted = decodeHTMLEntities(String(content[range]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    return extracted
                }
            }
        }
        return nil
    }

    private func parseManifest(_ content: String) -> [String: String] {
        var manifest: [String: String] = [:]
        
        // More flexible item pattern that handles various formatting
        let itemPatterns = [
            #"<item\s+([^>]+)/?\s*>"#,
            #"<item\s+([^>]+)>"#
        ]
        
        for itemPattern in itemPatterns {
            if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let matches = itemRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let attrsRange = Range(match.range(at: 1), in: content) {
                        let attrs = String(content[attrsRange])

                        // Support both double and single quotes
                        let idPatterns = [#"id="([^"]+)""#, #"id='([^']+)'"#]
                        let hrefPatterns = [#"href="([^"]+)""#, #"href='([^']+)'"#]

                        var itemId: String?
                        var itemHref: String?

                        for idPattern in idPatterns {
                            if let idRegex = try? NSRegularExpression(pattern: idPattern, options: .caseInsensitive),
                               let idMatch = idRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                               let idRange = Range(idMatch.range(at: 1), in: attrs) {
                                itemId = decodeHTMLEntities(String(attrs[idRange]))
                                break
                            }
                        }
                        
                        for hrefPattern in hrefPatterns {
                            if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive),
                               let hrefMatch = hrefRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                               let hrefRange = Range(hrefMatch.range(at: 1), in: attrs) {
                                itemHref = decodeHTMLEntities(String(attrs[hrefRange]))
                                break
                            }
                        }

                        if let id = itemId, let href = itemHref {
                            manifest[id] = href
                        }
                    }
                }
            }
        }

        return manifest
    }

    // MARK: - TOC Parsing

    private func parseTOC(_ opfContent: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        // First try EPUB 3 nav document
        if let navChapters = try? parseEPUB3Nav(opfContent, manifest: manifest, baseURL: baseURL), !navChapters.isEmpty {
            return navChapters
        }

        // Fall back to EPUB 2 NCX
        if let ncxChapters = try? parseNCX(opfContent, manifest: manifest, baseURL: baseURL), !ncxChapters.isEmpty {
            return ncxChapters
        }

        return []
    }

    // MARK: - EPUB 3 Navigation Document

    private func parseEPUB3Nav(_ opfContent: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        // Find nav document in manifest (has properties="nav")
        let navPattern = #"<item[^>]+properties="[^"]*nav[^"]*"[^>]+href="([^"]+)""#
        let navPatternAlt = #"<item[^>]+href="([^"]+)"[^>]+properties="[^"]*nav[^"]*""#

        var navHref: String?

        for pattern in [navPattern, navPatternAlt] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: opfContent, range: NSRange(opfContent.startIndex..., in: opfContent)),
               let range = Range(match.range(at: 1), in: opfContent) {
                navHref = String(opfContent[range])
                break
            }
        }

        guard let href = navHref else { return [] }

        let navURL = baseURL.appendingPathComponent(href)
        let navDirectory = navURL.deletingLastPathComponent()
        guard let navContent = try? String(contentsOf: navURL, encoding: .utf8) else { return [] }

        return parseNavDocument(navContent, baseURL: navDirectory)
    }

    private func parseNavDocument(_ content: String, baseURL: URL) -> [Chapter] {
        var chapters: [Chapter] = []
        var order = 0

        // Find the toc nav element
        let tocPattern = #"<nav[^>]+epub:type="toc"[^>]*>([\s\S]*?)</nav>"#
        guard let regex = try? NSRegularExpression(pattern: tocPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return []
        }

        let tocContent = String(content[range])
        parseNavList(tocContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: 0)

        return chapters
    }

    /// Maximum table-of-contents nesting we'll recurse through. Real TOCs
    /// rarely exceed three or four levels; this cap stops a malformed or
    /// maliciously deep nav/NCX document from overflowing the stack.
    private static let maxTOCDepth = 64

    private func parseNavList(_ content: String, baseURL: URL, chapters: inout [Chapter], order: inout Int, depth: Int) {
        guard depth < Self.maxTOCDepth else {
            AppLog.parser.warning("Nav list nesting exceeded \(Self.maxTOCDepth) levels; stopping recursion.")
            return
        }
        // Parse <li> elements with <a> tags
        let liPattern = #"<li[^>]*>([\s\S]*?)</li>"#

        guard let liRegex = try? NSRegularExpression(pattern: liPattern, options: .caseInsensitive) else { return }

        let matches = liRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            guard let range = Range(match.range(at: 1), in: content) else { continue }
            let liContent = String(content[range])

            // Extract the anchor. The inner capture is `[\s\S]*?` (not
            // `[^<]+`) so titles wrapped in nested markup survive; `cleanTitle`
            // strips the tags afterward. href accepts single or double quotes.
            let aPattern = #"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#
            if let aRegex = try? NSRegularExpression(pattern: aPattern, options: .caseInsensitive),
               let aMatch = aRegex.firstMatch(in: liContent, range: NSRange(liContent.startIndex..., in: liContent)),
               let hrefRange = Range(aMatch.range(at: 1), in: liContent),
               let textRange = Range(aMatch.range(at: 2), in: liContent) {

                let href = decodeHTMLEntities(String(liContent[hrefRange]))
                let title = cleanTitle(String(liContent[textRange]))

                if !title.isEmpty {
                    let filePath = href.components(separatedBy: "#").first ?? href
                    let contentURL = baseURL.appendingPathComponent(filePath.removingPercentEncoding ?? filePath)
                    let contentString = (try? String(contentsOf: contentURL, encoding: .utf8)) ?? ""

                    chapters.append(Chapter(
                        id: "nav-\(order)",
                        title: title,
                        href: href,
                        content: contentString,
                        order: order,
                        depth: depth
                    ))
                    order += 1
                }
            }

            // Check for nested <ol> (sub-items)
            let nestedOlPattern = #"<ol[^>]*>([\s\S]*?)</ol>"#
            if let olRegex = try? NSRegularExpression(pattern: nestedOlPattern, options: .caseInsensitive),
               let olMatch = olRegex.firstMatch(in: liContent, range: NSRange(liContent.startIndex..., in: liContent)),
               let olRange = Range(olMatch.range(at: 1), in: liContent) {
                let nestedContent = String(liContent[olRange])
                parseNavList(nestedContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: depth + 1)
            }
        }
    }

    // MARK: - EPUB 2 NCX Parsing

    private func parseNCX(_ opfContent: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        // Find NCX file in manifest (media-type="application/x-dtbncx+xml")
        var ncxHref: String?

        for (_, href) in manifest {
            if href.lowercased().hasSuffix(".ncx") {
                ncxHref = href
                break
            }
        }

        // Also check for explicit NCX reference in spine
        let spinePattern = #"<spine[^>]+toc="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: spinePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: opfContent, range: NSRange(opfContent.startIndex..., in: opfContent)),
           let range = Range(match.range(at: 1), in: opfContent) {
            let tocId = String(opfContent[range])
            if let href = manifest[tocId] {
                ncxHref = href
            }
        }

        guard let href = ncxHref else { return [] }

        let ncxURL = baseURL.appendingPathComponent(href)
        let ncxDirectory = ncxURL.deletingLastPathComponent()
        guard let ncxContent = try? String(contentsOf: ncxURL, encoding: .utf8) else { return [] }

        return parseNCXContent(ncxContent, baseURL: ncxDirectory)
    }

    private func parseNCXContent(_ content: String, baseURL: URL) -> [Chapter] {
        var chapters: [Chapter] = []
        var order = 0

        // Find navMap - use greedy match since there's only one navMap
        guard let navMapStart = content.range(of: "<navMap", options: .caseInsensitive),
              let navMapEnd = content.range(of: "</navMap>", options: .caseInsensitive) else {
            return []
        }

        let navMapContent = String(content[navMapStart.upperBound..<navMapEnd.lowerBound])

        // Find top-level navPoints and process them recursively
        parseNavPointsAtLevel(navMapContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: 0)

        return chapters
    }

    /// Parse navPoints at a given level, handling nesting recursively
    private func parseNavPointsAtLevel(_ content: String, baseURL: URL, chapters: inout [Chapter], order: inout Int, depth: Int) {
        guard depth < Self.maxTOCDepth else {
            AppLog.parser.warning("NCX navPoint nesting exceeded \(Self.maxTOCDepth) levels; stopping recursion.")
            return
        }
        var searchStart = content.startIndex

        while let openRange = content.range(of: "<navPoint", options: .caseInsensitive, range: searchStart..<content.endIndex) {
            // Find the matching </navPoint> tag, accounting for nesting
            guard let navPointEnd = findMatchingCloseTag(in: content, tagName: "navPoint", from: openRange.lowerBound) else {
                break
            }

            let navPointContent = String(content[openRange.lowerBound..<navPointEnd])
            processNavPointRecursive(navPointContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: depth)

            searchStart = navPointEnd
        }
    }

    /// Find the matching close tag for a given open tag, handling nesting
    private func findMatchingCloseTag(in content: String, tagName: String, from startIndex: String.Index) -> String.Index? {
        let openTag = "<\(tagName)"
        let closeTag = "</\(tagName)>"

        var nestLevel = 0
        var currentIndex = startIndex

        while currentIndex < content.endIndex {
            let remaining = content[currentIndex...]

            if remaining.hasPrefix(openTag) {
                nestLevel += 1
                currentIndex = content.index(currentIndex, offsetBy: openTag.count, limitedBy: content.endIndex) ?? content.endIndex
            } else if remaining.hasPrefix(closeTag) {
                nestLevel -= 1
                if nestLevel == 0 {
                    return content.index(currentIndex, offsetBy: closeTag.count, limitedBy: content.endIndex)
                }
                currentIndex = content.index(currentIndex, offsetBy: closeTag.count, limitedBy: content.endIndex) ?? content.endIndex
            } else {
                currentIndex = content.index(after: currentIndex)
            }
        }

        return nil
    }

    /// Process a single navPoint and its children recursively
    private func processNavPointRecursive(_ content: String, baseURL: URL, chapters: inout [Chapter], order: inout Int, depth: Int) {
        // Extract navLabel text
        var title = ""
        if let labelStart = content.range(of: "<navLabel", options: .caseInsensitive),
           let textStart = content.range(of: "<text", options: .caseInsensitive, range: labelStart.upperBound..<content.endIndex),
           let textContentStart = content.range(of: ">", range: textStart.upperBound..<content.endIndex),
           let textEnd = content.range(of: "</text>", options: .caseInsensitive, range: textContentStart.upperBound..<content.endIndex) {
            // NCX <text> can contain inline markup; cleanTitle strips it so
            // the sidebar never shows tags like "<span>1.</span> Intro".
            title = cleanTitle(String(content[textContentStart.upperBound..<textEnd.lowerBound]))
        }

        // Extract navPoint id attribute (single or double quotes). The
        // navPoint's own id is the first `id=` in the content.
        let navPointId = attributeValue("id", in: content) ?? "ncx-\(order)"

        // Extract content src (single or double quotes). Scope to the
        // <content> tag so a stray src elsewhere can't be picked up.
        var href = ""
        if let contentTag = content.range(of: "<content", options: .caseInsensitive),
           let src = attributeValue("src", in: String(content[contentTag.lowerBound...])) {
            href = decodeHTMLEntities(src)
        }

        // Add this navPoint as a chapter
        if !title.isEmpty && !href.isEmpty {
            let filePath = href.components(separatedBy: "#").first ?? href
            let contentURL = baseURL.appendingPathComponent(filePath.removingPercentEncoding ?? filePath)
            let contentString = (try? String(contentsOf: contentURL, encoding: .utf8)) ?? ""

            chapters.append(Chapter(
                id: navPointId,
                title: title,
                href: href,
                content: contentString,
                order: order,
                depth: depth
            ))
            order += 1
        }

        // Find nested navPoints (children of this navPoint)
        // They appear after the </content> tag but before the final </navPoint>
        if let contentTagStart = content.range(of: "<content", options: .caseInsensitive),
           let contentTagEnd = content.range(of: "/>", range: contentTagStart.upperBound..<content.endIndex) {
            // Get content after the <content .../> tag
            let afterContent = String(content[contentTagEnd.upperBound...])

            // Remove the final </navPoint> and process nested navPoints
            let options: String.CompareOptions = [.caseInsensitive, .backwards]
            if let lastClose = afterContent.range(of: "</navPoint>", options: options) {
                let nestedContent = String(afterContent[..<lastClose.lowerBound])
                if nestedContent.contains("<navPoint") {
                    parseNavPointsAtLevel(nestedContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Fallback: Spine-based chapters

    private func parseSpineFallback(_ content: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        var chapters: [Chapter] = []

        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for (index, match) in matches.enumerated() {
                if let idRange = Range(match.range(at: 1), in: content) {
                    let idref = String(content[idRange])
                    if let href = manifest[idref] {
                        let chapterURL = baseURL.appendingPathComponent(href)
                        let chapterContent = (try? String(contentsOf: chapterURL, encoding: .utf8)) ?? ""
                        let title = extractChapterTitle(from: chapterContent) ?? "Chapter \(index + 1)"

                        chapters.append(Chapter(
                            id: idref,
                            title: title,
                            href: href,
                            content: chapterContent,
                            order: index,
                            depth: 0
                        ))
                    }
                }
            }
        }

        return chapters
    }

    private func extractChapterTitle(from html: String) -> String? {
        for tag in ["h1", "h2", "title"] {
            // Inner capture is `[\s\S]*?` so headings with inline markup
            // (e.g. `<h1>Chapter <em>One</em></h1>`) are captured in full and
            // cleaned, instead of failing to match and falling back to
            // "Chapter N".
            let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let title = cleanTitle(String(html[range]))
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }

    // MARK: - Cover Image

    private func findCoverImage(_ content: String, manifest: [String: String], baseURL: URL) -> Data? {
        // Strategy 1: Look for cover in metadata
        let metaCoverPatterns = [
            #"<meta[^>]+name="cover"[^>]+content="([^"]+)""#,
            #"<meta[^>]+content="([^"]+)"[^>]+name="cover""#
        ]
        
        for pattern in metaCoverPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                let coverId = String(content[range])
                if let href = manifest[coverId] {
                    let coverURL = baseURL.appendingPathComponent(href)
                    if let data = try? Data(contentsOf: coverURL) {
                        return data
                    }
                }
            }
        }
        
        // Strategy 2: Look for item with id containing "cover" and image media type
        let coverItemPatterns = [
            #"<item[^>]+id="[^"]*cover[^"]*"[^>]+href="([^"]+)"[^>]+media-type="image/[^"]+""#,
            #"<item[^>]+href="([^"]+)"[^>]+id="[^"]*cover[^"]*"[^>]+media-type="image/[^"]+""#,
            #"<item[^>]+id="cover[^"]*"[^>]+href="([^"]+)""#,
            #"<item[^>]+href="([^"]+)"[^>]+id="cover[^"]*""#
        ]
        
        for pattern in coverItemPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                let href = decodeHTMLEntities(String(content[range]))
                let coverURL = baseURL.appendingPathComponent(href)
                if let data = try? Data(contentsOf: coverURL) {
                    return data
                }
            }
        }
        
        // Strategy 3: Look for item with properties="cover-image" (EPUB 3)
        let coverImagePatterns = [
            #"<item[^>]+properties="[^"]*cover-image[^"]*"[^>]+href="([^"]+)""#,
            #"<item[^>]+href="([^"]+)"[^>]+properties="[^"]*cover-image[^"]*""#
        ]
        
        for pattern in coverImagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                let href = decodeHTMLEntities(String(content[range]))
                let coverURL = baseURL.appendingPathComponent(href)
                if let data = try? Data(contentsOf: coverURL) {
                    return data
                }
            }
        }
        
        // Strategy 4: Look for common cover image filenames in manifest
        let commonCoverNames = ["cover", "Cover", "COVER", "cover-image", "frontcover", "book-cover"]
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
        
        for (_, href) in manifest {
            let filename = URL(fileURLWithPath: href).deletingPathExtension().lastPathComponent.lowercased()
            let ext = URL(fileURLWithPath: href).pathExtension.lowercased()
            
            if imageExtensions.contains(ext) && commonCoverNames.contains(where: { filename.contains($0.lowercased()) }) {
                let coverURL = baseURL.appendingPathComponent(href)
                if let data = try? Data(contentsOf: coverURL) {
                    return data
                }
            }
        }
        
        // Strategy 5: Find first image in images directory
        let imageDirectories = ["images", "Images", "IMAGES", "img", "IMG", "media", "Media"]
        for dir in imageDirectories {
            let dirURL = baseURL.appendingPathComponent(dir)
            if let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    if imageExtensions.contains(ext) {
                        if let data = try? Data(contentsOf: fileURL) {
                            return data
                        }
                    }
                }
            }
        }
        
        return nil
    }

    // MARK: - Utilities

    /// Extracts the first value of `name="…"` or `name='…'` from a fragment
    /// of markup. XML attributes may use either quote style; the older NCX
    /// parser only matched double quotes and silently dropped chapters whose
    /// `src`/`id` were single-quoted (which is perfectly valid XML).
    private func attributeValue(_ name: String, in text: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Normalize a raw table-of-contents label into clean display text.
    ///
    /// TOC labels frequently wrap their text in nested markup — e.g.
    /// `<a href="…"><span class="num">1.</span> Introduction</a>` or
    /// `Chapter <i>One</i>`. Capturing only `[^<]` (as the old anchor regex
    /// did) either truncated such titles at the first tag or dropped the
    /// entry entirely. This strips every tag, decodes entities, and collapses
    /// the whitespace that tag removal leaves behind so the sidebar never
    /// shows raw HTML.
    ///
    /// Order matters: strip tags *before* decoding entities, otherwise a
    /// literal `&lt;` in the title would be turned into `<` and then eaten by
    /// the tag-stripping pass.
    private func cleanTitle(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded = decodeHTMLEntities(stripped)
        let collapsed = decoded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            "&#160;": " ",
            "&ndash;": "–",
            "&mdash;": "—",
            "&hellip;": "…",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\u{201D}",
            "&ldquo;": "\u{201C}"
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle decimal numeric entities like &#8220;
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let numRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[numRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        // Handle hexadecimal numeric entities like &#x201C;
        let hexPattern = #"&#[xX]([0-9a-fA-F]+);"#
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let hexRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[hexRange], radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
