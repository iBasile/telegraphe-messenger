import Foundation

public enum MediaKind: String, Codable, Sendable {
    case photo
    case video
}

public struct MediaAttachment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: MediaKind
    public let conversationID: String
    public let byteSize: Int64
    public let width: Int
    public let height: Int
    public let durationSeconds: Int?
    public let thumbnailData: Data?
    public var uploadProgress: Double
    public var status: MessageStatus

    public init(
        id: String,
        kind: MediaKind,
        conversationID: String,
        byteSize: Int64,
        width: Int,
        height: Int,
        durationSeconds: Int? = nil,
        thumbnailData: Data? = nil,
        uploadProgress: Double = 0,
        status: MessageStatus = .pending
    ) {
        self.id = id
        self.kind = kind
        self.conversationID = conversationID
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.thumbnailData = thumbnailData
        self.uploadProgress = uploadProgress
        self.status = status
    }
}

public struct MediaLimits: Sendable, Equatable {
    public let photoMaxBytes: Int64
    public let videoMaxBytes: Int64
    public let videoMaxDurationSeconds: Int

    public init(
        photoMaxBytes: Int64 = 10 * 1024 * 1024,
        videoMaxBytes: Int64 = 50 * 1024 * 1024,
        videoMaxDurationSeconds: Int = 60
    ) {
        self.photoMaxBytes = photoMaxBytes
        self.videoMaxBytes = videoMaxBytes
        self.videoMaxDurationSeconds = videoMaxDurationSeconds
    }

    public func validate(_ media: MediaAttachment) throws {
        let maximum = media.kind == .photo ? photoMaxBytes : videoMaxBytes
        guard media.byteSize <= maximum else { throw MediaError.sizeLimit }
        if media.kind == .video, (media.durationSeconds ?? 0) > videoMaxDurationSeconds {
            throw MediaError.durationLimit
        }
    }
}

public enum MediaError: Error, Equatable {
    case sizeLimit
    case durationLimit
    case unsupportedFormat
    case cancelled
    case cacheFull
}

public protocol MediaPicker: Sendable {
    func pick() async throws -> [MediaAttachment]
    func capture(kind: MediaKind) async throws -> MediaAttachment
}

public protocol MediaTransferClient: Sendable {
    func upload(
        _ media: MediaAttachment,
        data: AsyncThrowingStream<Data, Error>,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
    func download(mediaID: String) async throws -> URL
    func cancel(mediaID: String) async
}

public actor MediaCache {
    private let directory: URL
    private let byteLimit: Int64

    public init(directory: URL, byteLimit: Int64 = 512 * 1024 * 1024) {
        self.directory = directory
        self.byteLimit = byteLimit
    }

    public func cachedURL(for mediaID: String) -> URL? {
        let url = directory.appendingPathComponent(mediaID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func store(_ source: URL, mediaID: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(mediaID)
        if destination != source {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        }
        try evictIfNeeded(excluding: destination)
        return destination
    }

    private func evictIfNeeded(excluding: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey]
        )
        var total = try files.reduce(Int64(0)) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0)
        }
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where total > byteLimit && file != excluding {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
            try FileManager.default.removeItem(at: file)
            total -= size
        }
        if total > byteLimit { throw MediaError.cacheFull }
    }
}
