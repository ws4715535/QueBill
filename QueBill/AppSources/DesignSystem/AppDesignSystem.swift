import SwiftUI

enum AppSpacing {
    static let xSmall: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

enum AppRadius {
    static let control: CGFloat = 10
    static let surface: CGFloat = 12
    static let hero: CGFloat = 16
}

enum AppColors {
    static let backgroundPrimary = Color.white
    static let backgroundSubtle = Color(red: 0.965, green: 0.965, blue: 0.970)
    static let surface = Color.white
    static let accentStrong = Color(red: 0.298, green: 0.153, blue: 0.843)
    static let accentDefault = Color(red: 0.451, green: 0.341, blue: 0.965)
    static let accentSubtle = Color(red: 0.937, green: 0.918, blue: 1.000)
    static let textPrimary = Color(red: 0.110, green: 0.094, blue: 0.200)
    static let textSecondary = Color(red: 0.439, green: 0.424, blue: 0.537)
    static let border = Color(red: 0.886, green: 0.875, blue: 0.945)
    static let warning = Color(red: 0.718, green: 0.475, blue: 0.122)
    static let danger = Color(red: 0.663, green: 0.220, blue: 0.180)
    static let trend = Color(red: 0.039, green: 0.702, blue: 0.792)

    static let accent = accentStrong
    static let subtleAccent = accentSubtle
    static let canvas = backgroundPrimary
    static let divider = border
    static let secondaryText = textSecondary
}

enum AppTypography {
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let machineNumber = Font.system(size: 26, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 18, weight: .bold)
    static let metric = Font.system(size: 24, weight: .bold, design: .rounded)
}

struct ProductPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                configuration.isPressed ? AppColors.accentDefault : AppColors.accentStrong,
                in: RoundedRectangle(cornerRadius: AppRadius.control)
            )
            .contentShape(Rectangle())
    }
}

struct ProductSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                configuration.isPressed ? AppColors.border : AppColors.backgroundSubtle,
                in: RoundedRectangle(cornerRadius: AppRadius.control)
            )
            .contentShape(Rectangle())
    }
}

typealias PrimaryActionButtonStyle = ProductPrimaryButtonStyle
typealias SecondaryActionButtonStyle = ProductSecondaryButtonStyle

struct ProductCardModifier: ViewModifier {
    var radius: CGFloat = AppRadius.surface
    var borderColor: Color = AppColors.border
    var background: Color = AppColors.surface

    func body(content: Content) -> some View {
        content
            .background(background, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(borderColor, lineWidth: 1)
            }
    }
}

extension View {
    func productCard(
        radius: CGFloat = AppRadius.surface,
        borderColor: Color = AppColors.border,
        background: Color = AppColors.surface
    ) -> some View {
        modifier(ProductCardModifier(radius: radius, borderColor: borderColor, background: background))
    }
}

extension MachineStatus {
    var tint: Color {
        switch self {
        case .idle: AppColors.textSecondary
        case .inUse: AppColors.accentDefault
        case .paused: AppColors.warning
        case .maintenance: AppColors.danger
        case .disabled: AppColors.textSecondary
        }
    }

    var symbol: String {
        switch self {
        case .idle: "checkmark.circle.fill"
        case .inUse: "clock.fill"
        case .paused: "pause.circle.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .disabled: "minus.circle.fill"
        }
    }
}
