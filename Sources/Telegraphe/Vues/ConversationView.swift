import SwiftUI
import TelegrapheCore

struct ConversationView: View {
    let viewModel: ViewModel
    let conversation: Conversation
    @State var text = ""

    var conversationMessages: [Message] {
        let values = viewModel.messages.filter { $0.conversationID == conversation.id }
        return values.isEmpty && conversation.id == "example-alice" ? ExampleData.messages : values
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AvatarView(name: conversation.title, size: .small, isOnline: !conversation.isGroup)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title).font(.subheadline.weight(.semibold))
                    Text(conversation.isGroup ? "Groupe" : "En ligne")
                        .font(.caption).foregroundStyle(TelegrapheTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "video").foregroundStyle(TelegrapheTheme.accent)
                Image(systemName: "phone").foregroundStyle(TelegrapheTheme.accent)
            }
            .padding(.horizontal, TelegrapheTheme.spaceL)
            .padding(.vertical, 10)
            .background(TelegrapheTheme.elevatedSurface)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: TelegrapheTheme.spaceS) {
                        ForEach(conversationMessages) { message in
                            MessageBubble(message: message, isMine: message.senderUserID == "me").id(message.id)
                        }
                    }
                    .padding(.horizontal, TelegrapheTheme.spaceL)
                    .padding(.vertical, TelegrapheTheme.spaceM)
                }
                .onAppear { viewModel.openConversation(conversation) }
                .onChange(of: conversationMessages.last?.id) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: TelegrapheTheme.spaceS) {
                Button { } label: {
                    Image(systemName: "paperclip").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("Ajouter une photo ou une vidéo")
                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(4).roundedField()
                Button {
                    viewModel.send(text: text, to: conversation, senderID: "me")
                    text = ""
                } label: {
                    Image(systemName: "arrow.up").font(.headline.weight(.bold)).foregroundStyle(TelegrapheTheme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(TelegrapheTheme.accentDeep, in: Circle())
                        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Envoyer le message")
            }
            .padding(TelegrapheTheme.spaceS)
            .background(TelegrapheTheme.surface)
        }
        .background(TelegrapheTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
