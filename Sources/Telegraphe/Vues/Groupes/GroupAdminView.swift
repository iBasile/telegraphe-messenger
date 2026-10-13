import SwiftUI
import TelegrapheCore

struct GroupAdminView: View {
    let conversation: Conversation
    @Environment(\.dismiss) var dismiss
    @State var newName: String

    init(conversation: Conversation) {
        self.conversation = conversation
        _newName = State(initialValue: conversation.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Groupe") {
                    TextField("Nom du groupe", text: $newName)
                    Button("Modifier le nom") { }
                    Button("Ajouter un membre") { }
                }
                Section("Membres") {
                    Text("Les membres et leurs rôles sont gérés par le serveur.")
                        .foregroundStyle(.secondary)
                }
                Button("Quitter le groupe", role: .destructive) { dismiss() }
            }
            .navigationTitle("Administration")
            .toolbar { ToolbarItem { Button("Fermer") { dismiss() } } }
        }
    }
}
