import Foundation
import Darwin

// Disk analysis is deliberately separate from ScanEngine. It retains directory
// aggregates and the bounded large-file result, never one node per discovered file.

public enum FileCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

/// User-facing content groups are derived only from file extensions for
/// analysis and presentation. They never imply that a file is disposable.
public enum DiskContentCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case documents
    case images
    case videos
    case audio
    case archives
    case development
    case other

    fileprivate var accumulatorIndex: Int {
        switch self {
        case .documents: return 0
        case .images: return 1
        case .videos: return 2
        case .audio: return 3
        case .archives: return 4
        case .development: return 5
        case .other: return 6
        }
    }

    public static func classify(path: URL) -> DiskContentCategory {
        classify(fileName: path.lastPathComponent)
    }

    static func classify(fileName: String) -> DiskContentCategory {
        // getattrlistbulk already gives us the basename as a String. Avoid
        // creating a Substring/String and lowercased copy for the common
        // ASCII filename path. Non-ASCII names retain the original fallback
        // behavior below; they cannot match the ASCII extension table unless
        // Foundation's Unicode folding would change their meaning.
        if let category = classifyASCII(fileName: fileName) {
            return category
        }
        let ext: String
        if let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex {
            ext = fileName[fileName.index(after: dot)...].lowercased()
        } else {
            ext = ""
        }
        switch ext {
        case "txt", "md", "rtf", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "csv", "json", "xml", "yaml", "yml":
            return .documents
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff", "bmp", "svg", "raw", "dng":
            return .images
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "flv":
            return .videos
        case "mp3", "m4a", "wav", "flac", "aac", "aiff", "caf", "ogg":
            return .audio
        case "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar", "dmg", "iso", "pkg":
            return .archives
        case "swift", "h", "m", "mm", "c", "cc", "cpp", "hpp", "rs", "go", "py", "js", "ts", "jsx", "tsx", "java", "kt", "kts", "rb", "php", "sh", "zsh", "fish", "sql", "plist", "xcconfig", "xcodeproj":
            return .development
        default:
            return .other
        }
    }

    private static func classifyASCII(fileName: String) -> DiskContentCategory? {
        fileName.withCString { pointer in
            var length = 0
            var lastDot = -1
            while pointer[length] != 0 {
                let byte = UInt8(bitPattern: pointer[length])
                guard byte < 0x80 else { return nil }
                if byte == 0x2E { lastDot = length }
                length += 1
            }
            guard lastDot >= 0, lastDot + 1 < length else { return .other }
            let extensionStart = lastDot + 1
            let extensionLength = length - extensionStart

            func matches(_ literal: StaticString) -> Bool {
                literal.withUTF8Buffer { literalBytes in
                    guard literalBytes.count == extensionLength else { return false }
                    for index in 0..<extensionLength {
                        var value = UInt8(bitPattern: pointer[extensionStart + index])
                        if value >= 0x41 && value <= 0x5A { value += 0x20 }
                        if value != literalBytes[index] { return false }
                    }
                    return true
                }
            }

            if matches("txt") || matches("md") || matches("rtf") || matches("pdf") ||
                matches("doc") || matches("docx") || matches("xls") || matches("xlsx") ||
                matches("ppt") || matches("pptx") || matches("pages") || matches("numbers") ||
                matches("key") || matches("csv") || matches("json") || matches("xml") ||
                matches("yaml") || matches("yml") { return .documents }
            if matches("jpg") || matches("jpeg") || matches("png") || matches("gif") ||
                matches("heic") || matches("webp") || matches("tif") || matches("tiff") ||
                matches("bmp") || matches("svg") || matches("raw") || matches("dng") { return .images }
            if matches("mp4") || matches("mov") || matches("m4v") || matches("mkv") ||
                matches("avi") || matches("webm") || matches("wmv") || matches("flv") { return .videos }
            if matches("mp3") || matches("m4a") || matches("wav") || matches("flac") ||
                matches("aac") || matches("aiff") || matches("caf") || matches("ogg") { return .audio }
            if matches("zip") || matches("gz") || matches("tgz") || matches("bz2") ||
                matches("xz") || matches("7z") || matches("rar") || matches("tar") ||
                matches("dmg") || matches("iso") || matches("pkg") { return .archives }
            if matches("swift") || matches("h") || matches("m") || matches("mm") ||
                matches("c") || matches("cc") || matches("cpp") || matches("hpp") ||
                matches("rs") || matches("go") || matches("py") || matches("js") ||
                matches("ts") || matches("jsx") || matches("tsx") || matches("java") ||
                matches("kt") || matches("kts") || matches("rb") || matches("php") ||
                matches("sh") || matches("zsh") || matches("fish") || matches("sql") ||
                matches("plist") || matches("xcconfig") || matches("xcodeproj") { return .development }
            return .other
        }
    }
}

public struct DiskContentStatistics: Codable, Sendable, Hashable {
    public let fileCount: UInt64
    /// Logical bytes (st_size) attributed to this content category.
    public let totalBytes: UInt64
    /// Filesystem-reported allocated bytes (st_blocks/ATTR_FILE_ALLOCSIZE).
    public let allocatedBytes: UInt64

    public init(fileCount: UInt64, totalBytes: UInt64, allocatedBytes: UInt64? = nil) {
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.allocatedBytes = allocatedBytes ?? totalBytes
    }

    private enum CodingKeys: String, CodingKey { case fileCount, totalBytes, allocatedBytes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fileCount: try container.decode(UInt64.self, forKey: .fileCount),
            totalBytes: try container.decode(UInt64.self, forKey: .totalBytes),
            allocatedBytes: try container.decodeIfPresent(UInt64.self, forKey: .allocatedBytes)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(allocatedBytes, forKey: .allocatedBytes)
    }
}

public struct DiskNode: Codable, Sendable, Hashable {
    public let path: URL
    public let canonicalPath: URL
    public let sizeBytes: UInt64
    /// Bytes logically attributable to entries that are not retained as child
    /// nodes. This is used to render an explicit "Others" tile without
    /// materializing every file in the tree.
    public let otherBytes: UInt64
    /// Physical bytes reported by the filesystem. It is separate from the
    /// logical size because sparse files and APFS compression can differ.
    public let allocatedSizeBytes: UInt64
    /// Allocated bytes belonging to entries not retained as child nodes.
    public let otherAllocatedSizeBytes: UInt64
    public let fileCount: UInt64
    public let directoryCount: UInt64
    public let lastModified: Date?
    public let isComplete: Bool
    private let isRoot: Bool

    public var parentCanonicalPath: URL? {
        guard !isRoot else { return nil }
        return canonicalPath.deletingLastPathComponent().standardizedFileURL
    }

    public var name: String { path.lastPathComponent }
    public var category: FileCategory { .directory }

    public init(
        path: URL,
        canonicalPath: URL,
        parentCanonicalPath: URL?,
        name: String,
        category: FileCategory,
        sizeBytes: UInt64,
        otherBytes: UInt64 = 0,
        allocatedSizeBytes: UInt64 = 0,
        otherAllocatedSizeBytes: UInt64 = 0,
        fileCount: UInt64,
        directoryCount: UInt64,
        lastModified: Date?,
        isComplete: Bool
    ) {
        let normalizedPath = path.standardizedFileURL
        let normalizedCanonicalPath = canonicalPath.standardizedFileURL
        self.path = normalizedPath
        // Directory symlinks are never recursively traversed. Reusing the
        // normalized path for the overwhelmingly common real-directory case
        // avoids retaining a second equivalent URL/string representation for
        // every Home directory node.
        self.canonicalPath = normalizedPath.path == normalizedCanonicalPath.path ? normalizedPath : normalizedCanonicalPath
        self.sizeBytes = sizeBytes
        self.otherBytes = otherBytes
        self.allocatedSizeBytes = allocatedSizeBytes
        self.otherAllocatedSizeBytes = otherAllocatedSizeBytes
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.lastModified = lastModified
        self.isComplete = isComplete
        self.isRoot = parentCanonicalPath == nil
    }

    private enum CodingKeys: String, CodingKey {
        case path, canonicalPath, parentCanonicalPath, name, category,
             sizeBytes, otherBytes, allocatedSizeBytes, otherAllocatedSizeBytes, fileCount, directoryCount, lastModified, isComplete
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(URL.self, forKey: .path)
        let canonicalPath = try container.decode(URL.self, forKey: .canonicalPath)
        let parent = try container.decodeIfPresent(URL.self, forKey: .parentCanonicalPath)
        self.init(
            path: path,
            canonicalPath: canonicalPath,
            parentCanonicalPath: parent,
            name: (try? container.decode(String.self, forKey: .name)) ?? path.lastPathComponent,
            category: (try? container.decode(FileCategory.self, forKey: .category)) ?? .directory,
            sizeBytes: try container.decode(UInt64.self, forKey: .sizeBytes),
            otherBytes: try container.decodeIfPresent(UInt64.self, forKey: .otherBytes) ?? 0,
            allocatedSizeBytes: try container.decodeIfPresent(UInt64.self, forKey: .allocatedSizeBytes) ?? (try container.decode(UInt64.self, forKey: .sizeBytes)),
            otherAllocatedSizeBytes: try container.decodeIfPresent(UInt64.self, forKey: .otherAllocatedSizeBytes) ?? 0,
            fileCount: try container.decode(UInt64.self, forKey: .fileCount),
            directoryCount: try container.decode(UInt64.self, forKey: .directoryCount),
            lastModified: try container.decodeIfPresent(Date.self, forKey: .lastModified),
            isComplete: try container.decode(Bool.self, forKey: .isComplete)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(canonicalPath, forKey: .canonicalPath)
        try container.encodeIfPresent(parentCanonicalPath, forKey: .parentCanonicalPath)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(otherBytes, forKey: .otherBytes)
        try container.encode(allocatedSizeBytes, forKey: .allocatedSizeBytes)
        try container.encode(otherAllocatedSizeBytes, forKey: .otherAllocatedSizeBytes)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(directoryCount, forKey: .directoryCount)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encode(isComplete, forKey: .isComplete)
    }
}

/// A flat, aggregate-only tree. `nodes` contains directories, not every file.
/// Individual files are represented only in `DiskAnalysisSnapshot.largeFiles`
/// and in the bounded treemap projection.
public struct DiskTree: Codable, Sendable, Hashable {
    public let roots: [DiskNode]
    public let nodes: [DiskNode]
    public let retainedFileNodeCount: UInt64
    public let isComplete: Bool

    public init(roots: [DiskNode], nodes: [DiskNode], retainedFileNodeCount: UInt64, isComplete: Bool) {
        self.roots = roots
        self.nodes = nodes
        self.retainedFileNodeCount = retainedFileNodeCount
        self.isComplete = isComplete
    }
}

/// A flat treemap projection. Consumers can construct rectangles or a visual
/// hierarchy later; Core intentionally contains no layout or UI code.
public struct TreemapNode: Codable, Sendable, Hashable {
    public let id: String
    public let path: URL
    public let parentID: String?
    public let name: String
    public let category: FileCategory
    public let sizeBytes: UInt64
    /// Filesystem-reported allocation used for the default treemap geometry.
    public let allocatedSizeBytes: UInt64
    public let fileCount: UInt64
    public let directoryCount: UInt64
    public let isLargeFile: Bool
    public let isOther: Bool

    public init(
        id: String,
        path: URL,
        parentID: String?,
        name: String,
        category: FileCategory,
        sizeBytes: UInt64,
        allocatedSizeBytes: UInt64? = nil,
        fileCount: UInt64,
        directoryCount: UInt64,
        isLargeFile: Bool,
        isOther: Bool = false
    ) {
        self.id = id
        self.path = path
        self.parentID = parentID
        self.name = name
        self.category = category
        self.sizeBytes = sizeBytes
        self.allocatedSizeBytes = allocatedSizeBytes ?? sizeBytes
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.isLargeFile = isLargeFile
        self.isOther = isOther
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, parentID, name, category, sizeBytes, allocatedSizeBytes,
             fileCount, directoryCount, isLargeFile, isOther
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sizeBytes = try container.decode(UInt64.self, forKey: .sizeBytes)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            path: try container.decode(URL.self, forKey: .path),
            parentID: try container.decodeIfPresent(String.self, forKey: .parentID),
            name: try container.decode(String.self, forKey: .name),
            category: try container.decode(FileCategory.self, forKey: .category),
            sizeBytes: sizeBytes,
            allocatedSizeBytes: try container.decodeIfPresent(UInt64.self, forKey: .allocatedSizeBytes) ?? sizeBytes,
            fileCount: try container.decode(UInt64.self, forKey: .fileCount),
            directoryCount: try container.decode(UInt64.self, forKey: .directoryCount),
            isLargeFile: try container.decode(Bool.self, forKey: .isLargeFile),
            isOther: try container.decodeIfPresent(Bool.self, forKey: .isOther) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(allocatedSizeBytes, forKey: .allocatedSizeBytes)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(directoryCount, forKey: .directoryCount)
        try container.encode(isLargeFile, forKey: .isLargeFile)
        try container.encode(isOther, forKey: .isOther)
    }
}

public struct LargeFileOptions: Codable, Sendable, Hashable {
    public let thresholdBytes: UInt64
    public let topN: Int
    public let minimumAge: TimeInterval?
    public let allowedTypes: Set<FileCategory>
    public let pathPrefix: URL?
    public let minimumSizeBytes: UInt64?
    public let maximumSizeBytes: UInt64?

    public init(
        thresholdBytes: UInt64 = 1_000_000_000,
        topN: Int = 100,
        minimumAge: TimeInterval? = nil,
        allowedTypes: Set<FileCategory> = [.regularFile],
        pathPrefix: URL? = nil,
        minimumSizeBytes: UInt64? = nil,
        maximumSizeBytes: UInt64? = nil
    ) {
        self.thresholdBytes = thresholdBytes
        self.topN = max(0, min(topN, 10_000))
        self.minimumAge = minimumAge.map { max(0, $0) }
        self.allowedTypes = allowedTypes
        self.pathPrefix = pathPrefix?.standardizedFileURL
        self.minimumSizeBytes = minimumSizeBytes
        self.maximumSizeBytes = maximumSizeBytes
    }
}

public struct DiskAnalysisConfiguration: Codable, Sendable, Hashable {
    public let allowedRoots: [URL]
    public let maxConcurrentDirectories: Int
    public let largeFiles: LargeFileOptions
    public let memorySampleStride: UInt64
    public let referenceDate: Date
    /// Explicit analysis-scope filters. Production defaults preserve the
    /// complete read-only scan; benchmark or caller-defined scopes must opt
    /// into exclusions so they cannot silently change normal results.
    public let excludedDirectoryNames: Set<String>
    public let includeSymbolicLinks: Bool
    public let initialDirectoryIdentityCapacity: Int
    public let adaptiveConcurrency: Bool
    /// Disabled by default because collecting phase counters/timers adds
    /// synchronization and clock reads to the scanner hot path. It is used
    /// only for performance audits and never changes scan semantics.
    public let collectPerformanceBreakdown: Bool

