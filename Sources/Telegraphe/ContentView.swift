import SwiftUI

struct ContentView: View {
    @State var viewModel = ViewModel()

    var body: some View {
        Group {
            if viewModel.database == nil {
                DatabaseUnavailableView(viewModel: viewModel)
            } else if viewModel.isAuthLoading && viewModel.sessionState == .signedOut {
                ProgressView("Restauration de la session…")
            } else if viewModel.sessionState == .signedIn {
                MainTabView(viewModel: viewModel)
            } else {
                LoginView(viewModel: viewModel)
            }
        }
        .tint(TelegrapheTheme.accent)
        .task { await viewModel.restoreSession() }
    }
}

struct DatabaseUnavailableView: View {
    let viewModel: ViewModel

    var body: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 36))
                .foregroundStyle(TelegrapheTheme.accent)
            Text("Base locale indisponible").font(.title3.weight(.semibold))
            Text(viewModel.errorMessage ?? "La base locale n’a pas pu être ouverte.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Réessayer") { viewModel.retryDatabase() }
                .orangeButton()
        }
        .padding(TelegrapheTheme.spaceXL)
    }
}
