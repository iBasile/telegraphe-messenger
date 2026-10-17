import SwiftUI
import TelegrapheCore

struct MessagesView: View {
    let viewModel: ViewModel
    @State var searchText = ""
    @State var showingNewMessage = false
    @State var filter = "Tout"

    var displayedConversations: [Conversation] {
        var values = viewModel.conversations.isEmpty ? ExampleData.conversations : viewModel.conversations
        if filter == "Groupes" { values = values.filter(\.isGroup) }
        if filter == "Non lus" { values = values.filter { $0.id == "example-family" } }
        guard !searchText.isEmpty else { return values }
        return values.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.lastMessage ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filtrer les discussions", selection: $filter) {
                    Text("Tout").tag("Tout")
                    Text("Non lus").tag("Non lus")
                    Text("Groupes").tag("Groupes")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TelegrapheTheme.spaceL)
                .padding(.top, TelegrapheTheme.spaceS)
                .padding(.bottom, TelegrapheTheme.spaceXS)
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
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Rechercher")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewMessage = true } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Nouvelle conversation")
                }
            }
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