    private enum CodingKeys: String, CodingKey {
        case allowedRoots, maxConcurrentDirectories, largeFiles, memorySampleStride,
             referenceDate, excludedDirectoryNames, includeSymbolicLinks,
             initialDirectoryIdentityCapacity, adaptiveConcurrency,
             collectPerformanceBreakdown
    }

    public init(
        allowedRoots: [URL],
        maxConcurrentDirectories: Int = 4,
        largeFiles: LargeFileOptions = LargeFileOptions(),
        memorySampleStride: UInt64 = 256,
        referenceDate: Date = Date(),
        excludedDirectoryNames: Set<String> = [],
        includeSymbolicLinks: Bool = true,
        initialDirectoryIdentityCapacity: Int = 1 << 14,
        adaptiveConcurrency: Bool = false,
        collectPerformanceBreakdown: Bool = false
    ) {
        self.allowedRoots = allowedRoots.map(\.standardizedFileURL)
        self.maxConcurrentDirectories = max(1, min(maxConcurrentDirectories, 64))
        self.largeFiles = largeFiles
        self.memorySampleStride = max(1, memorySampleStride)
        self.referenceDate = referenceDate
        self.excludedDirectoryNames = excludedDirectoryNames
        self.includeSymbolicLinks = includeSymbolicLinks
        self.initialDirectoryIdentityCapacity = max(16, min(initialDirectoryIdentityCapacity, 1 << 20))
        self.adaptiveConcurrency = adaptiveConcurrency
        self.collectPerformanceBreakdown = collectPerformanceBreakdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            allowedRoots: try container.decode([URL].self, forKey: .allowedRoots),
            maxConcurrentDirectories: try container.decodeIfPresent(Int.self, forKey: .maxConcurrentDirectories) ?? 4,
            largeFiles: try container.decodeIfPresent(LargeFileOptions.self, forKey: .largeFiles) ?? LargeFileOptions(),
            memorySampleStride: try container.decodeIfPresent(UInt64.self, forKey: .memorySampleStride) ?? 256,
            referenceDate: try container.decodeIfPresent(Date.self, forKey: .referenceDate) ?? Date(),
            excludedDirectoryNames: try container.decodeIfPresent(Set<String>.self, forKey: .excludedDirectoryNames) ?? [],
            includeSymbolicLinks: try container.decodeIfPresent(Bool.self, forKey: .includeSymbolicLinks) ?? true,
            initialDirectoryIdentityCapacity: try container.decodeIfPresent(Int.self, forKey: .initialDirectoryIdentityCapacity) ?? (1 << 14),
            adaptiveConcurrency: try container.decodeIfPresent(Bool.self, forKey: .adaptiveConcurrency) ?? false,
            collectPerformanceBreakdown: try container.decodeIfPresent(Bool.self, forKey: .collectPerformanceBreakdown) ?? false
        )
    }
}

public struct DiskAnalysisTarget: Codable, Sendable, Hashable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public enum DiskAllocationStatus: String, Codable, Sendable, Hashable {
    case filesystemReported
    /// The filesystem-reported allocation is available, but shared APFS
    /// extents (for example clones) cannot be attributed uniquely by this
    /// public read-only scan.
    case filesystemReportedSharedExtentsUnknown
    /// The reported allocation exceeded the volume capacity and was bounded
    /// fail-safe for presentation.
    case volumeBounded
    case unavailable
}

public struct LargeFileEntry: Codable, Sendable, Hashable {
    public let path: URL
    public let canonicalPath: URL
    public let sizeBytes: UInt64
    public let allocatedSizeBytes: UInt64
    public let lastModified: Date?
    public let fileType: FileCategory
    public let age: TimeInterval?

    public init(path: URL, canonicalPath: URL, sizeBytes: UInt64, allocatedSizeBytes: UInt64? = nil, lastModified: Date?, fileType: FileCategory, age: TimeInterval?) {
        self.path = path
        self.canonicalPath = canonicalPath
        self.sizeBytes = sizeBytes
        self.allocatedSizeBytes = allocatedSizeBytes ?? sizeBytes
        self.lastModified = lastModified
        self.fileType = fileType
        self.age = age
    }

    private enum CodingKeys: String, CodingKey { case path, canonicalPath, sizeBytes, allocatedSizeBytes, lastModified, fileType, age }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sizeBytes = try container.decode(UInt64.self, forKey: .sizeBytes)
        self.init(
            path: try container.decode(URL.self, forKey: .path),
            canonicalPath: try container.decode(URL.self, forKey: .canonicalPath),
            sizeBytes: sizeBytes,
            allocatedSizeBytes: try container.decodeIfPresent(UInt64.self, forKey: .allocatedSizeBytes) ?? sizeBytes,
            lastModified: try container.decodeIfPresent(Date.self, forKey: .lastModified),
            fileType: try container.decode(FileCategory.self, forKey: .fileType),
            age: try container.decodeIfPresent(TimeInterval.self, forKey: .age)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(canonicalPath, forKey: .canonicalPath)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(allocatedSizeBytes, forKey: .allocatedSizeBytes)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encode(fileType, forKey: .fileType)
        try container.encodeIfPresent(age, forKey: .age)
    }
}

public enum DiskAnalysisIssueKind: String, Codable, Sendable, Hashable {
    case invalidTarget
    case notFound
    case notDirectory
    case permissionDenied
    case enumerationFailed
    case metadataUnavailable
    case symlinkSkipped
    case symlinkEscape
    case symlinkUnresolved
    case canonicalDuplicate
    case protectedPath
    case volumeBoundary
    case cancelled
}

public struct DiskAnalysisIssue: Codable, Sendable, Hashable {
    public let kind: DiskAnalysisIssueKind
    public let path: URL
    public let detail: String

    public init(kind: DiskAnalysisIssueKind, path: URL, detail: String) {
        self.kind = kind
        self.path = path
        self.detail = detail
    }
}

public struct DiskMemorySample: Codable, Sendable, Hashable {
    public let elapsed: TimeInterval
    public let residentMemoryBytes: UInt64

    public init(elapsed: TimeInterval, residentMemoryBytes: UInt64) {
        self.elapsed = elapsed
        self.residentMemoryBytes = residentMemoryBytes
    }
}

/// Optional audit-only counters for explaining Full-quality scan cost. The
/// counters are absent from normal scans so production performance is not
/// changed by profiling support.
public struct DiskAnalysisBreakdown: Codable, Sendable, Hashable {
    public let metadataCalls: UInt64
    public let metadataEntries: UInt64
    public let metadataNanoseconds: UInt64
    public let symlinkEntries: UInt64
    public let symlinkNanoseconds: UInt64
    public let volumeChecks: UInt64
    public let volumeBoundaryEntries: UInt64
    public let volumeNanoseconds: UInt64
    public let permissionChecks: UInt64
    public let permissionFailures: UInt64
    public let identityChecks: UInt64
    public let identityNanoseconds: UInt64
    public let hardLinkCandidates: UInt64
    public let hardLinkDuplicates: UInt64
    public let hardLinkNanoseconds: UInt64
    public let watchdogOpens: UInt64
    public let watchdogTimeouts: UInt64
    public let watchdogNanoseconds: UInt64
    public let aggregationRecords: UInt64
    public let aggregationNanoseconds: UInt64
    /// Allocation-sensitive counters for the bounded large-file projection.
    /// These are not a substitute for Instruments' total malloc count; they
    /// identify avoidable `LargeFileEntry` materialization in the scan path.
    public let largeFileCandidates: UInt64
    public let largeFileEntriesMaterialized: UInt64
    public let largeFileCandidatesRejectedBeforeMaterialization: UInt64

    public init(
        metadataCalls: UInt64 = 0,
        metadataEntries: UInt64 = 0,
        metadataNanoseconds: UInt64 = 0,
        symlinkEntries: UInt64 = 0,
        symlinkNanoseconds: UInt64 = 0,
        volumeChecks: UInt64 = 0,
        volumeBoundaryEntries: UInt64 = 0,
        volumeNanoseconds: UInt64 = 0,
        permissionChecks: UInt64 = 0,
        permissionFailures: UInt64 = 0,
        identityChecks: UInt64 = 0,
        identityNanoseconds: UInt64 = 0,
        hardLinkCandidates: UInt64 = 0,
        hardLinkDuplicates: UInt64 = 0,
        hardLinkNanoseconds: UInt64 = 0,
        watchdogOpens: UInt64 = 0,
        watchdogTimeouts: UInt64 = 0,
        watchdogNanoseconds: UInt64 = 0,
        aggregationRecords: UInt64 = 0,
        aggregationNanoseconds: UInt64 = 0,
        largeFileCandidates: UInt64 = 0,
        largeFileEntriesMaterialized: UInt64 = 0,
        largeFileCandidatesRejectedBeforeMaterialization: UInt64 = 0
    ) {
        self.metadataCalls = metadataCalls
        self.metadataEntries = metadataEntries
        self.metadataNanoseconds = metadataNanoseconds
        self.symlinkEntries = symlinkEntries
        self.symlinkNanoseconds = symlinkNanoseconds
        self.volumeChecks = volumeChecks
        self.volumeBoundaryEntries = volumeBoundaryEntries
        self.volumeNanoseconds = volumeNanoseconds
        self.permissionChecks = permissionChecks
        self.permissionFailures = permissionFailures
        self.identityChecks = identityChecks
        self.identityNanoseconds = identityNanoseconds
        self.hardLinkCandidates = hardLinkCandidates
        self.hardLinkDuplicates = hardLinkDuplicates
        self.hardLinkNanoseconds = hardLinkNanoseconds
        self.watchdogOpens = watchdogOpens
        self.watchdogTimeouts = watchdogTimeouts
        self.watchdogNanoseconds = watchdogNanoseconds
        self.aggregationRecords = aggregationRecords
        self.aggregationNanoseconds = aggregationNanoseconds
        self.largeFileCandidates = largeFileCandidates
        self.largeFileEntriesMaterialized = largeFileEntriesMaterialized
        self.largeFileCandidatesRejectedBeforeMaterialization = largeFileCandidatesRejectedBeforeMaterialization
    }

    private enum CodingKeys: String, CodingKey {
        case metadataCalls, metadataEntries, metadataNanoseconds
        case symlinkEntries, symlinkNanoseconds
        case volumeChecks, volumeBoundaryEntries, volumeNanoseconds
        case permissionChecks, permissionFailures
        case identityChecks, identityNanoseconds
        case hardLinkCandidates, hardLinkDuplicates, hardLinkNanoseconds
        case watchdogOpens, watchdogTimeouts, watchdogNanoseconds
        case aggregationRecords, aggregationNanoseconds
        case largeFileCandidates, largeFileEntriesMaterialized
        case largeFileCandidatesRejectedBeforeMaterialization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            metadataCalls: try container.decodeIfPresent(UInt64.self, forKey: .metadataCalls) ?? 0,
            metadataEntries: try container.decodeIfPresent(UInt64.self, forKey: .metadataEntries) ?? 0,
            metadataNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .metadataNanoseconds) ?? 0,
            symlinkEntries: try container.decodeIfPresent(UInt64.self, forKey: .symlinkEntries) ?? 0,
            symlinkNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .symlinkNanoseconds) ?? 0,
            volumeChecks: try container.decodeIfPresent(UInt64.self, forKey: .volumeChecks) ?? 0,
            volumeBoundaryEntries: try container.decodeIfPresent(UInt64.self, forKey: .volumeBoundaryEntries) ?? 0,
            volumeNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .volumeNanoseconds) ?? 0,
            permissionChecks: try container.decodeIfPresent(UInt64.self, forKey: .permissionChecks) ?? 0,
            permissionFailures: try container.decodeIfPresent(UInt64.self, forKey: .permissionFailures) ?? 0,
            identityChecks: try container.decodeIfPresent(UInt64.self, forKey: .identityChecks) ?? 0,
            identityNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .identityNanoseconds) ?? 0,
            hardLinkCandidates: try container.decodeIfPresent(UInt64.self, forKey: .hardLinkCandidates) ?? 0,
            hardLinkDuplicates: try container.decodeIfPresent(UInt64.self, forKey: .hardLinkDuplicates) ?? 0,
            hardLinkNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .hardLinkNanoseconds) ?? 0,
            watchdogOpens: try container.decodeIfPresent(UInt64.self, forKey: .watchdogOpens) ?? 0,
            watchdogTimeouts: try container.decodeIfPresent(UInt64.self, forKey: .watchdogTimeouts) ?? 0,
            watchdogNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .watchdogNanoseconds) ?? 0,
            aggregationRecords: try container.decodeIfPresent(UInt64.self, forKey: .aggregationRecords) ?? 0,
            aggregationNanoseconds: try container.decodeIfPresent(UInt64.self, forKey: .aggregationNanoseconds) ?? 0,
            largeFileCandidates: try container.decodeIfPresent(UInt64.self, forKey: .largeFileCandidates) ?? 0,
            largeFileEntriesMaterialized: try container.decodeIfPresent(UInt64.self, forKey: .largeFileEntriesMaterialized) ?? 0,
            largeFileCandidatesRejectedBeforeMaterialization: try container.decodeIfPresent(UInt64.self, forKey: .largeFileCandidatesRejectedBeforeMaterialization) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadataCalls, forKey: .metadataCalls)
        try container.encode(metadataEntries, forKey: .metadataEntries)
        try container.encode(metadataNanoseconds, forKey: .metadataNanoseconds)
        try container.encode(symlinkEntries, forKey: .symlinkEntries)
        try container.encode(symlinkNanoseconds, forKey: .symlinkNanoseconds)
        try container.encode(volumeChecks, forKey: .volumeChecks)
        try container.encode(volumeBoundaryEntries, forKey: .volumeBoundaryEntries)
        try container.encode(volumeNanoseconds, forKey: .volumeNanoseconds)
        try container.encode(permissionChecks, forKey: .permissionChecks)
        try container.encode(permissionFailures, forKey: .permissionFailures)
        try container.encode(identityChecks, forKey: .identityChecks)
        try container.encode(identityNanoseconds, forKey: .identityNanoseconds)
        try container.encode(hardLinkCandidates, forKey: .hardLinkCandidates)
        try container.encode(hardLinkDuplicates, forKey: .hardLinkDuplicates)
        try container.encode(hardLinkNanoseconds, forKey: .hardLinkNanoseconds)
        try container.encode(watchdogOpens, forKey: .watchdogOpens)
        try container.encode(watchdogTimeouts, forKey: .watchdogTimeouts)
        try container.encode(watchdogNanoseconds, forKey: .watchdogNanoseconds)
        try container.encode(aggregationRecords, forKey: .aggregationRecords)
        try container.encode(aggregationNanoseconds, forKey: .aggregationNanoseconds)
        try container.encode(largeFileCandidates, forKey: .largeFileCandidates)
        try container.encode(largeFileEntriesMaterialized, forKey: .largeFileEntriesMaterialized)
        try container.encode(largeFileCandidatesRejectedBeforeMaterialization, forKey: .largeFileCandidatesRejectedBeforeMaterialization)
    }
}

