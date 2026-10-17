import Testing
import TelegrapheCore

@Test
func databaseMigrationsPersistenceAndFullTextSearch() throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.migrate()
    try database.insertItem(title: "Première ligne")
    try database.insertItem(title: "Autre contenu")

    #expect(try database.items().map(\.title) == ["Première ligne", "Autre contenu"])
    #expect(try database.searchItems(matching: "Première").map(\.title) == ["Première ligne"])
}

@Test
func outboxAndMessageStateMachine() throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "conversation", otherUserID: "other", title: "Test", lastMessage: nil))
    let message = try database.enqueueMessage(conversationID: "conversation", senderUserID: "me", text: "Bonjour", id: "message")

    #expect(message.status == .pending)
    #expect(try database.pendingOutbox(now: message.timestamp).map(\.id) == ["message"])
    try database.updateMessageStatus(id: "message", status: .sent)
    #expect(try database.pendingOutbox(now: message.timestamp).isEmpty)
    try database.updateMessageStatus(id: "message", status: .delivered)
    try database.updateMessageStatus(id: "message", status: .read)
    #expect(try database.messages(in: "conversation").first?.status == .read)
}

@Test
func cursorKeepsTheMostRecentMailboxPosition() throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.setCursor(deviceID: "device", cursor: 12)
    try database.setCursor(deviceID: "device", cursor: 23)
    #expect(try database.cursor(deviceID: "device") == 23)
}

@Test
func incomingMessagesAreIdempotent() throws {
    let database = LocalDatabase()
    try database.migrate()
    let first = try database.insertIncomingMessage(
        id: "incoming",
        conversationID: "conversation",
        senderUserID: "other",
        text: "Bonjour",
        timestamp: 10
    )
    let duplicate = try database.insertIncomingMessage(
        id: "incoming",
        conversationID: "conversation",
        senderUserID: "other",
        text: "Bonjour",
        timestamp: 10
    )
    #expect(first)
    #expect(!duplicate)
    #expect(try database.messages(in: "conversation").count == 1)
}

@Test
func systemEventsAreStoredAsConversationMessages() throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "group", otherUserID: "", title: "Équipe", lastMessage: nil, isGroup: true, groupRole: .admin))
    _ = try database.recordSystemEvent(
        conversationID: "group",
        event: .init(kind: .memberAdded, actorUserID: "admin", subjectUserID: "member", text: "Un membre a été ajouté"),
        id: "event",
    )
    #expect(try database.messages(in: "group").first?.text == "Un membre a été ajouté")
    #expect(try database.messages(in: "group").first?.status == .read)
}

@Test
func mediaOutboxStoresMetadataAndEnforcesLimits() throws {
    let database = LocalDatabase()
    try database.migrate()
    try database.upsertConversation(.init(id: "media-group", otherUserID: "", title: "Médias", lastMessage: nil, isGroup: true))
    let media = MediaAttachment(
        id: "media-id",
        kind: .photo,
        conversationID: "media-group",
        byteSize: 512,
        width: 640,
        height: 480
    )
    try MediaLimits(photoMaxBytes: 1_024).validate(media)
    let message = try database.enqueueMedia(
        conversationID: "media-group",
        senderUserID: "me",
        media: media,
        id: "media-message"
    )
    #expect(message.status == .pending)
    #expect(try database.mediaAttachment(messageID: message.id)?.id == "media-id")
    #expect(try database.pendingOutbox(now: message.timestamp).map(\.id) == ["media-message"])
    #expect(throws: MediaError.sizeLimit) {
        try MediaLimits(photoMaxBytes: 1).validate(media)
    }
}
