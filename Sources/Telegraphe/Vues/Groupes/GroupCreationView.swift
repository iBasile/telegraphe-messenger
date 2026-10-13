import SwiftUI

struct GroupCreationView: View {
    let viewModel: ViewModel
    @Environment(\.dismiss) var dismiss
    @State var name = ""
    @State var members = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations du groupe") {
                    TextField("Nom du groupe", text: $name)
                    TextField("Membres séparés par des virgules", text: $members)
                }
                Button("Créer le groupe") { dismiss() }
                    .orangeButton()
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Nouveau groupe")
            .toolbar { ToolbarItem { Button("Annuler") { dismiss() } } }
        }
    }
}