public struct DiskAnalysisPerformance: Codable, Sendable, Hashable {
    public let duration: TimeInterval
    public let cpuTimeSeconds: TimeInterval
    public let averageCPUPercent: Double
    public let peakResidentMemoryBytes: UInt64
    public let memorySamples: [DiskMemorySample]
    public let throughputFilesPerSecond: Double
    public let maxObservedConcurrentDirectories: Int
    public let maxDirectoryEntriesBuffered: Int
    public let cancellationLatency: TimeInterval?
    public let breakdown: DiskAnalysisBreakdown?

    public init(
        duration: TimeInterval,
        cpuTimeSeconds: TimeInterval,
        averageCPUPercent: Double,
        peakResidentMemoryBytes: UInt64,
        memorySamples: [DiskMemorySample],
        throughputFilesPerSecond: Double,
        maxObservedConcurrentDirectories: Int,
        maxDirectoryEntriesBuffered: Int,
        cancellationLatency: TimeInterval?,
        breakdown: DiskAnalysisBreakdown? = nil
    ) {
        self.duration = duration
        self.cpuTimeSeconds = cpuTimeSeconds
        self.averageCPUPercent = averageCPUPercent
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.memorySamples = memorySamples
        self.throughputFilesPerSecond = throughputFilesPerSecond
        self.maxObservedConcurrentDirectories = maxObservedConcurrentDirectories
        self.maxDirectoryEntriesBuffered = maxDirectoryEntriesBuffered
        self.cancellationLatency = cancellationLatency
        self.breakdown = breakdown
    }
}

public struct DiskAnalysisSnapshot: Codable, Sendable, Hashable {
    public let startedAt: Date
    public let finishedAt: Date
    public let cancelled: Bool
    public let visitedPathCount: UInt64
    public let fileCount: UInt64
    public let directoryCount: UInt64
    public let totalBytes: UInt64
    /// Logical bytes counted once per device/inode identity.
    public let allocatedBytes: UInt64
    public let volumeCapacityBytes: UInt64?
    public let allocationStatus: DiskAllocationStatus
    public let tree: DiskTree
    public let largeFiles: [LargeFileEntry]
    public let contentStatistics: [DiskContentCategory: DiskContentStatistics]
    public let issues: [DiskAnalysisIssue]
    /// To keep a Home scan bounded, only the first issue samples are retained;
    /// this count preserves the fact that additional issues existed.
    public let suppressedIssueCount: UInt64
    public let performance: DiskAnalysisPerformance

    /// A derived projection. Directory nodes and the bounded large-file list
    /// already contain all information needed to render the treemap, so the
    /// completed snapshot does not retain a second full array of equivalent
    /// nodes. This is important for large Home scans.
    public var treemapNodes: [TreemapNode] {
        var result = tree.nodes.map { node in
            TreemapNode(
                id: node.canonicalPath.path,
                path: node.path,
                parentID: node.parentCanonicalPath?.path,
                name: node.name,
                category: .directory,
                sizeBytes: node.sizeBytes,
                allocatedSizeBytes: node.allocatedSizeBytes,
                fileCount: node.fileCount,
                directoryCount: node.directoryCount,
                isLargeFile: false
            )
        }
        result.append(contentsOf: tree.nodes.compactMap { node in
            guard node.otherBytes > 0 else { return nil }
            return TreemapNode(
                id: "other:\(node.canonicalPath.path)",
                path: node.path,
                parentID: node.canonicalPath.path,
                name: "Other",
                category: .other,
                sizeBytes: node.otherBytes,
                allocatedSizeBytes: node.otherAllocatedSizeBytes,
                fileCount: 0,
                directoryCount: 0,
                isLargeFile: false,
                isOther: true
            )
        })
        result.append(contentsOf: largeFiles.map { entry in
            TreemapNode(
                id: "file:\(entry.canonicalPath.path)",
                path: entry.path,
                parentID: entry.canonicalPath.deletingLastPathComponent().standardizedFileURL.path,
                name: entry.path.lastPathComponent,
                category: entry.fileType,
                sizeBytes: entry.sizeBytes,
                allocatedSizeBytes: entry.allocatedSizeBytes,
                fileCount: 1,
                directoryCount: 0,
                isLargeFile: true
            )
        })
        return result
    }

    /// Produces only one visible treemap layer. This avoids materializing the
    /// complete directory projection when a caller only needs children of one
    /// directory, such as the SwiftUI drill-in view.
    public func treemapNodes(forParentPath parent: URL) -> [TreemapNode] {
        let canonicalParent = parent.standardizedFileURL.path
        var result: [TreemapNode] = []
        result.reserveCapacity(64)

        for node in tree.nodes where node.parentCanonicalPath?.path == canonicalParent {
            result.append(TreemapNode(
                id: node.canonicalPath.path,
                path: node.path,
                parentID: node.parentCanonicalPath?.path,
                name: node.name,
                category: .directory,
                sizeBytes: node.sizeBytes,
                allocatedSizeBytes: node.allocatedSizeBytes,
                fileCount: node.fileCount,
                directoryCount: node.directoryCount,
                isLargeFile: false
            ))
        }
        if let parentNode = tree.nodes.first(where: { $0.canonicalPath.path == canonicalParent }),
           parentNode.otherBytes > 0 {
            result.append(TreemapNode(
                id: "other:\(parentNode.canonicalPath.path)",
                path: parentNode.path,
                parentID: parentNode.canonicalPath.path,
                name: "Other",
                category: .other,
                sizeBytes: parentNode.otherBytes,
                allocatedSizeBytes: parentNode.otherAllocatedSizeBytes,
                fileCount: 0,
                directoryCount: 0,
                isLargeFile: false,
                isOther: true
            ))
        }
        for entry in largeFiles where entry.canonicalPath.deletingLastPathComponent().standardizedFileURL.path == canonicalParent {
            result.append(TreemapNode(
                id: "file:\(entry.canonicalPath.path)",
                path: entry.path,
                parentID: canonicalParent,
                name: entry.path.lastPathComponent,
                category: entry.fileType,
                sizeBytes: entry.sizeBytes,
                allocatedSizeBytes: entry.allocatedSizeBytes,
                fileCount: 1,
                directoryCount: 0,
                isLargeFile: true
            ))
        }
        return result
    }

    public init(
        startedAt: Date,
        finishedAt: Date,
        cancelled: Bool,
        visitedPathCount: UInt64,
        fileCount: UInt64,
        directoryCount: UInt64,
        totalBytes: UInt64,
        allocatedBytes: UInt64 = 0,
        volumeCapacityBytes: UInt64? = nil,
        allocationStatus: DiskAllocationStatus = .unavailable,
        tree: DiskTree,
        treemapNodes: [TreemapNode],
        largeFiles: [LargeFileEntry],
        contentStatistics: [DiskContentCategory: DiskContentStatistics] = [:],
        issues: [DiskAnalysisIssue],
        suppressedIssueCount: UInt64 = 0,
        performance: DiskAnalysisPerformance
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.cancelled = cancelled
        self.visitedPathCount = visitedPathCount
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalBytes = totalBytes
        self.allocatedBytes = allocatedBytes
        self.volumeCapacityBytes = volumeCapacityBytes
        self.allocationStatus = allocationStatus
        self.tree = tree
        self.largeFiles = largeFiles
        self.contentStatistics = contentStatistics
        self.issues = issues
        self.suppressedIssueCount = suppressedIssueCount
        self.performance = performance
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt, finishedAt, cancelled, visitedPathCount, fileCount,
             directoryCount, totalBytes, allocatedBytes, tree, treemapNodes, largeFiles,
             volumeCapacityBytes, allocationStatus, contentStatistics, issues, suppressedIssueCount, performance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        cancelled = try container.decode(Bool.self, forKey: .cancelled)
        visitedPathCount = try container.decode(UInt64.self, forKey: .visitedPathCount)
        fileCount = try container.decode(UInt64.self, forKey: .fileCount)
        directoryCount = try container.decode(UInt64.self, forKey: .directoryCount)
        totalBytes = try container.decode(UInt64.self, forKey: .totalBytes)
        allocatedBytes = try container.decodeIfPresent(UInt64.self, forKey: .allocatedBytes) ?? totalBytes
        volumeCapacityBytes = try container.decodeIfPresent(UInt64.self, forKey: .volumeCapacityBytes)
        allocationStatus = try container.decodeIfPresent(DiskAllocationStatus.self, forKey: .allocationStatus) ?? .unavailable
        tree = try container.decode(DiskTree.self, forKey: .tree)
        // Decode for backward compatibility, but intentionally do not retain
        // the redundant projection. It is derived from tree + largeFiles.
        _ = try container.decodeIfPresent([TreemapNode].self, forKey: .treemapNodes)
        largeFiles = try container.decode([LargeFileEntry].self, forKey: .largeFiles)
        contentStatistics = try container.decodeIfPresent([DiskContentCategory: DiskContentStatistics].self, forKey: .contentStatistics) ?? [:]
        issues = try container.decode([DiskAnalysisIssue].self, forKey: .issues)
        suppressedIssueCount = try container.decodeIfPresent(UInt64.self, forKey: .suppressedIssueCount) ?? 0
        performance = try container.decode(DiskAnalysisPerformance.self, forKey: .performance)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(finishedAt, forKey: .finishedAt)
        try container.encode(cancelled, forKey: .cancelled)
        try container.encode(visitedPathCount, forKey: .visitedPathCount)
        try container.encode(fileCount, forKey: .fileCount)
        try container.encode(directoryCount, forKey: .directoryCount)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(allocatedBytes, forKey: .allocatedBytes)
        try container.encodeIfPresent(volumeCapacityBytes, forKey: .volumeCapacityBytes)
        try container.encode(allocationStatus, forKey: .allocationStatus)
        try container.encode(tree, forKey: .tree)
        // Preserve the existing serialized shape for external consumers. The
        // array is created only during encoding and is not retained in memory.
        try container.encode(treemapNodes, forKey: .treemapNodes)
        try container.encode(largeFiles, forKey: .largeFiles)
        try container.encode(contentStatistics, forKey: .contentStatistics)
        try container.encode(issues, forKey: .issues)
        try container.encode(suppressedIssueCount, forKey: .suppressedIssueCount)
        try container.encode(performance, forKey: .performance)
    }
}

public enum DiskAnalysisUpdateKind: String, Codable, Sendable, Hashable {
    case progress
    case directoryCompleted
    case largeFileFound
    case issue
    case completed
}

/// Progress is intentionally split into a compact, immediately renderable
/// inventory projection and the final authoritative enrichment result. Both
/// stages come from the same getattrlistbulk traversal; this is not a second
/// scan and therefore cannot silently use a smaller root or file scope.
public enum DiskAnalysisStage: String, Codable, Sendable, Hashable {
    case fastInventory
    case deepEnrichment
}

public struct DiskAnalysisUpdate: Sendable {
    public let kind: DiskAnalysisUpdateKind
    public let stage: DiskAnalysisStage
    public let path: URL?
    public let node: DiskNode?
    public let largeFile: LargeFileEntry?
    public let issue: DiskAnalysisIssue?
    public let visitedPathCount: UInt64
    public let fileCount: UInt64
    public let directoryCount: UInt64
    public let totalBytes: UInt64
    public let allocatedBytes: UInt64
    public let snapshot: DiskAnalysisSnapshot?

    public init(
        kind: DiskAnalysisUpdateKind,
        path: URL?,
        node: DiskNode? = nil,
        largeFile: LargeFileEntry? = nil,
        issue: DiskAnalysisIssue? = nil,
        visitedPathCount: UInt64,
        fileCount: UInt64,
        directoryCount: UInt64,
        totalBytes: UInt64,
        allocatedBytes: UInt64 = 0,
        snapshot: DiskAnalysisSnapshot? = nil,
        stage: DiskAnalysisStage? = nil
    ) {
        self.kind = kind
        self.stage = stage ?? ((kind == .completed || kind == .issue) ? .deepEnrichment : .fastInventory)
        self.path = path
        self.node = node
        self.largeFile = largeFile
        self.issue = issue
        self.visitedPathCount = visitedPathCount
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalBytes = totalBytes
        self.allocatedBytes = allocatedBytes
        self.snapshot = snapshot
    }
}

