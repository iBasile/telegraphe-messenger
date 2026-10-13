import SwiftUI

enum TelegrapheTheme {
    static let accent = Color.orange
    static let accentDeep = Color(red: 0.76, green: 0.25, blue: 0.05)
    static let onAccent = Color.white
    static let shadow = Color.black.opacity(0.12)
    static let accentSoft = Color(red: 1.0, green: 0.55, blue: 0.14).opacity(0.16)
    static let background = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let surface = Color(red: 1.0, green: 0.99, blue: 0.97)
    static let elevatedSurface = Color.white
    static let primaryText = Color(red: 0.15, green: 0.10, blue: 0.07)
    static let secondaryText = Color(red: 0.40, green: 0.34, blue: 0.30)
    static let separator = Color(red: 0.82, green: 0.75, blue: 0.68).opacity(0.45)
    static let success = Color(red: 0.18, green: 0.48, blue: 0.25)
    static let danger = Color(red: 0.75, green: 0.12, blue: 0.10)
    static let avatarPalette = [
        Color(red: 0.95, green: 0.38, blue: 0.16),
        Color(red: 0.95, green: 0.62, blue: 0.12),
        Color(red: 0.89, green: 0.39, blue: 0.29),
        Color(red: 0.68, green: 0.30, blue: 0.20),
        Color(red: 0.78, green: 0.60, blue: 0.39),
        Color(red: 0.85, green: 0.48, blue: 0.52)
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
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(TelegrapheTheme.accentDeep, in: RoundedRectangle(cornerRadius: TelegrapheTheme.radiusM))
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
            .background(TelegrapheTheme.surface, in: RoundedRectangle(cornerRadius: TelegrapheTheme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: TelegrapheTheme.radiusM).stroke(TelegrapheTheme.separator, lineWidth: 1))
    }
}

extension View {
    func roundedField() -> some View { modifier(RoundedFieldStyle()) }
    func orangeButton() -> some View { buttonStyle(PrimaryButton()) }
}
