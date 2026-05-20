import SwiftUI

/// CardShow Pro design system.
/// Premium-dark aesthetic — matte black canvas, hot-accent value tags,
/// monospace numerics. Reads as a pro vendor tool, not a kid's collector app.
enum Theme {

    // MARK: - Colors
    enum Colors {
        // Backgrounds
        static let bg          = Color(red: 0.04, green: 0.04, blue: 0.05)   // #0A0A0C — main canvas
        static let surface     = Color(red: 0.10, green: 0.10, blue: 0.11)   // #1A1A1D — cards
        static let surfaceHi   = Color(red: 0.14, green: 0.14, blue: 0.16)   // elevated surface
        static let border      = Color.white.opacity(0.08)
        static let divider     = Color.white.opacity(0.04)

        // Text
        static let textPrimary   = Color.white
        static let textSecondary = Color.white.opacity(0.65)
        static let textTertiary  = Color.white.opacity(0.40)
        static let textDisabled  = Color.white.opacity(0.25)

        // Accents
        static let amber      = Color(red: 1.00, green: 0.69, blue: 0.13)   // #FFB020 — primary accent / value
        static let amberSoft  = Color(red: 1.00, green: 0.69, blue: 0.13).opacity(0.15)
        static let green      = Color(red: 0.24, green: 0.86, blue: 0.52)   // #3DDC84 — sold / profit
        static let greenSoft  = Color(red: 0.24, green: 0.86, blue: 0.52).opacity(0.15)
        static let red        = Color(red: 1.00, green: 0.28, blue: 0.34)   // #FF4757 — loss / alert
        static let redSoft    = Color(red: 1.00, green: 0.28, blue: 0.34).opacity(0.15)
        static let blue       = Color(red: 0.36, green: 0.66, blue: 1.00)   // #5BA9FF — bought / accent secondary
        static let blueSoft   = Color(red: 0.36, green: 0.66, blue: 1.00).opacity(0.15)
    }

    // MARK: - Typography
    enum Typography {
        static let displayLarge  = Font.system(size: 44, weight: .heavy, design: .rounded)
        static let displayNum    = Font.system(size: 36, weight: .bold,  design: .monospaced)
        static let headline      = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let title         = Font.system(size: 17, weight: .semibold, design: .default)
        static let body          = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMono      = Font.system(size: 15, weight: .medium,  design: .monospaced)
        static let priceLg       = Font.system(size: 22, weight: .bold,    design: .monospaced)
        static let priceMd       = Font.system(size: 17, weight: .semibold, design: .monospaced)
        static let priceSm       = Font.system(size: 13, weight: .medium,  design: .monospaced)
        static let caption       = Font.system(size: 12, weight: .medium, design: .default)
        static let captionMono   = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let label         = Font.system(size: 11, weight: .heavy,  design: .default).smallCaps()
    }

    // MARK: - Spacing (12pt base grid — tight by design)
    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 20
        static let xl:  CGFloat = 32
    }

    // MARK: - Radii
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let pill: CGFloat = 999
    }
}

// MARK: - Reusable view modifiers

struct SurfaceCardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.md
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func surfaceCard(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(SurfaceCardModifier(padding: padding))
    }
}

// MARK: - Status pill (bought / sold / traded)

struct StatusPill: View {
    let status: String

    private var palette: (bg: Color, fg: Color, label: String) {
        switch status.lowercased() {
        case "bought", "holding":
            return (Theme.Colors.blueSoft, Theme.Colors.blue, status.uppercased())
        case "sold":
            return (Theme.Colors.greenSoft, Theme.Colors.green, "SOLD")
        case "traded":
            return (Theme.Colors.amberSoft, Theme.Colors.amber, "TRADED")
        default:
            return (Color.white.opacity(0.08), Theme.Colors.textSecondary, status.uppercased())
        }
    }

    var body: some View {
        Text(palette.label)
            .font(Theme.Typography.label)
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(palette.bg))
            .foregroundStyle(palette.fg)
    }
}

// MARK: - Big number display (used on TodayView)

struct StatTile: View {
    let label: String
    let value: String
    let accent: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(Theme.Typography.displayNum)
                .foregroundStyle(accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: Theme.Spacing.lg)
    }
}