public actor DiskAnalysisEngine {
    private let maxConcurrentDirectories: Int
    private let directoryOpenHandler: DiskDirectoryOpenHandler

    public init(maxConcurrentDirectories: Int = 4) {
        self.init(
            maxConcurrentDirectories: maxConcurrentDirectories,
            directoryOpenHandler: productionDirectoryOpenHandler
        )
    }

    /// Internal test seam. Production callers always use the initializer above,
    /// which invokes real POSIX open through the shared watchdog.
    init(
        maxConcurrentDirectories: Int = 4,
        directoryOpenHandler: @escaping DiskDirectoryOpenHandler
    ) {
        self.maxConcurrentDirectories = max(1, min(maxConcurrentDirectories, 64))
        self.directoryOpenHandler = directoryOpenHandler
    }

    public func analyze(
        targets: [DiskAnalysisTarget],
        configuration: DiskAnalysisConfiguration,
        progress: (@Sendable (DiskAnalysisUpdate) async -> Void)? = nil
    ) async -> DiskAnalysisSnapshot {
        let startedAt = Date()
        let accumulator = DiskAnalysisAccumulator(startedAt: startedAt, configuration: configuration)
        let queue = DiskDirectoryQueue(initialIdentityCapacity: configuration.initialDirectoryIdentityCapacity)
        let allowedRoots = await Self.canonicalAllowedRoots(configuration.allowedRoots, accumulator: accumulator)
        var initialItems: [DiskWorkItem] = []
        var initialCanonicalPaths: Set<String> = []

        for target in targets {
            guard !Task.isCancelled else { break }
            guard let item = await Self.makeInitialWorkItem(
                target: target,
                allowedRoots: allowedRoots,
                accumulator: accumulator
            ) else { continue }
            if initialCanonicalPaths.insert(item.canonicalPath.path).inserted {
                initialItems.append(item)
            } else {
                accumulator.recordIssue(DiskAnalysisIssue(
                    kind: .canonicalDuplicate,
                    path: item.url,
                    detail: "Canonical target was already scheduled."
                ))
            }
        }

        let volumeContext = initialItems.first.flatMap { diskVolumeContext(at: $0.canonicalPath, device: $0.metadata.identity?.device) }
        accumulator.configureVolume(volumeContext)
        let scanVolumeDevice = volumeContext?.device
        if let scanVolumeDevice {
            let crossVolumeItems = initialItems.filter { $0.metadata.identity?.device != scanVolumeDevice }
            for item in crossVolumeItems {
                accumulator.recordIssue(DiskAnalysisIssue(kind: .volumeBoundary, path: item.url, detail: "Target is on a different volume and was excluded by the default volume boundary."))
            }
            initialItems.removeAll { $0.metadata.identity?.device != scanVolumeDevice }
        }
        let initialDuplicates = await queue.enqueue(initialItems)
        for duplicate in initialDuplicates {
            accumulator.recordIssue(DiskAnalysisIssue(kind: .canonicalDuplicate, path: duplicate, detail: "Canonical directory was already scheduled."))
        }
        let configuredWorkerLimit = min(maxConcurrentDirectories, configuration.maxConcurrentDirectories)
        let workerLimit = configuration.adaptiveConcurrency
            ? Self.adaptiveWorkerLimit(configuredLimit: configuredWorkerLimit)
            : configuredWorkerLimit
        let directoryOpenHandler = self.directoryOpenHandler
        if !initialItems.isEmpty && !Task.isCancelled {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<workerLimit {
                    group.addTask {
                        await Self.worker(
                            queue: queue,
                            accumulator: accumulator,
                            allowedRoots: allowedRoots,
                            scanVolumeDevice: scanVolumeDevice,
                            configuration: configuration,
                            progress: progress,
                            directoryOpenHandler: directoryOpenHandler
                        )
                    }
                }
            }
        }

        let taskCancelled = Task.isCancelled
        let queueCancelled = await queue.wasCancelled()
        // The queue's canonical de-duplication set is only needed while work
        // is being scheduled. Release its potentially large path set before
        // building the result so the UI process does not retain scan-control
        // state after completion.
        await queue.releaseTransientState()
        let cancelled = taskCancelled || queueCancelled
        if cancelled {
            accumulator.markCancelled()
        }
        let finishedAt = Date()
        let snapshot = accumulator.makeSnapshot(
            finishedAt: finishedAt,
            cancelled: cancelled,
            maxObservedConcurrency: await queue.maxObservedConcurrency()
        )
        if let progress {
            await progress(DiskAnalysisUpdate(
                kind: .completed,
                path: nil,
                visitedPathCount: snapshot.visitedPathCount,
                fileCount: snapshot.fileCount,
                    directoryCount: snapshot.directoryCount,
                    totalBytes: snapshot.totalBytes,
                    allocatedBytes: snapshot.allocatedBytes,
                    snapshot: snapshot
            ))
        }
        return snapshot
    }

    private static func adaptiveWorkerLimit(configuredLimit: Int) -> Int {
        // Keep adaptive fan-out bounded. The configured limit still caps this
        // value, so callers can explicitly select a lower count for sensitive
        // volumes; this is never unbounded concurrency.
        let hardwareLimit = max(1, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))
        return min(configuredLimit, hardwareLimit)
    }

    private static func canonicalAllowedRoots(_ roots: [URL], accumulator: DiskAnalysisAccumulator) async -> [URL] {
        var result: [URL] = []
        for root in roots {
            let normalized = root.standardizedFileURL
            guard normalized.path.hasPrefix("/"), let canonical = canonicalURL(normalized) else {
                accumulator.recordIssue(DiskAnalysisIssue(kind: .protectedPath, path: normalized, detail: "Allowed root is not an existing absolute path."))
                continue
            }
            if !result.contains(where: { pathIsWithin(canonical, root: $0) }) {
                result.append(canonical)
            }
        }
        return result
    }

    private static func makeInitialWorkItem(
        target: DiskAnalysisTarget,
        allowedRoots: [URL],
        accumulator: DiskAnalysisAccumulator
    ) async -> DiskWorkItem? {
        let normalized = target.url.standardizedFileURL
        guard normalized.path.hasPrefix("/") else {
            accumulator.recordIssue(DiskAnalysisIssue(kind: .invalidTarget, path: normalized, detail: "Only absolute paths are accepted."))
            return nil
        }
        guard let metadata = readDiskMetadata(at: normalized) else {
            accumulator.recordIssue(DiskAnalysisIssue(kind: .notFound, path: normalized, detail: "Target does not exist or cannot be inspected."))
            return nil
        }
        guard metadata.category == .directory else {
            accumulator.recordIssue(DiskAnalysisIssue(kind: .notDirectory, path: normalized, detail: "Analysis targets must be directories."))
            return nil
        }
        guard let canonical = canonicalURL(normalized) else {
            accumulator.recordIssue(DiskAnalysisIssue(kind: .metadataUnavailable, path: normalized, detail: "Target canonicalization failed."))
            return nil
        }
        guard allowedRoots.contains(where: { pathIsWithin(canonical, root: $0) }) else {
            accumulator.recordIssue(DiskAnalysisIssue(kind: .protectedPath, path: normalized, detail: "Target is outside the configured allowed roots."))
            return nil
        }
        return DiskWorkItem(
            url: normalized,
            canonicalPath: canonical,
            parentCanonicalPath: nil,
            scanRootPath: canonical,
            visibleAggregatePath: canonical,
            depth: pathDepth(canonical),
            metadata: metadata
        )
    }

    private static func worker(
        queue: DiskDirectoryQueue,
        accumulator: DiskAnalysisAccumulator,
        allowedRoots: [URL],
        scanVolumeDevice: UInt64?,
        configuration: DiskAnalysisConfiguration,
        progress: (@Sendable (DiskAnalysisUpdate) async -> Void)?,
        directoryOpenHandler: @escaping DiskDirectoryOpenHandler
    ) async {
        // Keep one parser buffer per bounded worker instead of allocating a
        // new buffer for every directory. The buffer is never shared
        // between workers and is not retained in the result snapshot.
        let bulkBuffer = BulkDirectoryBuffer()
        while !Task.isCancelled {
            guard let work = await queue.next() else { return }
            accumulator.recordDirectory(work)
            let entries = await enumerateDirectory(
                work: work,
                queue: queue,
                accumulator: accumulator,
                allowedRoots: allowedRoots,
                scanVolumeDevice: scanVolumeDevice,
                configuration: configuration,
                progress: progress,
                bulkBuffer: bulkBuffer,
                directoryOpenHandler: directoryOpenHandler
            )
            let duplicates = await queue.enqueue(entries)
            for duplicate in duplicates {
                accumulator.recordIssue(DiskAnalysisIssue(kind: .canonicalDuplicate, path: duplicate, detail: "Canonical directory was already scheduled or scanned."))
            }
            let completedNode = accumulator.completeDirectory(work)
            await queue.complete()
            if let completedNode, let progress {
                let counts = accumulator.counts()
                await progress(DiskAnalysisUpdate(
                    kind: .directoryCompleted,
                    path: completedNode.path,
                    node: completedNode,
                    visitedPathCount: counts.visited,
                    fileCount: counts.files,
                    directoryCount: counts.directories,
                    totalBytes: counts.bytes,
                    allocatedBytes: counts.allocated
                ))
            }
        }
        if Task.isCancelled {
            await queue.cancel()
            accumulator.markCancellationObserved()
        }
    }

    private static func enumerateDirectory(
        work: DiskWorkItem,
        queue: DiskDirectoryQueue,
        accumulator: DiskAnalysisAccumulator,
        allowedRoots: [URL],
        scanVolumeDevice: UInt64?,
        configuration: DiskAnalysisConfiguration,
        progress: (@Sendable (DiskAnalysisUpdate) async -> Void)?,
        bulkBuffer: BulkDirectoryBuffer,
        directoryOpenHandler: @escaping DiskDirectoryOpenHandler
    ) async -> [DiskWorkItem] {
        guard !Task.isCancelled else { return [] }
        let canonicalWorkPath = work.canonicalPath.path
        let aggregateKey = work.visibleAggregatePath.path
        let scanRootKey = work.scanRootPath.path
        // A mode-000 directory can be reported as an empty enumeration by some
        // FileManager/macOS combinations. Fail closed before calling it so the
        // permission boundary remains observable and no empty result is treated
        // as a successful scan.
        let permissionDenied = work.metadata.posixMode & 0o400 == 0 || work.metadata.posixMode & 0o100 == 0
        accumulator.recordPermissionCheck(failed: permissionDenied)
        if permissionDenied {
            let issue = DiskAnalysisIssue(kind: .permissionDenied, path: work.url, detail: "Directory does not expose read and search permission bits.")
            accumulator.recordIssue(issue)
            if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
            return []
        }
        // Open the canonical path, never the user-facing path that may still
        // contain a symlink component. O_NOFOLLOW also fails closed if the
        // final component changes between getattrlistbulk and open.
        let watchdogStartedAt = configuration.collectPerformanceBreakdown ? DispatchTime.now().uptimeNanoseconds : 0
        let openResult = await openDirectoryWithTimeout(
            path: canonicalWorkPath,
            opener: directoryOpenHandler
        )
        if configuration.collectPerformanceBreakdown {
            accumulator.recordWatchdog(
                timeout: {
                    if case .timedOut = openResult { return true }
                    return false
                }(),
                nanoseconds: DispatchTime.now().uptimeNanoseconds &- watchdogStartedAt
            )
        }
        let directoryFD: Int32
        switch openResult {
        case .opened(let fd):
            directoryFD = fd
        case .failed(let error):
            let issue = DiskAnalysisIssue(kind: isPermissionErrno(error) ? .permissionDenied : .enumerationFailed, path: work.url, detail: "open directory failed: errno \(error).")
            accumulator.recordIssue(issue)
            if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
            return []
        case .timedOut:
            let issue = DiskAnalysisIssue(kind: .enumerationFailed, path: work.url, detail: "Directory open exceeded the watchdog timeout and was skipped.")
            accumulator.recordIssue(issue)
            if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
            return []
        }
        let ownsDirectoryFD = true
        defer { if ownsDirectoryFD { close(directoryFD) } }
        if let expectedIdentity = work.metadata.identity {
            let identityStartedAt = configuration.collectPerformanceBreakdown ? DispatchTime.now().uptimeNanoseconds : 0
            let identityMatches = directoryIdentityMatches(fd: directoryFD, expected: expectedIdentity)
            if configuration.collectPerformanceBreakdown {
                accumulator.recordIdentityCheck(nanoseconds: DispatchTime.now().uptimeNanoseconds &- identityStartedAt)
            }
            if !identityMatches {
                let issue = DiskAnalysisIssue(kind: .enumerationFailed, path: work.url, detail: "Directory identity changed before enumeration; directory skipped.")
                accumulator.recordIssue(issue)
                if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                return []
            }
        }

        // getattrlistbulk returns a bounded batch of names and metadata in a
        // single filesystem call. It preserves symlinks as symlinks and avoids
        // the old per-entry lstat/stat round trips. The buffer is reused for
        // every batch and is never retained by the accumulator.
        var children: [DiskWorkItem] = []
        var fileRecords: [DiskFileRecord] = []
        fileRecords.reserveCapacity(128)
        var bulkEntries: [DiskFileRecord] = []
        bulkEntries.reserveCapacity(256)
        let recordChunkLimit = 128
        while !Task.isCancelled {
            let metadataStartedAt = configuration.collectPerformanceBreakdown ? DispatchTime.now().uptimeNanoseconds : 0
            let metadataError = readBulkDirectoryEntries(fd: directoryFD, buffer: bulkBuffer, entries: &bulkEntries)
            if configuration.collectPerformanceBreakdown {
                accumulator.recordMetadata(
                    callCount: 1,
                    entryCount: UInt64(bulkEntries.count),
                    nanoseconds: DispatchTime.now().uptimeNanoseconds &- metadataStartedAt
                )
            }
            if let error = metadataError {
                let issue = DiskAnalysisIssue(kind: isPermissionErrno(error) ? .permissionDenied : .enumerationFailed, path: work.url, detail: "getattrlistbulk failed: errno \(error).")
                accumulator.recordIssue(issue)
                if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                return children
            }
            guard !bulkEntries.isEmpty else { break }
            accumulator.recordEntriesBuffered(bulkEntries.count)
            var visitedInBatch = 0
            var lastProgressName: String?
            for rawEntryInfo in bulkEntries {
                if Task.isCancelled { break }
                let name = rawEntryInfo.fileName
                var metadata = rawEntryInfo.metadata
                if metadata.category == .directory && configuration.excludedDirectoryNames.contains(name) {
                    continue
                }
                if metadata.category == .symbolicLink && !configuration.includeSymbolicLinks {
                    continue
                }
                // FILEID is omitted from the bulk attribute set. Ordinary
                // single-link files do not need an inode for aggregation or
                // safety decisions. Re-read identity only where it matters:
                // directories, symlinks, and hard-link candidates. A failed
                // conditional read is fail-closed for that entry.
                let needsConditionalIdentity = metadata.category == .directory
                    || metadata.category == .symbolicLink
                    || (metadata.category == .regularFile && metadata.linkCount > 1)
                if needsConditionalIdentity {
                    guard let verification = identityAt(parentFD: directoryFD, name: name),
                          metadata.identity?.device == verification.identity.device else {
                        let issue = DiskAnalysisIssue(
                            kind: .metadataUnavailable,
                            path: work.url.appendingPathComponent(name, isDirectory: metadata.category == .directory),
                            detail: "Conditional identity verification failed; entry was skipped."
                        )
                        accumulator.recordIssue(issue)
                        if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                        continue
                    }
                    metadata = metadata.replacingIdentity(
                        verification.identity,
                        posixMode: metadata.category == .directory ? verification.posixMode : nil
                    )
                }
                let entryInfo = DiskFileRecord(
                    fileName: name,
                    canonicalPath: rawEntryInfo.canonicalPath,
                    metadata: metadata
                )
                if let scanVolumeDevice {
                    let volumeStartedAt = configuration.collectPerformanceBreakdown ? DispatchTime.now().uptimeNanoseconds : 0
                    let isBoundary = metadata.identity?.device != scanVolumeDevice
                    if configuration.collectPerformanceBreakdown {
                        accumulator.recordVolumeCheck(
                            boundary: isBoundary,
                            nanoseconds: DispatchTime.now().uptimeNanoseconds &- volumeStartedAt
                        )
                    }
                    if !isBoundary { /* continue with the normal entry path */ }
                    else {
                    let boundaryPath = work.url.appendingPathComponent(name, isDirectory: metadata.category == .directory)
                    let issue = DiskAnalysisIssue(kind: .volumeBoundary, path: boundaryPath, detail: "Entry is on a different volume and was skipped by the default volume boundary.")
                    accumulator.recordIssue(issue)
                    if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                    continue
                    }
                }
                // getattrlistbulk returns a basename without path separators.
                // The parent URL is already normalized, so appending the
                // basename is sufficient and avoids a Foundation
                // path-normalization pass for every entry. Canonicalization
                // below remains mandatory for directories and symlinks.
                // A regular entry below an already-canonical parent cannot
                // escape through an intermediate symlink: the parent was
                // canonicalized before it entered the queue and getattrlistbulk
                // reports the entry itself without following it. Keep regular
                // files as a basename-only record; constructing URL/canonical
                // objects for every file was a measured hot-path allocation.
                if metadata.category == .regularFile {
                    visitedInBatch += 1
                    lastProgressName = name
                    fileRecords.append(entryInfo)
                    if fileRecords.count >= recordChunkLimit {
                        accumulator.recordVisits(visitedInBatch)
                        if let progress {
                            await accumulator.recordFiles(
                                fileRecords,
                                parentPath: work.url,
                                parentCanonicalPath: work.canonicalPath,
                                aggregateKey: aggregateKey,
                                scanRootKey: scanRootKey,
                                progress: progress
                            )
                        } else {
                            accumulator.recordFilesWithoutProgress(
                                fileRecords,
                                parentPath: work.url,
                                parentCanonicalPath: work.canonicalPath,
                                aggregateKey: aggregateKey,
                                scanRootKey: scanRootKey
                            )
                        }
                        visitedInBatch = 0
                        fileRecords.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                // A bulk entry reported as VDIR is not a symlink. Its parent
                // is already canonical, so constructing the child from that
                // canonical parent is equivalent to realpath here. The queued
                // directory is still opened with O_NOFOLLOW and checked with
                // fstat before enumeration, preserving the race/identity
                // boundary without an extra realpath syscall per directory.
                if metadata.category == .directory {
                    let normalized = work.canonicalPath.appendingPathComponent(name, isDirectory: true)
                    let displayPath = work.url.appendingPathComponent(name, isDirectory: true)
                    visitedInBatch += 1
                    lastProgressName = name
                    guard allowedRoots.contains(where: { pathIsWithin(normalized, root: $0) }) else {
                        let issue = DiskAnalysisIssue(kind: .protectedPath, path: displayPath, detail: "Resolved entry escaped the configured allowed roots.")
                        accumulator.recordIssue(issue)
                        if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                        continue
                    }
                    children.append(DiskWorkItem(
                        url: displayPath,
                        canonicalPath: normalized,
                        parentCanonicalPath: work.canonicalPath,
                        scanRootPath: work.scanRootPath,
                        visibleAggregatePath: work.parentCanonicalPath == nil ? normalized : work.visibleAggregatePath,
                        depth: pathDepth(normalized),
                        metadata: metadata
                    ))
                    continue
                }

                let symlinkStartedAt = metadata.category == .symbolicLink && configuration.collectPerformanceBreakdown
                    ? DispatchTime.now().uptimeNanoseconds
                    : 0
                let normalized = work.url.appendingPathComponent(name, isDirectory: false)
                guard let canonical = canonicalURL(normalized) else {
                    if metadata.category == .symbolicLink && configuration.collectPerformanceBreakdown {
                        accumulator.recordSymlink(nanoseconds: DispatchTime.now().uptimeNanoseconds &- symlinkStartedAt)
                    }
                    let kind: DiskAnalysisIssueKind = metadata.category == .symbolicLink ? .symlinkUnresolved : .metadataUnavailable
                    let issue = DiskAnalysisIssue(kind: kind, path: normalized, detail: "Canonical path resolution failed; entry was not followed.")
                    accumulator.recordIssue(issue)
                    if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                    continue
                }
                visitedInBatch += 1
                lastProgressName = name

            if metadata.category == .symbolicLink {
                let kind = allowedRoots.contains(where: { pathIsWithin(canonical, root: $0) }) ? DiskAnalysisIssueKind.symlinkSkipped : .symlinkEscape
                let issue = DiskAnalysisIssue(kind: kind, path: normalized, detail: "Symlinks are retained as leaves and never recursively followed.")
                accumulator.recordIssue(issue)
                fileRecords.append(DiskFileRecord(
                    fileName: name,
                    canonicalPath: canonical,
                    metadata: metadata
                ))
                if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                if configuration.collectPerformanceBreakdown {
                    accumulator.recordSymlink(nanoseconds: DispatchTime.now().uptimeNanoseconds &- symlinkStartedAt)
                }
                continue
            }

            guard allowedRoots.contains(where: { pathIsWithin(canonical, root: $0) }) else {
                let issue = DiskAnalysisIssue(kind: .protectedPath, path: normalized, detail: "Resolved entry escaped the configured allowed roots.")
                accumulator.recordIssue(issue)
                if let progress { await emitIssue(issue, accumulator: accumulator, progress: progress) }
                continue
            }
            fileRecords.append(DiskFileRecord(
                fileName: name,
                canonicalPath: canonical,
                metadata: metadata
            ))
                if fileRecords.count >= recordChunkLimit {
                    accumulator.recordVisits(visitedInBatch)
                    if let progress {
                        await accumulator.recordFiles(
                            fileRecords,
                            parentPath: work.url,
                            parentCanonicalPath: work.canonicalPath,
                            aggregateKey: aggregateKey,
                            scanRootKey: scanRootKey,
                            progress: progress
                        )
                    } else {
                        accumulator.recordFilesWithoutProgress(
                            fileRecords,
                            parentPath: work.url,
                            parentCanonicalPath: work.canonicalPath,
                            aggregateKey: aggregateKey,
                            scanRootKey: scanRootKey
                        )
                    }
                    visitedInBatch = 0
                    fileRecords.removeAll(keepingCapacity: true)
                }
        }
            if visitedInBatch > 0 {
                accumulator.recordVisits(visitedInBatch)
            }
            if let progress {
                await accumulator.recordFiles(
                    fileRecords,
                    parentPath: work.url,
                    parentCanonicalPath: work.canonicalPath,
                    aggregateKey: aggregateKey,
                    scanRootKey: scanRootKey,
                    progress: progress
                )
            } else {
                accumulator.recordFilesWithoutProgress(
                    fileRecords,
                    parentPath: work.url,
                    parentCanonicalPath: work.canonicalPath,
                    aggregateKey: aggregateKey,
                    scanRootKey: scanRootKey
                )
            }
            fileRecords.removeAll(keepingCapacity: true)
            if let progress, let lastProgressName, accumulator.shouldEmitProgress() {
                let counts = accumulator.counts()
                await progress(DiskAnalysisUpdate(
                    kind: .progress,
                    path: work.url.appendingPathComponent(lastProgressName, isDirectory: false),
                    visitedPathCount: counts.visited,
                    fileCount: counts.files,
                    directoryCount: counts.directories,
                    totalBytes: counts.bytes,
                    allocatedBytes: counts.allocated
                ))
            }
        }
        return children
    }

    private static func emitIssue(
        _ issue: DiskAnalysisIssue,
        accumulator: DiskAnalysisAccumulator,
        progress: @Sendable (DiskAnalysisUpdate) async -> Void
    ) async {
        let counts = accumulator.counts()
        await progress(DiskAnalysisUpdate(
            kind: .issue,
            path: issue.path,
            issue: issue,
            visitedPathCount: counts.visited,
            fileCount: counts.files,
            directoryCount: counts.directories,
            totalBytes: counts.bytes,
            allocatedBytes: counts.allocated
        ))
    }
}

private struct DiskWorkItem: Sendable {
    let url: URL
    let canonicalPath: URL
    let parentCanonicalPath: URL?
    let scanRootPath: URL
    /// The root-level directory whose aggregate is retained for the final
    /// treemap. Deeper directories are intentionally not retained.
    let visibleAggregatePath: URL
    let depth: Int
    let metadata: DiskMetadata
}

private struct DiskFileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

private struct DiskTimestamp: Comparable, Sendable {
    let seconds: Int64
    let nanoseconds: Int32

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
    }

    static func < (lhs: DiskTimestamp, rhs: DiskTimestamp) -> Bool {
        if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
        return lhs.nanoseconds < rhs.nanoseconds
    }
}

