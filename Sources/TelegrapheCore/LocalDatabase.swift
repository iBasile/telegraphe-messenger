import Foundation
import SkipSQLCore
import SkipSQL

public enum MessageStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case sent
    case delivered
    case read
    case failed
}

public enum GroupRole: String, Sendable {
    case admin
    case member
}

public enum SystemEventKind: String, Sendable {
    case memberAdded
    case memberRemoved
    case nameChanged
    case memberPromoted
}

public struct SystemEvent: Equatable, Sendable {
    public let kind: SystemEventKind
    public let actorUserID: String
    public let subjectUserID: String?
    public let text: String
    public init(kind: SystemEventKind, actorUserID: String, subjectUserID: String? = nil, text: String) {
        self.kind = kind
        self.actorUserID = actorUserID
        self.subjectUserID = subjectUserID
        self.text = text
    }
}

public struct User: Identifiable, Equatable, Sendable {
    public let id: String
    public let email: String
    public let username: String
    public let displayName: String
    public init(id: String, email: String, username: String, displayName: String) {
        self.id = id
        self.email = email
        self.username = username
        self.displayName = displayName
    }
}

public struct Conversation: Identifiable, Equatable, Sendable {
    public let id: String
    public let otherUserID: String
    public let title: String
    public let lastMessage: String?
    public let isGroup: Bool
    public let groupRole: GroupRole?
    public init(id: String, otherUserID: String, title: String, lastMessage: String?, isGroup: Bool = false, groupRole: GroupRole? = nil) {
        self.id = id
        self.otherUserID = otherUserID
        self.title = title
        self.lastMessage = lastMessage
        self.isGroup = isGroup
        self.groupRole = groupRole
    }
}

public struct Message: Identifiable, Equatable, Sendable {
    public let id: String
    public let conversationID: String
    public let senderUserID: String
    public let text: String
    public let timestamp: Int64
    public let status: MessageStatus
    public let deliveryCount: Int
    public let readCount: Int
    public init(id: String, conversationID: String, senderUserID: String, text: String, timestamp: Int64, status: MessageStatus, deliveryCount: Int = 0, readCount: Int = 0) {
        self.id = id
        self.conversationID = conversationID
        self.senderUserID = senderUserID
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.deliveryCount = deliveryCount
        self.readCount = readCount
    }
}

public struct DatabaseItem: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String
    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}

public final class LocalDatabase {
    private let context: SQLContext
    public private(set) var fullTextSearchAvailable = false

    public init() {
        context = SQLContext(configuration: .platform)
    }

    public init(path: String) throws {
        context = try SQLContext(path: path, configuration: .platform)
    }

    public static func applicationData() throws -> LocalDatabase {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let path = directory.appendingPathComponent("telegraphe.sqlite").path
        print("[Telegraphe][SQLite] database path: \(path)")
        return try LocalDatabase(path: path)
    }

    deinit { try? context.close() }

