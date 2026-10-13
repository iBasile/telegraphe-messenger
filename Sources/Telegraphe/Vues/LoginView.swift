import SwiftUI

struct LoginView: View {
    let viewModel: ViewModel
    @State var mode: LoginMode = .login

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                LinearGradient(colors: [TelegrapheTheme.accent, TelegrapheTheme.accentDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: TelegrapheTheme.spaceXL) {
                        VStack(spacing: TelegrapheTheme.spaceS) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(TelegrapheTheme.onAccent)
                                .frame(width: 80, height: 80)
                                .background(TelegrapheTheme.onAccent.opacity(0.18), in: RoundedRectangle(cornerRadius: 24))
                            Text("Telegraphe").font(.largeTitle.weight(.bold)).foregroundStyle(TelegrapheTheme.onAccent)
                            Text(mode == .login ? "Connectez-vous pour continuer" : "Créez votre compte")
                                .foregroundStyle(TelegrapheTheme.onAccent.opacity(0.88))
                        }
                        .padding(.top, TelegrapheTheme.spaceXXL)
                        authCard
                    }
                    .padding(.horizontal, TelegrapheTheme.spaceL)
                    .frame(minHeight: max(geometry.size.height - 20, 560))
                }
            }
        }
    }

    @ViewBuilder var authCard: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            switch mode {
            case .login: LoginForm(viewModel: viewModel, mode: $mode)
            case .register: RegisterForm(viewModel: viewModel, mode: $mode)
            case .forgot: ForgotPasswordForm(viewModel: viewModel, mode: $mode)
            case .verify: VerifyEmailForm(viewModel: viewModel, mode: $mode)
            }
        }
        .padding(TelegrapheTheme.spaceL)
        .background(TelegrapheTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: TelegrapheTheme.shadow, radius: 18, y: 8)
    }
}

enum LoginMode { case login, register, forgot, verify }

struct AuthErrorLabel: View {
    let message: String?
    var body: some View {
        if let message { Text(message).font(.footnote).foregroundStyle(TelegrapheTheme.danger).frame(maxWidth: .infinity, alignment: .leading) }
    }
}

struct AuthField: View {
    let symbol: String
    let title: String
    @Binding var text: String
    var isSecure = false
    @State var showingText = false
    var body: some View {
        HStack(spacing: TelegrapheTheme.spaceM) {
            Image(systemName: symbol).foregroundStyle(TelegrapheTheme.accent)
            if isSecure && !showingText { SecureField(title, text: $text) }
            else { TextField(title, text: $text) }
            if isSecure {
                Button { showingText.toggle() } label: {
                    Image(systemName: showingText ? "eye.slash" : "eye").foregroundStyle(TelegrapheTheme.secondaryText)
                }.buttonStyle(.plain)
            }
        }.roundedField()
    }
}

struct LoginForm: View {
    let viewModel: ViewModel
    @Binding var mode: LoginMode
    @State var email = ""
    @State var password = ""
    var body: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            AuthField(symbol: "envelope", title: "E-mail", text: $email)
            AuthField(symbol: "lock", title: "Mot de passe", text: $password, isSecure: true)
            AuthErrorLabel(message: viewModel.authErrorMessage)
            Button("Se connecter") { Task { await viewModel.login(email: email, password: password) } }
                .orangeButton().disabled(viewModel.isAuthLoading)
            if viewModel.isAuthLoading { ProgressView().tint(TelegrapheTheme.accent) }
            Button("Mot de passe oublié ?") { mode = .forgot }.foregroundStyle(TelegrapheTheme.accentDeep)
            Button("Pas encore de compte ?  S’inscrire") { mode = .register }.foregroundStyle(TelegrapheTheme.secondaryText)
        }
    }
}

struct RegisterForm: View {
    let viewModel: ViewModel
    @Binding var mode: LoginMode
    @State var email = ""
    @State var password = ""
    @State var confirmation = ""
    @State var displayName = ""
    var body: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            AuthField(symbol: "person", title: "Nom d’affichage", text: $displayName)
            AuthField(symbol: "envelope", title: "E-mail", text: $email)
            AuthField(symbol: "lock", title: "Mot de passe (12 caractères minimum)", text: $password, isSecure: true)
            AuthField(symbol: "checkmark.shield", title: "Confirmer le mot de passe", text: $confirmation, isSecure: true)
            AuthErrorLabel(message: viewModel.authErrorMessage)
            Button("Créer le compte") { Task { await viewModel.register(email: email, password: password, confirmation: confirmation, displayName: displayName) } }
                .orangeButton().disabled(viewModel.isAuthLoading)
            Button("J’ai déjà un compte") { mode = .login }.foregroundStyle(TelegrapheTheme.accentDeep)
        }
        .onChange(of: viewModel.sessionState) { _, state in if state == .emailVerificationRequired { mode = .verify } }
    }
}

struct VerifyEmailForm: View {
    let viewModel: ViewModel
    @Binding var mode: LoginMode
    @State var token = ""
    var body: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            Text("Collez le token reçu dans le lien de vérification.").foregroundStyle(TelegrapheTheme.secondaryText)
            AuthField(symbol: "checkmark.shield", title: "Token de vérification", text: $token)
            AuthErrorLabel(message: viewModel.authErrorMessage)
            Button("Vérifier l’adresse") { Task { await viewModel.verifyEmail(token: token) } }
                .orangeButton().disabled(viewModel.isAuthLoading || token.isEmpty)
            Button("Retour à la connexion") { mode = .login }.foregroundStyle(TelegrapheTheme.accentDeep)
        }
    }
}

struct ForgotPasswordForm: View {
    let viewModel: ViewModel
    @Binding var mode: LoginMode
    @State var email = ""
    @State var sent = false
    var body: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            AuthField(symbol: "envelope", title: "E-mail", text: $email)
            AuthErrorLabel(message: viewModel.authErrorMessage)
            if sent { Text("Si cette adresse existe, un e-mail a été envoyé.").font(.footnote).foregroundStyle(TelegrapheTheme.secondaryText) }
            Button("Envoyer le lien") { Task { await viewModel.requestPasswordReset(email: email); sent = viewModel.authErrorMessage == nil } }
                .orangeButton().disabled(viewModel.isAuthLoading)
            Button("Retour à la connexion") { mode = .login }.foregroundStyle(TelegrapheTheme.accentDeep)
        }
    }
}