private struct DiskVolumeContext: Sendable {
    let device: UInt64?
    let capacityBytes: UInt64?
    let filesystemName: String?
}

private struct DiskMetadata: Sendable {
    let category: FileCategory
    let sizeBytes: UInt64
    let allocatedSizeBytes: UInt64
    let lastModified: DiskTimestamp?
    let posixMode: UInt16
    let identity: DiskFileIdentity?
    let linkCount: UInt32

    func replacingIdentity(_ identity: DiskFileIdentity?, posixMode: UInt16? = nil) -> DiskMetadata {
        DiskMetadata(
            category: category,
            sizeBytes: sizeBytes,
            allocatedSizeBytes: allocatedSizeBytes,
            lastModified: lastModified,
            posixMode: posixMode ?? self.posixMode,
            identity: identity,
            linkCount: linkCount
        )
    }
}

private final class CompactDirectoryIdentitySet: @unchecked Sendable {
    private var devices: UnsafeMutablePointer<UInt64>
    private var inodes: UnsafeMutablePointer<UInt64>
    private(set) var count = 0
    private var capacity: Int

    init(initialCapacity: Int = 1 << 12) {
        let normalizedCapacity = max(16, initialCapacity.nextPowerOfTwo)
        capacity = normalizedCapacity
        devices = .allocate(capacity: normalizedCapacity)
        inodes = .allocate(capacity: normalizedCapacity)
        devices.initialize(repeating: 0, count: normalizedCapacity)
        inodes.initialize(repeating: 0, count: normalizedCapacity)
    }

    deinit {
        devices.deinitialize(count: capacity)
        inodes.deinitialize(count: capacity)
        devices.deallocate()
        inodes.deallocate()
    }

    func insert(_ identity: DiskFileIdentity) -> Bool {
        guard identity.device != 0, identity.inode != 0 else { return false }
        if count * 10 >= capacity * 8 { resize() }
        var index = bucket(for: identity, capacity: capacity)
        while devices[index] != 0 {
            if devices[index] == identity.device && inodes[index] == identity.inode { return false }
            index = (index + 1) & (capacity - 1)
        }
        devices[index] = identity.device
        inodes[index] = identity.inode
        count += 1
        return true
    }

    func removeAll() {
        devices.deinitialize(count: capacity)
        inodes.deinitialize(count: capacity)
        devices.deallocate()
        inodes.deallocate()
        capacity = 1 << 12
        devices = .allocate(capacity: capacity)
        inodes = .allocate(capacity: capacity)
        devices.initialize(repeating: 0, count: capacity)
        inodes.initialize(repeating: 0, count: capacity)
        count = 0
    }

    private func resize() {
        let oldCapacity = capacity
        let oldDevices = devices
        let oldInodes = inodes
        capacity *= 2
        devices = .allocate(capacity: capacity)
        inodes = .allocate(capacity: capacity)
        devices.initialize(repeating: 0, count: capacity)
        inodes.initialize(repeating: 0, count: capacity)
        count = 0
        for index in 0..<oldCapacity where oldDevices[index] != 0 {
            _ = insert(DiskFileIdentity(device: oldDevices[index], inode: oldInodes[index]))
        }
        oldDevices.deinitialize(count: oldCapacity)
        oldInodes.deinitialize(count: oldCapacity)
        oldDevices.deallocate()
        oldInodes.deallocate()
    }

    private func bucket(for identity: DiskFileIdentity, capacity: Int) -> Int {
        var value = identity.device &* 0x9E3779B185EBCA87
        value ^= identity.inode &+ 0xC2B2AE3D27D4EB4F
        value ^= value >> 29
        value &*= 0x165667B19E3779F9
        return Int(truncatingIfNeeded: value) & (capacity - 1)
    }
}

private extension Int {
    var nextPowerOfTwo: Int {
        var value = 1
        while value < self { value <<= 1 }
        return value
    }
}

