import SwiftUI
import TelegrapheCore

enum AvatarSize {
    case small, medium, large

    var value: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 52
        case .large: return 72
        }
    }
}

struct AvatarView: View {
    let name: String
    var size: AvatarSize = .medium
    var isOnline = false

    var initials: String {
        let words = name.split(separator: " ")
        if words.count == 1 { return String(words.first?.prefix(1) ?? "?").uppercased() }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var color: Color {
        let value = name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % TelegrapheTheme.avatarPalette.count }
        return TelegrapheTheme.avatarPalette[value]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(color)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size.value * 0.34, weight: .semibold))
                .foregroundStyle(TelegrapheTheme.onAccent)
            if isOnline {
                Circle().fill(TelegrapheTheme.success)
                    .frame(width: size.value * 0.25, height: size.value * 0.25)
                    .overlay(Circle().stroke(TelegrapheTheme.background, lineWidth: 2))
            }
        }
        .frame(width: size.value, height: size.value)
        .accessibilityLabel("Avatar de \(name)")
    }
}

struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(TelegrapheTheme.onAccent)
            .frame(minWidth: 22, minHeight: 22)
            .background(TelegrapheTheme.accentDeep, in: Capsule())
            .accessibilityLabel("\(count) messages non lus")
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? TelegrapheTheme.onAccent : TelegrapheTheme.secondaryText)
                .padding(.horizontal, TelegrapheTheme.spaceL)
                .frame(minHeight: 36)
                .background(isSelected ? TelegrapheTheme.accentDeep : TelegrapheTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var unreadCount = 0

    var body: some View {
        HStack(spacing: TelegrapheTheme.spaceM) {
            AvatarView(name: conversation.title)
            VStack(alignment: .leading, spacing: TelegrapheTheme.spaceXS) {
                HStack {
                    Text(conversation.title).font(.headline.weight(.semibold)).foregroundStyle(TelegrapheTheme.primaryText)
                    Spacer()
                    Text("12:40").font(.caption).foregroundStyle(unreadCount > 0 ? TelegrapheTheme.accentDeep : TelegrapheTheme.secondaryText)
                }
                HStack(spacing: TelegrapheTheme.spaceXS) {
                    Text(conversation.lastMessage ?? "Aucun message")
                        .font(.subheadline).foregroundStyle(TelegrapheTheme.secondaryText).lineLimit(1)
                    Spacer()
                    if unreadCount > 0 { UnreadBadge(count: unreadCount) }
                }
            }
        }
        .padding(.vertical, TelegrapheTheme.spaceS)
        .accessibilityLabel("\(conversation.title), \(conversation.lastMessage ?? "Aucun message")")
    }
}

struct MessageBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: TelegrapheTheme.spaceXS) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isMine ? TelegrapheTheme.onAccent : TelegrapheTheme.primaryText)
                    .padding(.horizontal, TelegrapheTheme.spaceL)
                    .padding(.vertical, 10)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: isMine ? 18 : 4,
                            bottomTrailingRadius: isMine ? 4 : 18,
                            topTrailingRadius: 18
                        )
                        .fill(isMine ? TelegrapheTheme.accent : TelegrapheTheme.receivedBubble)
                    }
                HStack(spacing: TelegrapheTheme.spaceXS) {
                    Text("12:40").font(.caption2).foregroundStyle(TelegrapheTheme.secondaryText)
                    if isMine { MessageStatusIcon(status: message.status) }
                }
            }
            .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer(minLength: 48) }
        }
    }
}

struct MessageStatusIcon: View {
    let status: MessageStatus
    var symbol: String {
        switch status {
        case .pending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
    var body: some View {
        Image(systemName: symbol)
            .font(.caption2)
            .foregroundStyle(status == .failed ? TelegrapheTheme.danger : (status == .read ? TelegrapheTheme.accentDeep : TelegrapheTheme.secondaryText))
            .accessibilityLabel(status == .failed ? "Échec de l’envoi" : "Statut du message")
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let symbol: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: TelegrapheTheme.spaceM) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(TelegrapheTheme.accent)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(TelegrapheTheme.primaryText)
            Text(message).font(.body).foregroundStyle(TelegrapheTheme.secondaryText).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).modifier(SecondaryButtonModifier()) }
        }
        .padding(TelegrapheTheme.spaceXL)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.headline.weight(.semibold)).foregroundStyle(TelegrapheTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TelegrapheTheme.spaceL)
            .padding(.top, TelegrapheTheme.spaceS)
    }
}

struct SettingsRow: View {
    let title: String
    let symbol: String
    var tint: Color = TelegrapheTheme.accent
    var textTint: Color = TelegrapheTheme.primaryText
    var body: some View {
        HStack(spacing: TelegrapheTheme.spaceM) {
            Image(systemName: symbol).foregroundStyle(TelegrapheTheme.onAccent).frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: TelegrapheTheme.radiusS))
            Text(title).foregroundStyle(textTint)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(TelegrapheTheme.secondaryText)
        }
        .frame(minHeight: 44)
    }
}
