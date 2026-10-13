import Observation
import SkipFuse
import TelegrapheCore

public enum SessionState: Equatable {
    case signedOut
    case signingIn
    case signedIn
    case emailVerificationRequired
}

@MainActor @Observable public final class ViewModel {
    public var conversations: [Conversation] = []
    public var messages: [Message] = []
    public var searchResults: [Message] = []
    public var pendingMedia: [MediaAttachment] = []
    public var selectedConversationID: String?
    public var errorMessage: String?
    public var showingGroupCreation = false
    public var groupToAdminister: Conversation?
    public var sessionState: SessionState = .signedOut
    public var authErrorMessage: String?
    public var isAuthLoading = false
    var database: LocalDatabase?
    let authService: AuthService

    public init(
        authService: AuthService = AuthService(
            client: ServerAuthenticationClient(http: URLSessionHTTPClient(configuration: APIConfiguration())),
            storage: KeychainSecureStorage()
        )
    ) {
        self.authService = authService
        retryDatabase()
    }

    public func restoreSession() async {
        isAuthLoading = true
        defer { isAuthLoading = false }
        do {
            sessionState = try await authService.restoreSession() ? .signedIn : .signedOut
        } catch {
            sessionState = .signedOut
        }
    }

    public func login(email: String, password: String) async {
        await performAuthRequest {
            try await self.authService.login(email: email, password: password)
            self.sessionState = .signedIn
        }
    }

    public func register(email: String, password: String, confirmation: String, displayName: String) async {
        await performAuthRequest {
            try await self.authService.register(
                email: email,
                password: password,
                confirmation: confirmation,
                displayName: displayName
            )
            self.sessionState = .emailVerificationRequired
        }
    }

    public func verifyEmail(token: String) async {
        await performAuthRequest {
            try await self.authService.verifyEmail(token: token)
            self.sessionState = .signedOut
        }
    }

    public func requestPasswordReset(email: String) async {
        await performAuthRequest {
            try await self.authService.requestPasswordReset(email: email)
        }
    }

    public func confirmPasswordReset(token: String, password: String, confirmation: String) async {
        await performAuthRequest {
            try await self.authService.confirmPasswordReset(
                token: token,
                password: password,
                confirmation: confirmation
            )
        }
    }

    public func logout() async {
        await performAuthRequest {
            try await self.authService.logout()
            self.sessionState = .signedOut
        }
    }

    public func authMessage(for error: Error) -> String {
        guard let error = error as? AuthError else { return "Une erreur inattendue est survenue." }
        switch error {
        case .invalidEmail: return "Saisissez une adresse e-mail valide."
        case .passwordTooShort: return "Le mot de passe doit contenir au moins 12 caractères."
        case .passwordsDoNotMatch: return "Les mots de passe ne correspondent pas."
        case .emailAlreadyUsed: return "Cette adresse e-mail est déjà utilisée."
        case .invalidCredentials: return "E-mail ou mot de passe incorrect."
        case .emailVerificationRequired: return "Vérifiez votre adresse e-mail avant de vous connecter."
        case .invalidVerificationToken: return "Le lien de vérification est invalide ou expiré."
        case .invalidResetToken: return "Le lien de réinitialisation est invalide ou expiré."
        case .tooManyAttempts: return "Trop de tentatives. Réessayez dans quelques minutes."
        case .networkUnavailable: return "Réseau indisponible. Vérifiez votre connexion."
        case .notAuthenticated: return "Votre session a expiré. Connectez-vous à nouveau."
        case .storageFailure: return "Impossible de sécuriser la session sur cet appareil."
        case .server(let message): return message
        }
    }

    func performAuthRequest(_ request: @escaping () async throws -> Void) async {
        isAuthLoading = true
        authErrorMessage = nil
        defer { isAuthLoading = false }
        do {
            try await request()
        } catch {
            if let authError = error as? AuthError, authError == .emailVerificationRequired {
                sessionState = .emailVerificationRequired
            }
            authErrorMessage = authMessage(for: error)
        }
    }

    public func retryDatabase() {
        do {
            let database = try LocalDatabase.applicationData()
            try database.migrate()
            self.database = database
            errorMessage = nil
        } catch {
            database = nil
            errorMessage = "La base locale n’a pas pu être initialisée. Vérifiez l’espace disponible puis réessayez.\n\nDétail : \(error.localizedDescription)"
        }
    }

    public func beginGroupCreation() {
        showingGroupCreation = true
    }

    public func openConversation(_ conversation: Conversation) {
        selectedConversationID = conversation.id
        refreshMessages()
    }

    public func refreshMessages() {
        guard let id = selectedConversationID else { return }
        guard let database else { return }
        do { messages = try database.messages(in: id) } catch { errorMessage = error.localizedDescription }
    }

    public func send(text: String, to conversation: Conversation, senderID: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let database else { return }
        do {
            try database.upsertConversation(conversation)
            _ = try database.enqueueMessage(conversationID: conversation.id, senderUserID: senderID, text: text)
            selectedConversationID = conversation.id
            refreshMessages()
        } catch { errorMessage = error.localizedDescription }
    }

    public func searchMessages(_ query: String) {
        guard !query.isEmpty else { searchResults = []; return }
        guard let database else { return }
        do { searchResults = try database.searchMessages(matching: query) } catch { errorMessage = error.localizedDescription }
    }

    public func attachMedia(
        using picker: any MediaPicker,
        to conversation: Conversation,
        senderID: String,
        limits: MediaLimits = .init()
    ) async {
        guard let database else { return }
        do {
            let selected = try await picker.pick()
            for media in selected {
                try limits.validate(media)
                try database.upsertConversation(conversation)
                _ = try database.enqueueMedia(
                    conversationID: conversation.id,
                    senderUserID: senderID,
                    media: media
                )
            }
            pendingMedia = selected
            selectedConversationID = conversation.id
            refreshMessages()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