private actor DiskDirectoryQueue {
    private var pending: [DiskWorkItem] = []
    // Directory identity is captured by getattrlistbulk and checked again by
    // fstat immediately before enumeration. The compact table stores the
    // complete device+inode pair (not a hash-only approximation), avoiding
    // large per-entry Swift enum/Hashable allocations. Entries without
    // identity fall back to their canonical path.
    private var seenDirectoryIdentities = CompactDirectoryIdentitySet()
    private var seenDirectoryPaths: Set<String> = []
    private var inFlight = 0
    private var maxInFlight = 0
    private var cancelled = false
    private var waiters: [CheckedContinuation<DiskWorkItem?, Never>] = []

    init(initialIdentityCapacity: Int) {
        seenDirectoryIdentities = CompactDirectoryIdentitySet(initialCapacity: initialIdentityCapacity)
    }

    func enqueue(_ items: [DiskWorkItem]) -> [URL] {
        var duplicates: [URL] = []
        for item in items {
            let inserted: Bool
            if let identity = item.metadata.identity, identity.device != 0, identity.inode != 0 {
                inserted = seenDirectoryIdentities.insert(identity)
            } else {
                inserted = seenDirectoryPaths.insert(item.canonicalPath.path).inserted
            }
            guard inserted else {
                duplicates.append(item.url)
                continue
            }
            if let waiter = waiters.popLast() {
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
                waiter.resume(returning: item)
            } else {
                pending.append(item)
            }
        }
        return duplicates
    }

    func next() async -> DiskWorkItem? {
        guard !cancelled else { return nil }
        if let item = pending.popLast() {
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return item
        }
        guard inFlight > 0 else { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func complete() {
        inFlight = max(0, inFlight - 1)
        if inFlight == 0 && pending.isEmpty {
            let currentWaiters = waiters
            waiters.removeAll()
            for waiter in currentWaiters { waiter.resume(returning: nil) }
        }
    }

    func cancel() {
        cancelled = true
        pending.removeAll()
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters { waiter.resume(returning: nil) }
    }

    func wasCancelled() -> Bool { cancelled }
    func maxObservedConcurrency() -> Int { maxInFlight }

    func releaseTransientState() {
        pending.removeAll(keepingCapacity: false)
        seenDirectoryIdentities.removeAll()
        seenDirectoryPaths.removeAll(keepingCapacity: false)
    }
}

private struct DiskFileRecord: Sendable {
    let fileName: String
    let canonicalPath: URL?
    let metadata: DiskMetadata
}

private struct LargeFileRankingKey {
    let parentPath: String
    let fileName: String

    /// Compares the virtual UTF-8 sequence `parentPath + "/" + fileName`.
    /// This preserves the existing URL.path tie-breaker without allocating a
    /// joined String for every candidate that is not retained in Top-N.
    func precedes(_ other: LargeFileRankingKey) -> Bool {
        var lhs = VirtualPathUTF8Iterator(parentPath: parentPath, fileName: fileName)
        var rhs = VirtualPathUTF8Iterator(parentPath: other.parentPath, fileName: other.fileName)
        while let leftByte = lhs.next() {
            guard let rightByte = rhs.next() else { return false }
            if leftByte != rightByte { return leftByte < rightByte }
        }
        return rhs.next() != nil
    }
}

private struct VirtualPathUTF8Iterator {
    private var parent: String.UTF8View.Iterator
    private var name: String.UTF8View.Iterator
    private var phase = 0

    init(parentPath: String, fileName: String) {
        parent = parentPath.utf8.makeIterator()
        name = fileName.utf8.makeIterator()
    }

    mutating func next() -> UInt8? {
        while phase < 3 {
            switch phase {
            case 0:
                if let byte = parent.next() { return byte }
                phase = 1
            case 1:
                phase = 2
                return 47
            default:
                if let byte = name.next() { return byte }
                phase = 3
            }
        }
        return nil
    }
}

private final class DiskAnalysisAccumulator: @unchecked Sendable {
    private struct MutableBreakdown {
        var metadataCalls: UInt64 = 0
        var metadataEntries: UInt64 = 0
        var metadataNanoseconds: UInt64 = 0
        var symlinkEntries: UInt64 = 0
        var symlinkNanoseconds: UInt64 = 0
        var volumeChecks: UInt64 = 0
        var volumeBoundaryEntries: UInt64 = 0
        var volumeNanoseconds: UInt64 = 0
        var permissionChecks: UInt64 = 0
        var permissionFailures: UInt64 = 0
        var identityChecks: UInt64 = 0
        var identityNanoseconds: UInt64 = 0
        var hardLinkCandidates: UInt64 = 0
        var hardLinkDuplicates: UInt64 = 0
        var hardLinkNanoseconds: UInt64 = 0
        var watchdogOpens: UInt64 = 0
        var watchdogTimeouts: UInt64 = 0
        var watchdogNanoseconds: UInt64 = 0
        var aggregationRecords: UInt64 = 0
        var aggregationNanoseconds: UInt64 = 0
        var largeFileCandidates: UInt64 = 0
        var largeFileEntriesMaterialized: UInt64 = 0
        var largeFileCandidatesRejectedBeforeMaterialization: UInt64 = 0

        var value: DiskAnalysisBreakdown {
            DiskAnalysisBreakdown(
                metadataCalls: metadataCalls,
                metadataEntries: metadataEntries,
                metadataNanoseconds: metadataNanoseconds,
                symlinkEntries: symlinkEntries,
                symlinkNanoseconds: symlinkNanoseconds,
                volumeChecks: volumeChecks,
                volumeBoundaryEntries: volumeBoundaryEntries,
                volumeNanoseconds: volumeNanoseconds,
                permissionChecks: permissionChecks,
                permissionFailures: permissionFailures,
                identityChecks: identityChecks,
                identityNanoseconds: identityNanoseconds,
                hardLinkCandidates: hardLinkCandidates,
                hardLinkDuplicates: hardLinkDuplicates,
                hardLinkNanoseconds: hardLinkNanoseconds,
                watchdogOpens: watchdogOpens,
                watchdogTimeouts: watchdogTimeouts,
                watchdogNanoseconds: watchdogNanoseconds,
                aggregationRecords: aggregationRecords,
                aggregationNanoseconds: aggregationNanoseconds,
                largeFileCandidates: largeFileCandidates,
                largeFileEntriesMaterialized: largeFileEntriesMaterialized,
                largeFileCandidatesRejectedBeforeMaterialization: largeFileCandidatesRejectedBeforeMaterialization
            )
        }
    }

    private final class MutableAggregate: @unchecked Sendable {
        let path: URL
        let canonicalPath: URL
        let parentCanonicalPath: URL?
        var logicalBytes: UInt64 = 0
        var allocatedBytes: UInt64 = 0
        var fileCount: UInt64 = 0
        var directoryCount: UInt64 = 0
        var latestModification: DiskTimestamp?
        var isComplete = false

        init(path: URL, canonicalPath: URL, parentCanonicalPath: URL?, latestModification: DiskTimestamp?) {
            self.path = path
            self.canonicalPath = canonicalPath
            self.parentCanonicalPath = parentCanonicalPath
            self.latestModification = latestModification
        }
    }

    private let lock = NSLock()
    private let startedAt: Date
    private let configuration: DiskAnalysisConfiguration
    private let largeFileOptions: LargeFileOptions
    private let referenceDate: Date
    // Only scan roots and their direct children are retained. All deeper
    // directory state is folded into the direct-child aggregate and can be
    // loaded lazily by the UI after the scan completes.
    private var aggregates: [String: MutableAggregate] = [:]
    private var roots: [String] = []
    private var rootChildren: [String: Set<String>] = [:]
    private var seenFileIdentities: Set<DiskFileIdentity> = []
    private var largeFiles: [LargeFileEntry] = []
    // Content groups are a fixed, small enum. Keeping the counters in slots
    // avoids a dictionary lookup and value replacement for every regular file;
    // the public dictionary is materialized once when the snapshot is built.
    private var contentFileCounts = [UInt64](repeating: 0, count: 7)
    private var contentLogicalBytes = [UInt64](repeating: 0, count: 7)
    private var contentAllocatedBytes = [UInt64](repeating: 0, count: 7)
    private var issues: [DiskAnalysisIssue] = []
    private var suppressedIssueCount: UInt64 = 0
    private var visitedPathCount: UInt64 = 0
    private var fileCount: UInt64 = 0
    private var directoryCount: UInt64 = 0
    private var totalBytes: UInt64 = 0
    private var allocatedBytes: UInt64 = 0
    private var volumeCapacityBytes: UInt64?
    private var filesystemName: String?
    private var maxDirectoryEntriesBuffered = 0
    private var cancellationObservedAt: Date?
    private var memorySamples: [DiskMemorySample] = []
    private var lastSampleAt: UInt64 = 0
    private var breakdown = MutableBreakdown()
    private var largeFileRankingKeys: [LargeFileRankingKey] = []

    init(startedAt: Date, configuration: DiskAnalysisConfiguration) {
        self.startedAt = startedAt
        self.configuration = configuration
        self.largeFileOptions = configuration.largeFiles
        self.referenceDate = configuration.referenceDate
    }

    func configureVolume(_ context: DiskVolumeContext?) {
        lock.lock()
        defer { lock.unlock() }
        volumeCapacityBytes = context?.capacityBytes
        filesystemName = context?.filesystemName
    }

    func recordMetadata(callCount: UInt64, entryCount: UInt64, nanoseconds: UInt64) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.metadataCalls &+= callCount
        breakdown.metadataEntries &+= entryCount
        breakdown.metadataNanoseconds &+= nanoseconds
        lock.unlock()
    }

    func recordSymlink(nanoseconds: UInt64) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.symlinkEntries &+= 1
        breakdown.symlinkNanoseconds &+= nanoseconds
        lock.unlock()
    }

    func recordVolumeCheck(boundary: Bool, nanoseconds: UInt64) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.volumeChecks &+= 1
        if boundary { breakdown.volumeBoundaryEntries &+= 1 }
        breakdown.volumeNanoseconds &+= nanoseconds
        lock.unlock()
    }

    func recordPermissionCheck(failed: Bool) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.permissionChecks &+= 1
        if failed { breakdown.permissionFailures &+= 1 }
        lock.unlock()
    }

    func recordIdentityCheck(nanoseconds: UInt64) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.identityChecks &+= 1
        breakdown.identityNanoseconds &+= nanoseconds
        lock.unlock()
    }

    func recordWatchdog(timeout: Bool, nanoseconds: UInt64) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.watchdogOpens &+= 1
        if timeout { breakdown.watchdogTimeouts &+= 1 }
        breakdown.watchdogNanoseconds &+= nanoseconds
        lock.unlock()
    }

    func recordAggregation(recordCount: UInt64, nanoseconds: UInt64) {
        guard configuration.collectPerformanceBreakdown else { return }
        lock.lock()
        breakdown.aggregationRecords &+= recordCount
        breakdown.aggregationNanoseconds &+= nanoseconds
        lock.unlock()
    }

    func recordDirectory(_ work: DiskWorkItem) {
        lock.lock()
        defer { lock.unlock() }
        let rootPath = work.scanRootPath.path
        let canonicalPath = work.canonicalPath.path
        let aggregatePath = work.parentCanonicalPath == nil ? canonicalPath : work.visibleAggregatePath.path
        if work.parentCanonicalPath != nil { rootChildren[rootPath, default: []].insert(aggregatePath) }
        if aggregates[aggregatePath] == nil {
            let aggregateURL = URL(fileURLWithPath: aggregatePath)
            aggregates[aggregatePath] = MutableAggregate(
                path: work.parentCanonicalPath == nil ? work.url : work.visibleAggregatePath,
                canonicalPath: aggregateURL,
                parentCanonicalPath: work.parentCanonicalPath == nil ? nil : work.scanRootPath,
                latestModification: work.metadata.lastModified
            )
        }
        aggregates[aggregatePath]?.directoryCount &+= 1
        if let timestamp = work.metadata.lastModified, aggregates[aggregatePath]?.latestModification.map({ $0 < timestamp }) ?? true {
            aggregates[aggregatePath]?.latestModification = timestamp
        }
        // The root aggregate contains all directories, while the visible
        // direct-child aggregate contains its own subtree count.
        if work.parentCanonicalPath != nil, aggregatePath != rootPath {
            aggregates[rootPath]?.directoryCount &+= 1
            if let timestamp = work.metadata.lastModified, aggregates[rootPath]?.latestModification.map({ $0 < timestamp }) ?? true {
                aggregates[rootPath]?.latestModification = timestamp
            }
        }
        directoryCount += 1
        if work.parentCanonicalPath == nil { roots.append(canonicalPath) }
        sampleMemoryIfNeeded()
    }

    func recordVisits(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        visitedPathCount &+= UInt64(max(0, count))
        sampleMemoryIfNeeded()
    }

    func recordEntriesBuffered(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        maxDirectoryEntriesBuffered = max(maxDirectoryEntriesBuffered, count)
    }

    func recordFiles(
        _ records: [DiskFileRecord],
        parentPath: URL,
        parentCanonicalPath: URL,
        aggregateKey: String,
        scanRootKey: String,
        progress: (@Sendable (DiskAnalysisUpdate) async -> Void)?
    ) async {
        let aggregationStartedAt = configuration.collectPerformanceBreakdown ? DispatchTime.now().uptimeNanoseconds : 0
        let emittedUpdates = recordFilesLocked(
            records,
            parentPath: parentPath,
            parentCanonicalPath: parentCanonicalPath,
            aggregateKey: aggregateKey,
            scanRootKey: scanRootKey,
            emitUpdates: progress != nil
        )
        if configuration.collectPerformanceBreakdown {
            recordAggregation(
                recordCount: UInt64(records.count),
                nanoseconds: DispatchTime.now().uptimeNanoseconds &- aggregationStartedAt
            )
        }
        if let progress {
            for update in emittedUpdates {
                await progress(update)
            }
        }
    }

    /// The benchmark and completed Home path commonly has no progress
    /// callback. Keep that path synchronous so each batch does not pay an
    /// async continuation/suspension cost; the locked aggregation and all
    /// identity checks remain identical.
    func recordFilesWithoutProgress(
        _ records: [DiskFileRecord],
        parentPath: URL,
        parentCanonicalPath: URL,
        aggregateKey: String,
        scanRootKey: String
    ) {
        let aggregationStartedAt = configuration.collectPerformanceBreakdown ? DispatchTime.now().uptimeNanoseconds : 0
        _ = recordFilesLocked(
            records,
            parentPath: parentPath,
            parentCanonicalPath: parentCanonicalPath,
            aggregateKey: aggregateKey,
            scanRootKey: scanRootKey,
            emitUpdates: false
        )
        if configuration.collectPerformanceBreakdown {
            recordAggregation(
                recordCount: UInt64(records.count),
                nanoseconds: DispatchTime.now().uptimeNanoseconds &- aggregationStartedAt
            )
        }
    }

    private func recordFilesLocked(
        _ records: [DiskFileRecord],
        parentPath: URL,
        parentCanonicalPath: URL,
        aggregateKey: String,
        scanRootKey: String,
        emitUpdates: Bool
    ) -> [DiskAnalysisUpdate] {
        var emittedUpdates: [DiskAnalysisUpdate] = []
        lock.lock()
        defer { lock.unlock() }
        let parentPathKey = parentPath.path
        for record in records {
            if Task.isCancelled { break }
            guard let entry = recordFile(
                record,
                parentPath: parentPath,
                parentCanonicalPath: parentCanonicalPath,
                aggregateKey: aggregateKey,
                scanRootKey: scanRootKey,
                parentPathKey: parentPathKey,
            ) else { continue }
            if emitUpdates {
                emittedUpdates.append(DiskAnalysisUpdate(
                    kind: .largeFileFound,
                    path: entry.path,
                    largeFile: entry,
                    visitedPathCount: visitedPathCount,
                    fileCount: fileCount,
                    directoryCount: directoryCount,
                    totalBytes: totalBytes,
                    allocatedBytes: allocatedBytes
                ))
            }
        }
        return emittedUpdates
    }

    private func recordFile(
        _ record: DiskFileRecord,
        parentPath: URL,
        parentCanonicalPath: URL,
        aggregateKey: String,
        scanRootKey: String,
        parentPathKey: String
    ) -> LargeFileEntry? {
        let fileName = record.fileName
        let metadata = record.metadata
        fileCount += 1
        let isUnique: Bool
        let hardLinkStartedAt = configuration.collectPerformanceBreakdown && metadata.linkCount > 1
            ? DispatchTime.now().uptimeNanoseconds
            : 0
        if metadata.linkCount > 1, let identity = metadata.identity {
            isUnique = seenFileIdentities.insert(identity).inserted
        } else {
            isUnique = true
        }
        if configuration.collectPerformanceBreakdown && metadata.linkCount > 1 {
            // recordFile is called while recordFilesLocked holds `lock`.
            // Update the optional audit counters in place to avoid lock
            // re-entry in diagnostics mode.
            breakdown.hardLinkCandidates &+= 1
            if !isUnique { breakdown.hardLinkDuplicates &+= 1 }
            breakdown.hardLinkNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- hardLinkStartedAt
        }
        if isUnique {
            totalBytes &+= metadata.sizeBytes
            allocatedBytes &+= metadata.allocatedSizeBytes
        }
        if let aggregate = aggregates[aggregateKey] {
            aggregate.fileCount &+= 1
            if isUnique {
                aggregate.logicalBytes &+= metadata.sizeBytes
                aggregate.allocatedBytes &+= metadata.allocatedSizeBytes
            }
            if let timestamp = metadata.lastModified, aggregate.latestModification.map({ $0 < timestamp }) ?? true { aggregate.latestModification = timestamp }
        }
        if aggregateKey != scanRootKey, let root = aggregates[scanRootKey] {
            root.fileCount &+= 1
            if isUnique {
                root.logicalBytes &+= metadata.sizeBytes
                root.allocatedBytes &+= metadata.allocatedSizeBytes
            }
            if let timestamp = metadata.lastModified, root.latestModification.map({ $0 < timestamp }) ?? true { root.latestModification = timestamp }
        }
        if metadata.category == .regularFile, isUnique {
            let contentCategory = DiskContentCategory.classify(fileName: fileName)
            let index = contentCategory.accumulatorIndex
            contentFileCounts[index] &+= 1
            contentLogicalBytes[index] &+= metadata.sizeBytes
            contentAllocatedBytes[index] &+= metadata.allocatedSizeBytes
        }
        let nowAge = metadata.lastModified.map { max(0, referenceDate.timeIntervalSince($0.date)) }
        let path = largeFileOptions.pathPrefix == nil ? nil : parentPath.appendingPathComponent(fileName, isDirectory: false)
        guard isLargeFileMatch(
            path: path,
            sizeBytes: metadata.sizeBytes,
            category: metadata.category,
            age: nowAge,
            options: largeFileOptions
        ) else {
            sampleMemoryIfNeeded()
            return nil
        }
        if configuration.collectPerformanceBreakdown {
            breakdown.largeFileCandidates &+= 1
        }
        guard isUnique else { return nil }
        let rankingKey = LargeFileRankingKey(parentPath: parentPathKey, fileName: fileName)
        guard let retention = largeFileRetention(sizeBytes: metadata.sizeBytes, key: rankingKey) else {
            if configuration.collectPerformanceBreakdown {
                breakdown.largeFileCandidatesRejectedBeforeMaterialization &+= 1
            }
            sampleMemoryIfNeeded()
            return nil
        }
        // Only a matching entry needs a canonical/path URL in the result.
        // Ordinary files are already proven to be below the canonical parent;
        // delaying this construction removes one Foundation allocation from
        // the hot path for every non-large file.
        if configuration.collectPerformanceBreakdown {
            breakdown.largeFileEntriesMaterialized &+= 1
        }
        let canonicalPath = record.canonicalPath ?? parentCanonicalPath.appendingPathComponent(fileName, isDirectory: false)
        let entry = LargeFileEntry(
            path: path ?? parentPath.appendingPathComponent(fileName, isDirectory: false),
            canonicalPath: canonicalPath,
            sizeBytes: metadata.sizeBytes,
            allocatedSizeBytes: metadata.allocatedSizeBytes,
            lastModified: metadata.lastModified?.date,
            fileType: metadata.category,
            age: nowAge
        )
        retainLargeFile(entry, key: rankingKey, retention: retention)
        sampleMemoryIfNeeded()
        return entry
    }

    func completeDirectory(_ work: DiskWorkItem) -> DiskNode? {
        lock.lock()
        defer { lock.unlock() }
        let canonicalPath = work.canonicalPath.path
        let aggregateKey = work.parentCanonicalPath == nil ? canonicalPath : work.visibleAggregatePath.path
        aggregates[aggregateKey]?.isComplete = true
        guard work.parentCanonicalPath == nil || canonicalPath == aggregateKey,
              let aggregate = aggregates[aggregateKey] else { return nil }
        return makeNode(aggregate, otherBytes: 0)
    }

    func recordIssue(_ issue: DiskAnalysisIssue) {
        lock.lock()
        defer { lock.unlock() }
        if issues.count < 1_024 {
            issues.append(issue)
        } else {
            suppressedIssueCount &+= 1
        }
    }

    func markCancelled() {
        lock.lock()
        defer { lock.unlock() }
        if cancellationObservedAt == nil { cancellationObservedAt = Date() }
        if !issues.contains(where: { $0.kind == .cancelled }) {
            let issue = DiskAnalysisIssue(kind: .cancelled, path: URL(fileURLWithPath: "/"), detail: "Analysis cancelled before completion.")
            if issues.count < 1_024 { issues.append(issue) } else {
                issues[issues.count - 1] = issue
                suppressedIssueCount &+= 1
            }
        }
    }

    func markCancellationObserved() {
        lock.lock()
        defer { lock.unlock() }
        if cancellationObservedAt == nil { cancellationObservedAt = Date() }
    }

    func shouldEmitProgress() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return visitedPathCount > 0 && visitedPathCount % configuration.memorySampleStride == 0
    }

    func counts() -> (visited: UInt64, files: UInt64, directories: UInt64, bytes: UInt64, allocated: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (visitedPathCount, fileCount, directoryCount, totalBytes, allocatedBytes)
    }

    func makeSnapshot(finishedAt: Date, cancelled: Bool, maxObservedConcurrency: Int) -> DiskAnalysisSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let rootNodes: [DiskNode] = roots.compactMap { path -> DiskNode? in
            guard let aggregate = aggregates[path] else { return nil }
            let childrenBytes = rootChildren[path, default: []].reduce(UInt64(0)) { partial, child in
                partial &+ (aggregates[child]?.logicalBytes ?? 0)
            }
            let childrenAllocatedBytes = rootChildren[path, default: []].reduce(UInt64(0)) { partial, child in
                partial &+ (aggregates[child]?.allocatedBytes ?? 0)
            }
            return makeNode(
                aggregate,
                otherBytes: aggregate.logicalBytes >= childrenBytes ? aggregate.logicalBytes - childrenBytes : 0,
                otherAllocatedSizeBytes: aggregate.allocatedBytes >= childrenAllocatedBytes ? aggregate.allocatedBytes - childrenAllocatedBytes : 0
            )
        }.sorted { $0.canonicalPath.path < $1.canonicalPath.path }
        let rootNodePaths = Set(roots)
        let directChildren = rootChildren.values.flatMap { $0 }.compactMap { path -> DiskNode? in
            guard let aggregate = aggregates[path], !rootNodePaths.contains(path) else { return nil }
            // A direct-child aggregate already represents its complete
            // subtree. Its own `Other` projection would duplicate the same
            // bytes when a UI drills into the child, because the collapsed
            // aggregate does not retain a second immediate-file bucket.
            // Only the scan root receives an `Other` remainder below.
            return makeNode(aggregate, otherBytes: 0, otherAllocatedSizeBytes: 0)
        }
        let directoryNodes = (rootNodes + directChildren).sorted { $0.canonicalPath.path < $1.canonicalPath.path }
        let retainedLargeFiles = largeFiles.sorted { lhs, rhs in
            if lhs.sizeBytes == rhs.sizeBytes { return lhs.path.path < rhs.path.path }
            return lhs.sizeBytes > rhs.sizeBytes
        }
        let tree = DiskTree(
            roots: rootNodes,
            nodes: directoryNodes,
            retainedFileNodeCount: UInt64(retainedLargeFiles.count),
            isComplete: !cancelled
        )
        let usage = resourceUsage()
        let duration = max(0, finishedAt.timeIntervalSince(startedAt))
        let cpu = max(0, usage.cpuTime - initialCPUTime)
        let performance = DiskAnalysisPerformance(
            duration: duration,
            cpuTimeSeconds: cpu,
            averageCPUPercent: duration > 0 ? cpu / duration * 100 : 0,
            peakResidentMemoryBytes: memorySamples.map(\.residentMemoryBytes).max() ?? usage.residentMemory,
            memorySamples: memorySamples,
            throughputFilesPerSecond: duration > 0 ? Double(fileCount) / duration : 0,
            maxObservedConcurrentDirectories: maxObservedConcurrency,
            maxDirectoryEntriesBuffered: maxDirectoryEntriesBuffered,
            cancellationLatency: cancellationObservedAt.map { max(0, finishedAt.timeIntervalSince($0)) },
            breakdown: configuration.collectPerformanceBreakdown ? breakdown.value : nil
        )
        var contentStatistics: [DiskContentCategory: DiskContentStatistics] = [:]
        for category in DiskContentCategory.allCases {
            let index = category.accumulatorIndex
            if contentFileCounts[index] > 0 {
                contentStatistics[category] = DiskContentStatistics(
                    fileCount: contentFileCounts[index],
                    totalBytes: contentLogicalBytes[index],
                    allocatedBytes: contentAllocatedBytes[index]
                )
            }
        }
        let boundedAllocatedBytes = volumeCapacityBytes.map { min(allocatedBytes, $0) } ?? allocatedBytes
        let allocationStatus: DiskAllocationStatus
        if volumeCapacityBytes == nil {
            allocationStatus = .unavailable
        } else if boundedAllocatedBytes != allocatedBytes {
            allocationStatus = .volumeBounded
        } else if filesystemName?.lowercased() == "apfs" {
            allocationStatus = .filesystemReportedSharedExtentsUnknown
        } else {
            allocationStatus = .filesystemReported
        }
        return DiskAnalysisSnapshot(
            startedAt: startedAt,
            finishedAt: finishedAt,
            cancelled: cancelled,
            visitedPathCount: visitedPathCount,
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalBytes: totalBytes,
            allocatedBytes: boundedAllocatedBytes,
            volumeCapacityBytes: volumeCapacityBytes,
            allocationStatus: allocationStatus,
            tree: tree,
            // The projection is derived lazily from tree + largeFiles.
            treemapNodes: [],
            largeFiles: retainedLargeFiles,
            contentStatistics: contentStatistics,
            issues: issues,
            suppressedIssueCount: suppressedIssueCount,
            performance: performance
        )
    }

    private let initialCPUTime: TimeInterval = resourceUsage().cpuTime

    private func makeNode(_ directory: MutableAggregate, otherBytes: UInt64, otherAllocatedSizeBytes: UInt64 = 0) -> DiskNode {
        DiskNode(
            path: directory.path,
            canonicalPath: directory.canonicalPath,
            parentCanonicalPath: directory.parentCanonicalPath,
            name: directory.path.lastPathComponent,
            category: .directory,
            sizeBytes: directory.logicalBytes,
            otherBytes: otherBytes,
            allocatedSizeBytes: volumeCapacityBytes.map { min(directory.allocatedBytes, $0) } ?? directory.allocatedBytes,
            otherAllocatedSizeBytes: volumeCapacityBytes.map { min(otherAllocatedSizeBytes, $0) } ?? otherAllocatedSizeBytes,
            fileCount: directory.fileCount,
            directoryCount: directory.directoryCount,
            lastModified: directory.latestModification?.date,
            isComplete: directory.isComplete
        )
    }

    private enum LargeFileRetention {
        case append
        case replace(Int)
    }

    private func largeFileRetention(sizeBytes: UInt64, key: LargeFileRankingKey) -> LargeFileRetention? {
        guard largeFileOptions.topN > 0 else { return nil }
        guard largeFiles.count >= largeFileOptions.topN else { return .append }
        guard let worstIndex = largeFiles.indices.min(by: { lhs, rhs in
            retainedLargeFilePrecedes(
                sizeBytes: largeFiles[lhs].sizeBytes,
                key: largeFileRankingKeys[lhs],
                otherSizeBytes: largeFiles[rhs].sizeBytes,
                otherKey: largeFileRankingKeys[rhs]
            )
        }) else { return nil }
        guard retainedLargeFilePrecedes(
            sizeBytes: sizeBytes,
            key: key,
            otherSizeBytes: largeFiles[worstIndex].sizeBytes,
            otherKey: largeFileRankingKeys[worstIndex]
        ) else { return nil }
        return .replace(worstIndex)
    }

    private func retainedLargeFilePrecedes(
        sizeBytes: UInt64,
        key: LargeFileRankingKey,
        otherSizeBytes: UInt64,
        otherKey: LargeFileRankingKey
    ) -> Bool {
        if sizeBytes == otherSizeBytes { return key.precedes(otherKey) }
        return sizeBytes > otherSizeBytes
    }

    private func retainLargeFile(
        _ entry: LargeFileEntry,
        key: LargeFileRankingKey,
        retention: LargeFileRetention
    ) {
        switch retention {
        case .append:
            largeFiles.append(entry)
            largeFileRankingKeys.append(key)
        case .replace(let index):
            largeFiles[index] = entry
            largeFileRankingKeys[index] = key
        }
    }

    private func sampleMemoryIfNeeded() {
        guard visitedPathCount >= lastSampleAt + configuration.memorySampleStride || memorySamples.isEmpty else { return }
        lastSampleAt = visitedPathCount
        let usage = resourceUsage()
        memorySamples.append(DiskMemorySample(elapsed: Date().timeIntervalSince(startedAt), residentMemoryBytes: usage.residentMemory))
        if memorySamples.count > 256 { memorySamples.removeFirst(128) }
    }
}

