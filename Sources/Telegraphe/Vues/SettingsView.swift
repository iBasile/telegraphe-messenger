import SwiftUI

struct SettingsView: View {
    let viewModel: ViewModel
    @State var appearance = "Automatique"
    @State var showingProfile = false
    @State var showingLogoutConfirmation = false
    @State var showingAbout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showingProfile = true } label: {
                        HStack(spacing: 14) {
                            AvatarView(name: "Mon profil", size: .large)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Mon profil").font(.headline)
                                Text("Modifier mon profil").font(.subheadline).foregroundStyle(TelegrapheTheme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Préférences") {
                    Label("Notifications", systemImage: "bell.fill")
                    Label("Apparence", systemImage: "paintbrush.fill")
                }
                Section("Confidentialité") {
                    Label("Confidentialité", systemImage: "lock.fill")
                    Label("Stockage et données", systemImage: "externaldrive.fill")
                }
                Section {
                    Button {
                        showingAbout = true
                    } label: {
                        Label("À propos de Telegraphe", systemImage: "info.circle.fill")
                    }
                    Text("Version Bêta 0.0").font(.footnote).foregroundStyle(TelegrapheTheme.secondaryText)
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { showingLogoutConfirmation = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TelegrapheTheme.background)
            .tint(TelegrapheTheme.accent)
            .navigationTitle("Réglages")
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .sheet(isPresented: $showingAbout) {
                            AboutView()
                        }
            .confirmationDialog("Se déconnecter ?", isPresented: $showingLogoutConfirmation) {
                Button("Se déconnecter", role: .destructive) { Task { await viewModel.logout() } }
                Button("Annuler", role: .cancel) { }
            }
        }
    }
}

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    @State var displayName = "Mon profil"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AvatarView(name: displayName, size: .large).frame(maxWidth: .infinity)
                    Button("Modifier la photo") { }
                }
                Section("Informations") { TextField("Nom d’affichage", text: $displayName) }
            }
            .navigationTitle("Mon profil")
            .toolbar { ToolbarItem { Button("Fermer") { dismiss() } } }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.largeTitle)
                    .foregroundStyle(TelegrapheTheme.accent)
                Text("Telegraphe")
                    .font(.title2.weight(.semibold))
                Text("Télégraphe est une application de messagerie instantanée qui respecte la vie privée.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Développement : Basile BARGIBANT")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Hébergement : Basile GUERMONPREZ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Télégraphe fonctionne avec plusieurs librairies open-source. [En savoir plus...](https://double-b-studio.web.app/telegraphe/acknowledgements.html)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("À propos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
