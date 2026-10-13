import SwiftUI

struct SettingsView: View {
    let viewModel: ViewModel
    @State var appearance = "Automatique"
    @State var showingProfile = false
    @State var showingLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TelegrapheTheme.spaceL) {
                    Text("Réglages").font(.largeTitle.weight(.bold)).foregroundStyle(TelegrapheTheme.primaryText)
                    Button { showingProfile = true } label: {
                        HStack(spacing: TelegrapheTheme.spaceM) {
                            AvatarView(name: "Mon profil", size: .large)
                            VStack(alignment: .leading, spacing: TelegrapheTheme.spaceXS) {
                                Text("Mon profil").font(.headline.weight(.semibold))
                                Text("Modifier mon profil").foregroundStyle(TelegrapheTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(TelegrapheTheme.secondaryText)
                        }
                        .padding(TelegrapheTheme.spaceL)
                        .background(TelegrapheTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                    SectionHeader(title: "Préférences")
                    settingsCard {
                        SettingsRow(title: "Notifications", symbol: "bell.fill")
                        Divider()
                        SettingsRow(title: "Apparence", symbol: "paintbrush.fill", tint: TelegrapheTheme.avatarPalette[2])
                    }
                    SectionHeader(title: "Confidentialité")
                    settingsCard {
                        SettingsRow(title: "Confidentialité", symbol: "lock.fill", tint: TelegrapheTheme.avatarPalette[3])
                        Divider()
                        SettingsRow(title: "Stockage et données", symbol: "externaldrive.fill", tint: TelegrapheTheme.avatarPalette[4])
                    }
                    settingsCard { SettingsRow(title: "À propos de Telegraphe", symbol: "info.circle.fill", tint: TelegrapheTheme.secondaryText) }
                    Button { showingLogoutConfirmation = true } label: {
                        SettingsRow(title: "Se déconnecter", symbol: "rectangle.portrait.and.arrow.right", tint: TelegrapheTheme.danger, textTint: TelegrapheTheme.danger)
                    }.buttonStyle(.plain).foregroundStyle(TelegrapheTheme.danger)
                    Text("Telegraphe • Version 1.0").font(.footnote).foregroundStyle(TelegrapheTheme.secondaryText)
                        .frame(maxWidth: .infinity).padding(.top, TelegrapheTheme.spaceS)
                }
                .padding(.horizontal, TelegrapheTheme.spaceL)
                .padding(.vertical, TelegrapheTheme.spaceL)
            }
            .background(TelegrapheTheme.background)
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .confirmationDialog("Se déconnecter ?", isPresented: $showingLogoutConfirmation) {
                Button("Se déconnecter", role: .destructive) { Task { await viewModel.logout() } }
                Button("Annuler", role: .cancel) { }
            }
        }
    }

    @ViewBuilder func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: TelegrapheTheme.spaceS) { content() }
            .padding(.horizontal, TelegrapheTheme.spaceL)
            .padding(.vertical, TelegrapheTheme.spaceS)
            .background(TelegrapheTheme.surface, in: RoundedRectangle(cornerRadius: 24))
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