private func isLargeFileMatch(
    path: URL?,
    sizeBytes: UInt64,
    category: FileCategory,
    age: TimeInterval?,
    options: LargeFileOptions
) -> Bool {
    guard options.allowedTypes.contains(category), sizeBytes >= options.thresholdBytes else { return false }
    if let minimum = options.minimumAge, (age ?? 0) < minimum { return false }
    if let prefix = options.pathPrefix {
        guard let path, pathIsWithin(path, root: prefix) else { return false }
    }
    if let minimumSize = options.minimumSizeBytes, sizeBytes < minimumSize { return false }
    if let maximumSize = options.maximumSizeBytes, sizeBytes > maximumSize { return false }
    return true
}

private func readDiskMetadata(at url: URL) -> DiskMetadata? {
    var statInfo = stat()
    guard lstat(url.path, &statInfo) == 0 else { return nil }
    let mode = statInfo.st_mode & S_IFMT
    let category: FileCategory
    if mode == S_IFREG { category = .regularFile }
    else if mode == S_IFDIR { category = .directory }
    else if mode == S_IFLNK { category = .symbolicLink }
    else { category = .other }
    let modification = DiskTimestamp(
        seconds: Int64(statInfo.st_mtimespec.tv_sec),
        nanoseconds: Int32(statInfo.st_mtimespec.tv_nsec)
    )
    return DiskMetadata(
        category: category,
        sizeBytes: UInt64(max(0, statInfo.st_size)),
        allocatedSizeBytes: UInt64(max(0, statInfo.st_blocks)) * 512,
        lastModified: modification,
        posixMode: UInt16(statInfo.st_mode & 0o7777),
        identity: DiskFileIdentity(device: UInt64(statInfo.st_dev), inode: UInt64(statInfo.st_ino)),
        linkCount: UInt32(statInfo.st_nlink)
    )
}

