import SwiftUI
import TelegrapheCore

struct MessagesView: View {
    let viewModel: ViewModel
    @State var searchText = ""
    @State var showingNewMessage = false
    @State var filter = "Tout"

    var displayedConversations: [Conversation] {
        let values = viewModel.conversations.isEmpty ? ExampleData.conversations : viewModel.conversations
        guard !searchText.isEmpty else { return values }
        return values.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        NavigationStack {
            VStack(alignment: .leading, spacing: TelegrapheTheme.spaceM) {
                HStack {
                    Text("Messages").font(.largeTitle.weight(.bold)).foregroundStyle(TelegrapheTheme.primaryText)
                    Spacer()
                    Button { showingNewMessage = true } label: {
                        Image(systemName: "square.and.pencil").font(.title3.weight(.semibold))
                            .foregroundStyle(TelegrapheTheme.accentDeep).frame(width: 44, height: 44)
                            .background(TelegrapheTheme.surface, in: Circle())
                    }.accessibilityLabel("Nouveau message ou groupe")
                }
                .padding(.horizontal, TelegrapheTheme.spaceL)
                HStack(spacing: TelegrapheTheme.spaceS) {
                    FilterChip(title: "Tout", isSelected: filter == "Tout") { filter = "Tout" }
                    FilterChip(title: "Non lus", isSelected: filter == "Non lus") { filter = "Non lus" }
                    FilterChip(title: "Groupes", isSelected: filter == "Groupes") { filter = "Groupes" }
                }.padding(.horizontal, TelegrapheTheme.spaceL)
                List(displayedConversations) { conversation in
                    NavigationLink { ConversationView(viewModel: viewModel, conversation: conversation) } label: {
                        ConversationRow(conversation: conversation, unreadCount: conversation.id == "example-family" ? 2 : 0)
                    }
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        Button("Supprimer", role: .destructive) { }
                        Button("Silencieux") { }.tint(TelegrapheTheme.secondaryText)
                        Button("Épingler") { }.tint(TelegrapheTheme.accentDeep)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(TelegrapheTheme.background)
            .searchable(text: $searchText, prompt: "Rechercher")
            .sheet(isPresented: $showingNewMessage) { NewConversationView(viewModel: viewModel) }
            .sheet(isPresented: $bindableViewModel.showingGroupCreation) { GroupCreationView(viewModel: viewModel) }
            .sheet(item: $bindableViewModel.groupToAdminister) { conversation in GroupAdminView(conversation: conversation) }
        }
    }
}

struct NewConversationView: View {
    let viewModel: ViewModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                Button { dismiss() } label: { Label("Nouveau message", systemImage: "person.crop.circle.badge.plus") }
                Button { viewModel.beginGroupCreation(); dismiss() } label: { Label("Nouveau groupe", systemImage: "person.3") }
            }
            .navigationTitle("Nouveau")
            .toolbar { ToolbarItem { Button("Fermer") { dismiss() } } }
        }
    }
}
