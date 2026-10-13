import Foundation
import TelegrapheCore

enum ExampleData {
    // Données de présentation uniquement : elles disparaîtront dès que la synchronisation sera branchée.
    static let conversations: [Conversation] = [
        Conversation(id: "example-alice", otherUserID: "alice", title: "Alice Martin", lastMessage: "À bientôt !"),
        Conversation(id: "example-family", otherUserID: "", title: "Famille", lastMessage: "Le dîner est à 20 h", isGroup: true, groupRole: .member)
    ]

    static let messages: [Message] = [
        Message(id: "example-message-1", conversationID: "example-alice", senderUserID: "alice", text: "Bonjour ! Comment vas-tu ?", timestamp: 1_726_000_000, status: .read),
        Message(id: "example-message-2", conversationID: "example-alice", senderUserID: "me", text: "Très bien, merci. À bientôt !", timestamp: 1_726_000_600, status: .delivered)
    ]
}