    public func migrate() throws {
        try executeMigration(sql: "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY NOT NULL)")
        let version = try context.selectAll(sql: "SELECT COALESCE(MAX(version), 0) FROM schema_migrations").first?.first?.longValue ?? 0

        if version < 1 {
            try context.transaction {
                for sql in [
                    "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, created_at INTEGER NOT NULL)",
                    "CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, other_user_id TEXT NOT NULL, title TEXT NOT NULL, is_group INTEGER NOT NULL DEFAULT 0, group_role TEXT, created_at INTEGER NOT NULL)",
                    "CREATE TABLE IF NOT EXISTS conversation_members (conversation_id TEXT NOT NULL, user_id TEXT NOT NULL, role TEXT NOT NULL, PRIMARY KEY (conversation_id, user_id))",
                    "CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, sender_user_id TEXT NOT NULL, text TEXT NOT NULL, timestamp INTEGER NOT NULL, status TEXT NOT NULL, FOREIGN KEY (conversation_id) REFERENCES conversations(id))",
                    "CREATE TABLE IF NOT EXISTS outbox (message_id TEXT PRIMARY KEY, attempts INTEGER NOT NULL DEFAULT 0, next_attempt_at INTEGER NOT NULL, last_error TEXT)",
                    "CREATE TABLE IF NOT EXISTS media_attachments (message_id TEXT PRIMARY KEY, media_id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, byte_size INTEGER NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, duration_seconds INTEGER, thumbnail_data TEXT, upload_progress INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE)",
                    "CREATE TABLE IF NOT EXISTS sync_cursor (device_id TEXT PRIMARY KEY, cursor INTEGER NOT NULL DEFAULT 0)",
                    "CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, title TEXT NOT NULL)",
                    "INSERT INTO schema_migrations(version) VALUES (1)",
                ] {
                    try executeMigration(sql: sql)
                }
            }
        }

        if version < 2 {
            do {
                try context.transaction {
                    try executeMigration(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(text, content='messages', content_rowid='rowid')")
                    try executeMigration(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(title, content='items', content_rowid='id')")
                    try executeMigration(sql: "INSERT INTO items_fts(rowid, title) SELECT id, title FROM items WHERE id NOT IN (SELECT rowid FROM items_fts)")
                    try executeMigration(sql: "INSERT INTO schema_migrations(version) VALUES (2)")
                }
            } catch {
                print("[Telegraphe][SQLite] FTS5 indisponible, repli LIKE: \(error.localizedDescription)")
                try executeMigration(sql: "INSERT OR IGNORE INTO schema_migrations(version) VALUES (2)")
            }
        }

        fullTextSearchAvailable = (try? context.selectAll(
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('messages_fts','items_fts')"
        ).first?.first?.longValue) == 2
    }

    private func executeMigration(sql: String) throws {
        print("[Telegraphe][SQLite] migration SQL: \(sql)")
        do {
            try context.exec(sql: sql)
        } catch {
            print("[Telegraphe][SQLite] migration error for SQL \(sql): \(error.localizedDescription)")
            throw error
        }
    }

    public func upsertUser(_ user: User) throws {
        try context.exec(sql: """
            INSERT INTO users (id,email,username,display_name,created_at) VALUES (?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET email=excluded.email, username=excluded.username, display_name=excluded.display_name
            """, parameters: [.text(user.id), .text(user.email), .text(user.username), .text(user.displayName), .integer(databaseNow())])
    }

    public func upsertConversation(_ conversation: Conversation) throws {
        try context.exec(sql: """
            INSERT INTO conversations (id,other_user_id,title,created_at) VALUES (?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET title=excluded.title
            """, parameters: [.text(conversation.id), .text(conversation.otherUserID), .text(conversation.title), .integer(databaseNow())])
    }

    @discardableResult
    public func enqueueMessage(conversationID: String, senderUserID: String, text: String, id: String? = nil) throws -> Message {
        let timestamp = databaseNow()
        let id = id ?? UUIDv7.generate()
        try context.exec(sql: "INSERT INTO messages (id,conversation_id,sender_user_id,text,timestamp,status) VALUES (?,?,?,?,?,?)",
                         parameters: [.text(id), .text(conversationID), .text(senderUserID), .text(text), .integer(timestamp), .text(MessageStatus.pending.rawValue)])
        try context.exec(sql: "INSERT INTO outbox (message_id,attempts,next_attempt_at) VALUES (?,?,?)",
                         parameters: [.text(id), .integer(0), .integer(timestamp)])
        if fullTextSearchAvailable {
            try context.exec(sql: "INSERT INTO messages_fts(rowid,text) SELECT rowid,text FROM messages WHERE id=?",
                             parameters: [.text(id)])
        }
        return Message(id: id, conversationID: conversationID, senderUserID: senderUserID, text: text, timestamp: timestamp, status: .pending)
    }

    @discardableResult
    public func insertIncomingMessage(
        id: String,
        conversationID: String,
        senderUserID: String,
        text: String,
        timestamp: Int64
    ) throws -> Bool {
        let existed = !(try context.selectAll(
            sql: "SELECT id FROM messages WHERE id=?",
            parameters: [.text(id)]
        ).isEmpty)
        try context.exec(
            sql: """
                INSERT OR IGNORE INTO messages
                (id,conversation_id,sender_user_id,text,timestamp,status)
                VALUES (?,?,?,?,?,'delivered')
                """,
            parameters: [
                .text(id), .text(conversationID), .text(senderUserID),
                .text(text), .integer(timestamp),
            ]
        )
        let inserted = !existed
        if inserted, fullTextSearchAvailable {
            try context.exec(
                sql: "INSERT INTO messages_fts(rowid,text) SELECT rowid,text FROM messages WHERE id=? AND rowid NOT IN (SELECT rowid FROM messages_fts)",
                parameters: [.text(id)]
            )
        }
        return inserted
    }

    public func recordSystemEvent(conversationID: String, event: SystemEvent, id: String? = nil) throws -> Message {
        let messageID = id ?? UUIDv7.generate()
        let timestamp = databaseNow()
        try context.exec(sql: "INSERT INTO messages (id,conversation_id,sender_user_id,text,timestamp,status) VALUES (?,?,?,?,?,?)",
                         parameters: [.text(messageID), .text(conversationID), .text(event.actorUserID), .text(event.text), .integer(timestamp), .text(MessageStatus.read.rawValue)])
        if fullTextSearchAvailable {
            try context.exec(sql: "INSERT INTO messages_fts(rowid,text) SELECT rowid,text FROM messages WHERE id=?", parameters: [.text(messageID)])
        }
        return Message(id: messageID, conversationID: conversationID, senderUserID: event.actorUserID, text: event.text, timestamp: timestamp, status: .read)
    }

    @discardableResult
    public func enqueueMedia(
        conversationID: String,
        senderUserID: String,
        media: MediaAttachment,
        id: String? = nil
    ) throws -> Message {
        let timestamp = databaseNow()
        let messageID = id ?? UUIDv7.generate()
        try context.exec(
            sql: "INSERT INTO messages (id,conversation_id,sender_user_id,text,timestamp,status) VALUES (?,?,?,?,?,?)",
            parameters: [.text(messageID), .text(conversationID), .text(senderUserID), .text(""), .integer(timestamp), .text(MessageStatus.pending.rawValue)]
        )
        try context.exec(
            sql: """
                INSERT INTO media_attachments
                (message_id,media_id,kind,byte_size,width,height,duration_seconds,thumbnail_data)
                VALUES (?,?,?,?,?,?,?,?)
                """,
            parameters: [
                .text(messageID), .text(media.id), .text(media.kind.rawValue), .integer(media.byteSize),
                .integer(Int64(media.width)), .integer(Int64(media.height)),
                media.durationSeconds.map { .integer(Int64($0)) } ?? .null,
                media.thumbnailData.map { .text($0.base64EncodedString()) } ?? .null,
            ]
        )
        try context.exec(sql: "INSERT INTO outbox (message_id,attempts,next_attempt_at) VALUES (?,?,?)",
                         parameters: [.text(messageID), .integer(0), .integer(timestamp)])
        return Message(id: messageID, conversationID: conversationID, senderUserID: senderUserID, text: "", timestamp: timestamp, status: .pending)
    }

    public func mediaAttachment(messageID: String) throws -> MediaAttachment? {
        try context.selectAll(
            sql: """
                SELECT media_id,kind,conversation_id,byte_size,width,height,duration_seconds,thumbnail_data,
                       m.status
                FROM media_attachments a JOIN messages m ON m.id=a.message_id
                WHERE a.message_id=?
                """,
            parameters: [.text(messageID)]
        ).compactMap { (row: [SQLValue]) -> MediaAttachment? in
            guard row.count == 9, let id = row[0].textValue, let rawKind = row[1].textValue,
                  let kind = MediaKind(rawValue: rawKind), let conversationID = row[2].textValue,
                  let byteSize = row[3].longValue, let width = row[4].longValue,
                  let height = row[5].longValue, let rawStatus = row[8].textValue,
                  let status = MessageStatus(rawValue: rawStatus) else { return nil }
            return MediaAttachment(id: id, kind: kind, conversationID: conversationID, byteSize: byteSize,
                                   width: Int(width), height: Int(height), durationSeconds: row[6].longValue.map(Int.init),
                                   thumbnailData: nil, status: status)
        }.first
    }

    public func updateMediaProgress(messageID: String, progress: Double) throws {
        try context.exec(sql: "UPDATE media_attachments SET upload_progress=? WHERE message_id=?",
                         parameters: [.integer(Int64(min(1, max(0, progress)) * 100)), .text(messageID)])
    }

    public func messages(in conversationID: String) throws -> [Message] {
        try context.selectAll(sql: "SELECT id,conversation_id,sender_user_id,text,timestamp,status FROM messages WHERE conversation_id=? ORDER BY timestamp",
                              parameters: [.text(conversationID)]).compactMap(Self.message)
    }

    public func conversation(id: String) throws -> Conversation? {
        try context.selectAll(
            sql: "SELECT id,other_user_id,title,is_group,group_role FROM conversations WHERE id=?",
            parameters: [.text(id)]
        ).compactMap { row -> Conversation? in
            guard row.count == 5, let id = row[0].textValue, let otherUserID = row[1].textValue,
                  let title = row[2].textValue, let isGroup = row[3].longValue else { return nil }
            return Conversation(
                id: id,
                otherUserID: otherUserID,
                title: title,
                lastMessage: nil,
                isGroup: isGroup != 0,
                groupRole: row[4].textValue.flatMap(GroupRole.init(rawValue:))
            )
        }.first
    }

    public func pendingOutbox(now: Int64? = nil) throws -> [Message] {
        let now = now ?? databaseNow()
        return try context.selectAll(sql: """
            SELECT m.id,m.conversation_id,m.sender_user_id,m.text,m.timestamp,m.status
            FROM messages m JOIN outbox o ON o.message_id=m.id
            WHERE o.next_attempt_at <= ? AND m.status IN ('pending','failed') ORDER BY m.timestamp
            """, parameters: [.integer(now)]).compactMap(Self.message)
    }

    public func updateMessageStatus(id: String, status: MessageStatus) throws {
        try context.exec(
            sql: """
                UPDATE messages SET status=?
                WHERE id=? AND CASE status
                  WHEN 'pending' THEN 0
                  WHEN 'sent' THEN 1
                  WHEN 'delivered' THEN 2
                  WHEN 'read' THEN 3
                  WHEN 'failed' THEN 0
                  ELSE 0 END <= CASE ?
                  WHEN 'pending' THEN 0
                  WHEN 'sent' THEN 1
                  WHEN 'delivered' THEN 2
                  WHEN 'read' THEN 3
                  WHEN 'failed' THEN 0
                  ELSE 0 END
                """,
            parameters: [.text(status.rawValue), .text(id), .text(status.rawValue)]
        )
        if status == .sent || status == .delivered || status == .read { try context.exec(sql: "DELETE FROM outbox WHERE message_id=?", parameters: [.text(id)]) }
    }

    public func recordRetry(id: String, now: Int64? = nil, error: String? = nil) throws {
        let now = now ?? databaseNow()
        try context.exec(sql: "UPDATE outbox SET attempts=attempts+1,next_attempt_at=?,last_error=? WHERE message_id=?",
                         parameters: [.integer(now + retryDelay(for: id)), error.map(SQLValue.text) ?? .null, .text(id)])
    }

    public func setCursor(deviceID: String, cursor: Int64) throws {
        try context.exec(sql: "INSERT INTO sync_cursor(device_id,cursor) VALUES(?,?) ON CONFLICT(device_id) DO UPDATE SET cursor=excluded.cursor",
                         parameters: [.text(deviceID), .integer(cursor)])
    }

    public func cursor(deviceID: String) throws -> Int64 {
        (try? context.selectAll(sql: "SELECT cursor FROM sync_cursor WHERE device_id=?", parameters: [.text(deviceID)]).first?[0].longValue) ?? 0
    }

    public func searchMessages(matching query: String) throws -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if fullTextSearchAvailable {
            let ftsQuery = sanitizeFTS5Query(trimmed)
            if !ftsQuery.isEmpty {
                do {
                    return try context.selectAll(sql: """
                    SELECT m.id,m.conversation_id,m.sender_user_id,m.text,m.timestamp,m.status
                    FROM messages_fts f JOIN messages m ON f.rowid=m.rowid WHERE f MATCH ? ORDER BY m.timestamp DESC
                    """, parameters: [.text(ftsQuery)]).compactMap(Self.message)
                } catch {
                    print("[Telegraphe][SQLite] FTS5 search failed, falling back to LIKE: \(error.localizedDescription)")
                }
            }
        }
        let escaped = trimmed.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        return try context.selectAll(
            sql: "SELECT id,conversation_id,sender_user_id,text,timestamp,status FROM messages WHERE text LIKE ? ESCAPE '\\' ORDER BY timestamp DESC",
            parameters: [.text("%\(escaped)%")]
        ).compactMap(Self.message)
    }

    // Kept for the starter sample and migration regression test.
    public func insertItem(title: String) throws {
        try context.exec(sql: "INSERT INTO items(title) VALUES (?)", parameters: [.text(title)])
        if fullTextSearchAvailable {
            try context.exec(sql: "INSERT INTO items_fts(rowid,title) VALUES(last_insert_rowid(),?)", parameters: [.text(title)])
        }
    }
    public func items() throws -> [DatabaseItem] {
        try context.selectAll(sql: "SELECT id,title FROM items ORDER BY id").compactMap { row in
            guard row.count == 2, let id = row[0].longValue, let title = row[1].textValue else { return nil }
            return DatabaseItem(id: id, title: title)
        }
    }
    public func searchItems(matching query: String) throws -> [DatabaseItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if fullTextSearchAvailable {
            let ftsQuery = sanitizeFTS5Query(trimmed)
            if !ftsQuery.isEmpty {
                do {
                    return try context.selectAll(
                        sql: "SELECT items.id,items.title FROM items_fts JOIN items ON items_fts.rowid=items.id WHERE items_fts MATCH ? ORDER BY items.id",
                        parameters: [.text(ftsQuery)]
                    ).compactMap { row in
                        guard let id = row[0].longValue, let title = row[1].textValue else { return nil }
                        return DatabaseItem(id: id, title: title)
                    }
                } catch {
                    print("[Telegraphe][SQLite] FTS5 searchItems failed, falling back to LIKE: \(error.localizedDescription)")
                }
            }
        }
        let escaped = trimmed.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        let rows = try context.selectAll(sql: "SELECT id,title FROM items WHERE title LIKE ? ESCAPE '\\' ORDER BY id", parameters: [.text("%\(escaped)%")])
        return rows.compactMap { row in
            guard let id = row[0].longValue, let title = row[1].textValue else { return nil }
            return DatabaseItem(id: id, title: title)
        }
    }

    private func sanitizeFTS5Query(_ query: String) -> String {
        let stripped = query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        let tokens = stripped.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return "" }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private static func message(_ row: [SQLValue]) -> Message? {
        guard row.count == 6, let id = row[0].textValue, let conversationID = row[1].textValue,
              let sender = row[2].textValue, let text = row[3].textValue, let timestamp = row[4].longValue,
              let rawStatus = row[5].textValue, let status = MessageStatus(rawValue: rawStatus) else { return nil }
        return Message(id: id, conversationID: conversationID, senderUserID: sender, text: text, timestamp: timestamp, status: status)
    }
    private func retryDelay(for id: String) -> Int64 {
        let attempts = (try? context.selectAll(sql: "SELECT attempts FROM outbox WHERE message_id=?", parameters: [.text(id)]).first?[0].longValue) ?? 0
        return min(300_000, Int64(1_000 * pow(2, Double(attempts))))
    }

    private func databaseNow() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

private enum UUIDv7 {
    static func generate() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 { bytes[index] = UInt8((timestamp >> UInt64((5 - index) * 8)) & 0xff) }
        for index in 6..<16 { bytes[index] = UInt8.random(in: 0...255) }
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return bytes.enumerated().map { index, byte in
            let value = String(format: "%02x", byte)
            return [4, 6, 8, 10].contains(index) ? "-" + value : value
        }.joined()
    }
}