private final class BulkDirectoryBuffer: @unchecked Sendable {
    // Keep the buffer reusable and bounded per worker while reducing
    // getattrlistbulk kernel crossings for directories with many entries.
    // 128 KiB is sufficient for the small-directory workload while lowering
    // the bounded per-worker resident footprint. getattrlistbulk is called
    // again when a larger directory needs more records; correctness and
    // traversal scope are unchanged.
    var bytes = [UInt8](repeating: 0, count: 128 * 1024)
}

private enum DirectoryOpenResult: Sendable {
    case opened(Int32)
    case failed(Int32)
    case timedOut
}

struct DiskDirectoryOpenAttempt: Sendable {
    let fileDescriptor: Int32
    let errorNumber: Int32
}

typealias DiskDirectoryOpenHandler = @Sendable (String) -> DiskDirectoryOpenAttempt

private let productionDirectoryOpenHandler: DiskDirectoryOpenHandler = { path in
    let fileDescriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    return DiskDirectoryOpenAttempt(
        fileDescriptor: fileDescriptor,
        errorNumber: fileDescriptor >= 0 ? 0 : errno
    )
}

private final class OneShotResolver<Value: Sendable>: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    // The resolver's unfair-lock guarded `resolved` bit guarantees that this
    // continuation is resumed at most once, including the timeout/open race.
    // The unchecked form removes the per-directory checked-continuation
    // bookkeeping from the hot path without changing the watchdog contract.
    private var continuation: UnsafeContinuation<Value, Never>?
    private var resolved = false

    func install(_ continuation: UnsafeContinuation<Value, Never>) {
        os_unfair_lock_lock(&lock)
        self.continuation = continuation
        os_unfair_lock_unlock(&lock)
    }

    @discardableResult
    func resolve(_ value: Value) -> Bool {
        os_unfair_lock_lock(&lock)
        guard !resolved else {
            os_unfair_lock_unlock(&lock)
            return false
        }
        resolved = true
        let continuation = self.continuation
        self.continuation = nil
        os_unfair_lock_unlock(&lock)
        continuation?.resume(returning: value)
        return true
    }
}

private let blockingDirectoryOpenQueue = DispatchQueue(
    label: "com.lexcleaner.disk-analysis.directory-open",
    // Directory opens are part of the foreground scan critical path. Keep
    // them off the cooperative executor, but do not let utility QoS add
    // avoidable scheduling latency before the bounded watchdog can resolve.
    qos: .userInitiated,
    attributes: .concurrent
)

private final class DirectoryOpenWatchdog: @unchecked Sendable {
    private struct Request {
        let deadline: UInt64
        let resolver: OneShotResolver<DirectoryOpenResult>
    }

    private var lock = os_unfair_lock_s()
    private var nextID: UInt64 = 0
    private var requests: [UInt64: Request] = [:]
    private let timer: DispatchSourceTimer

    init() {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(1), repeating: .milliseconds(1), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.expire() }
        timer.resume()
    }

    func register(_ resolver: OneShotResolver<DirectoryOpenResult>, timeoutNanoseconds: UInt64) -> UInt64 {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        nextID &+= 1
        let id = nextID
        requests[id] = Request(deadline: DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds, resolver: resolver)
        return id
    }

    private func expire() {
        let now = DispatchTime.now().uptimeNanoseconds
        os_unfair_lock_lock(&lock)
        let expired = requests.filter { $0.value.deadline <= now }
        for id in expired.keys { requests.removeValue(forKey: id) }
        os_unfair_lock_unlock(&lock)
        for request in expired.values { _ = request.resolver.resolve(.timedOut) }
    }
}

private let directoryOpenWatchdog = DirectoryOpenWatchdog()

// A local directory open should complete well below this bound. A protected,
// network-backed, or otherwise unhealthy mount must not hold the whole scan
// behind a multi-second system call; it is skipped fail-safe instead.
private func openDirectoryWithTimeout(
    path: String,
    timeoutNanoseconds: UInt64 = 100_000_000,
    opener: @escaping DiskDirectoryOpenHandler
) async -> DirectoryOpenResult {
    await withUnsafeContinuation { (continuation: UnsafeContinuation<DirectoryOpenResult, Never>) in
        let resolver = OneShotResolver<DirectoryOpenResult>()
        resolver.install(continuation)
        _ = directoryOpenWatchdog.register(resolver, timeoutNanoseconds: timeoutNanoseconds)
        // POSIX open can block in the filesystem. Keep it off Swift
        // Concurrency's cooperative executor so a group of slow directories
        // cannot starve the watchdog or the rest of the scan.
        blockingDirectoryOpenQueue.async {
            let attempt = opener(path)
            if attempt.fileDescriptor >= 0 {
                if resolver.resolve(.opened(attempt.fileDescriptor)) {
                } else {
                    close(attempt.fileDescriptor)
                }
            } else {
                if resolver.resolve(.failed(attempt.errorNumber)) {
                }
            }
        }
    }
}

private func directoryIdentityMatches(fd: Int32, expected: DiskFileIdentity) -> Bool {
    var info = stat()
    guard fstat(fd, &info) == 0 else { return false }
    return UInt64(info.st_dev) == expected.device && UInt64(info.st_ino) == expected.inode
}

private struct ConditionalIdentity {
    let identity: DiskFileIdentity
    let posixMode: UInt16
}

private func identityAt(parentFD: Int32, name: String) -> ConditionalIdentity? {
    var info = stat()
    let result = name.withCString { pointer in
        fstatat(parentFD, pointer, &info, AT_SYMLINK_NOFOLLOW)
    }
    guard result == 0 else { return nil }
    return ConditionalIdentity(
        identity: DiskFileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)),
        posixMode: UInt16(info.st_mode & 0o7777)
    )
}

private struct AttributeBufferReader {
    let base: UnsafeRawPointer
    let length: Int
    var offset: Int

    init(base: UnsafeRawPointer, length: Int) {
        self.base = base
        self.length = length
        self.offset = MemoryLayout<UInt32>.size
    }

    mutating func read<T>(_ type: T.Type) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= length else { return nil }
        let value = base.advanced(by: offset).loadUnaligned(as: T.self)
        offset += MemoryLayout<T>.size
        return value
    }

    mutating func readStringReference() -> String? {
        let referenceOffset = alignedOffset(for: MemoryLayout<attrreference_t>.self)
        guard let reference: attrreference_t = read(attrreference_t.self) else { return nil }
        let dataOffset = referenceOffset + Int(reference.attr_dataoffset)
        let dataLength = Int(reference.attr_length)
        guard dataOffset >= 0, dataLength > 0, dataOffset + dataLength <= length else { return nil }
        let bytes = UnsafeRawBufferPointer(start: base.advanced(by: dataOffset), count: dataLength)
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }

    private func alignedOffset<T>(for type: T.Type) -> Int {
        offset
    }
}

private func readBulkDirectoryEntries(
    fd: Int32,
    buffer: BulkDirectoryBuffer,
    entries: inout [DiskFileRecord]
) -> Int32? {
    entries.removeAll(keepingCapacity: true)
    var attributes = attrlist()
    attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    let commonAttributes: attrgroup_t = UInt32(ATTR_CMN_RETURNED_ATTRS)
        | UInt32(ATTR_CMN_NAME)
        | UInt32(ATTR_CMN_DEVID)
        | UInt32(ATTR_CMN_OBJTYPE)
        | UInt32(ATTR_CMN_MODTIME)
        | UInt32(ATTR_CMN_ERROR)
    attributes.commonattr = commonAttributes
    attributes.fileattr = UInt32(ATTR_FILE_TOTALSIZE) | UInt32(ATTR_FILE_ALLOCSIZE) | UInt32(ATTR_FILE_LINKCOUNT)

    // The buffer is reused for every batch and never retained by the result.
    let result = buffer.bytes.withUnsafeMutableBytes { rawBuffer -> Int in
        guard let base = rawBuffer.baseAddress else { return -1 }
        return Int(getattrlistbulk(fd, &attributes, base, rawBuffer.count, 0))
    }
    guard result > 0 else { return result < 0 ? errno : nil }
    if entries.capacity < result { entries.reserveCapacity(min(result, 2048)) }
    buffer.bytes.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return }
        var offset = 0
        for _ in 0..<result {
            guard offset + MemoryLayout<UInt32>.size <= rawBuffer.count else { break }
            let groupStart = base.advanced(by: offset)
            let groupLength = Int(groupStart.loadUnaligned(as: UInt32.self))
            guard groupLength >= MemoryLayout<UInt32>.size, offset + groupLength <= rawBuffer.count else { break }
            var reader = AttributeBufferReader(base: groupStart, length: groupLength)
            guard let returned = reader.read(attribute_set_t.self) else { break }
            var entryError: UInt32 = 0
            if returned.commonattr & UInt32(ATTR_CMN_ERROR) != 0 {
                entryError = reader.read(UInt32.self) ?? UInt32(EIO)
            }
            let name = returned.commonattr & UInt32(ATTR_CMN_NAME) != 0 ? reader.readStringReference() : nil
            var device: UInt64?
            if returned.commonattr & UInt32(ATTR_CMN_DEVID) != 0 { device = UInt64(reader.read(dev_t.self) ?? 0) }
            var objectType: fsobj_type_t?
            if returned.commonattr & UInt32(ATTR_CMN_OBJTYPE) != 0 { objectType = reader.read(fsobj_type_t.self) }
            var modification: DiskTimestamp?
            if returned.commonattr & UInt32(ATTR_CMN_MODTIME) != 0, let time = reader.read(timespec.self) {
                modification = DiskTimestamp(seconds: Int64(time.tv_sec), nanoseconds: Int32(time.tv_nsec))
            }
            // Permission bits are only needed for directories. They are
            // recovered by the conditional fstatat used before queueing a
            // directory; regular files never enter the permission path.
            let mode: UInt16 = 0o700
            var logicalSize: UInt64 = 0
            var allocatedSize: UInt64 = 0
            var linkCount: UInt32 = 1
            if returned.fileattr & UInt32(ATTR_FILE_LINKCOUNT) != 0 { linkCount = reader.read(UInt32.self) ?? 1 }
            if returned.fileattr & UInt32(ATTR_FILE_TOTALSIZE) != 0 { logicalSize = UInt64(max(0, reader.read(off_t.self) ?? 0)) }
            if returned.fileattr & UInt32(ATTR_FILE_ALLOCSIZE) != 0 { allocatedSize = UInt64(max(0, reader.read(off_t.self) ?? 0)) }

            if let name, entryError == 0, let objectType {
                let category: FileCategory
                switch objectType {
                case UInt32(VREG.rawValue): category = .regularFile
                case UInt32(VDIR.rawValue): category = .directory
                case UInt32(VLNK.rawValue): category = .symbolicLink
                default: category = .other
                }
                entries.append(DiskFileRecord(
                    fileName: name,
                    canonicalPath: nil,
                    metadata: DiskMetadata(
                        category: category,
                        sizeBytes: logicalSize,
                        allocatedSizeBytes: allocatedSize,
                        lastModified: modification,
                        posixMode: mode,
                        // Keep the device for the volume boundary check. The
                        // inode is acquired only for conditional identity
                        // cases in enumerateDirectory.
                        identity: device.map { DiskFileIdentity(device: $0, inode: 0) },
                        linkCount: linkCount
                    )
                ))
            }
            offset += groupLength
        }
    }
    return nil
}

private func canonicalURL(_ url: URL) -> URL? {
    guard let resolved = realpath(url.path, nil) else { return nil }
    defer { free(resolved) }
    // POSIX realpath has already removed `.`/`..` and duplicate separators.
    // Keep the mandatory realpath identity check, but avoid normalizing the
    // resulting path a second time through Foundation.
    return URL(fileURLWithPath: String(cString: resolved), isDirectory: false)
}

private func diskVolumeContext(at url: URL, device: UInt64?) -> DiskVolumeContext? {
    var info = statfs()
    guard statfs(url.path, &info) == 0 else { return nil }
    let filesystemNameCapacity = MemoryLayout.size(ofValue: info.f_fstypename)
    let filesystemName = withUnsafePointer(to: &info.f_fstypename) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: filesystemNameCapacity) {
            String(cString: $0)
        }
    }
    let capacity = UInt64(info.f_blocks) &* UInt64(info.f_bsize)
    return DiskVolumeContext(
        device: device ?? UInt64(info.f_fsid.val.0),
        capacityBytes: capacity > 0 ? capacity : nil,
        filesystemName: filesystemName
    )
}

private func pathIsWithin(_ candidate: URL, root: URL) -> Bool {
    // All callers pass either canonicalURL output or URLs built beneath an
    // already-normalized parent. Avoid re-normalizing on every entry while
    // retaining the component-boundary check that prevents prefix escapes.
    let candidatePath = candidate.path
    let rootPath = root.path
    return candidatePath == rootPath || candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
}

private func pathDepth(_ url: URL) -> Int { url.path.split(separator: "/").count }

private func isPermissionErrno(_ value: Int32) -> Bool {
    value == EACCES || value == EPERM
}

private struct ResourceUsage: Sendable {
    let residentMemory: UInt64
    let cpuTime: TimeInterval
}

private func resourceUsage() -> ResourceUsage {
    var info = proc_taskallinfo()
    let infoSize = Int32(MemoryLayout<proc_taskallinfo>.size)
    let resident = proc_pidinfo(getpid(), PROC_PIDTASKALLINFO, 0, &info, infoSize) == infoSize ? info.ptinfo.pti_resident_size : 0
    var usage = rusage()
    let result = getrusage(RUSAGE_SELF, &usage)
    let cpu: TimeInterval
    if result == 0 {
        cpu = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000 + TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
    } else {
        cpu = 0
    }
    return ResourceUsage(residentMemory: resident, cpuTime: cpu)
}
