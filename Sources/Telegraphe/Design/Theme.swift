import SwiftUI

enum TelegrapheTheme {
    static let accent = Color.orange
    static let accentDeep = accent
    static let onAccent = Color.white
    static let shadow = Color.black.opacity(0.08)
    static let accentSoft = accent.opacity(0.16)
    static let background = Color.primary.opacity(0.015)
    static let surface = Color.primary.opacity(0.055)
    static let elevatedSurface = Color.primary.opacity(0.045)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color.primary.opacity(0.12)
    static let success = Color.green
    static let danger = Color.red
    static let receivedBubble = Color.primary.opacity(0.08)
    static let avatarPalette = [
        accent.opacity(0.16),
        Color.teal.opacity(0.14),
        Color.pink.opacity(0.15),
        Color.blue.opacity(0.15),
        Color.purple.opacity(0.15),
        Color.yellow.opacity(0.18)
    ]
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let spaceXXL: CGFloat = 32
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TelegrapheTheme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(TelegrapheTheme.accent, in: RoundedRectangle(cornerRadius: TelegrapheTheme.radiusL))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TelegrapheTheme.accentDeep)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(TelegrapheTheme.accentSoft, in: RoundedRectangle(cornerRadius: TelegrapheTheme.radiusM))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct RoundedFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, TelegrapheTheme.spaceL)
            .frame(minHeight: 48)
            .background(TelegrapheTheme.surface, in: RoundedRectangle(cornerRadius: 15))
    }
}

extension View {
    func roundedField() -> some View { modifier(RoundedFieldStyle()) }
    func orangeButton() -> some View { buttonStyle(PrimaryButton()) }
}
