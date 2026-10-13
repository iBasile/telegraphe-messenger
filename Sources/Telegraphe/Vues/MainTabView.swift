import SwiftUI

struct MainTabView: View {
    let viewModel: ViewModel

    var body: some View {
        TabView {
            MessagesView(viewModel: viewModel)
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                .badge(2)
            ContactsPlaceholderView()
                .tabItem { Label("Contacts", systemImage: "person.2") }
            CallsView()
                .tabItem { Label("Appels", systemImage: "phone") }
            SettingsView(viewModel: viewModel)
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .tint(TelegrapheTheme.accent)
    }
}

struct ContactsPlaceholderView: View {
    let contacts = ["Adrien Bernard", "Alice Martin", "Avengers", "Basile Bargibant"]
    @State var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Button { } label: {
                    Label("Inviter des amis", systemImage: "person.badge.plus")
                        .foregroundStyle(TelegrapheTheme.accentDeep)
                }
                ForEach(filteredContacts, id: \.self) { contact in
                    HStack(spacing: TelegrapheTheme.spaceM) {
                        AvatarView(name: contact, size: .medium)
                        Text(contact).font(.headline.weight(.semibold))
                    }
                    .padding(.vertical, TelegrapheTheme.spaceXS)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TelegrapheTheme.background)
            .searchable(text: $searchText, prompt: "Rechercher")
            .navigationTitle("Contacts")
        }
    }

    var filteredContacts: [String] {
        guard !searchText.isEmpty else { return contacts }
        return contacts.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
}
