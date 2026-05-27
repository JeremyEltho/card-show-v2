import SwiftUI

/// "Convention Booth Pro" — the visual identity of a serious card-flipper at
/// a high-end show. Felt-green table surfaces, holographic shimmer on hero
/// actions, sticker-style price tags, rubber-stamp status marks.
enum Theme {

    // MARK: - Colors

    enum Colors {
        // Surfaces — felt green / poker table
        static let bg          = Color(red: 0.04, green: 0.08, blue: 0.05)   // #0A140C — deep felt
        static let surface     = Color(red: 0.08, green: 0.18, blue: 0.12)   // #15301F — card mat
        static let surfaceHi   = Color(red: 0.11, green: 0.24, blue: 0.17)   // #1C3D2C — elevated
        static let border      = Color(red: 0.18, green: 0.36, blue: 0.26).opacity(0.5)
        static let divider     = Color.white.opacity(0.06)

        // Text — slight warm tint, not pure white (feels less sterile)
        static let textPrimary   = Color(red: 0.98, green: 0.96, blue: 0.91)  // warm white
        static let textSecondary = Color(red: 0.78, green: 0.78, blue: 0.74)
        static let textTertiary  = Color(red: 0.55, green: 0.58, blue: 0.54)
        static let textDisabled  = Color.white.opacity(0.22)

        // Accents — CMYK printing-press energy + sticker yellow
        static let amber      = Color(red: 1.00, green: 0.84, blue: 0.04)   // #FFD60A — sticker yellow
        static let amberSoft  = Color(red: 1.00, green: 0.84, blue: 0.04).opacity(0.15)
        static let green      = Color(red: 0.31, green: 0.86, blue: 0.45)   // #4FDC73 — neon emerald
        static let greenSoft  = Color(red: 0.31, green: 0.86, blue: 0.45).opacity(0.18)
        static let red        = Color(red: 0.93, green: 0.18, blue: 0.27)   // #ED2D45 — Beckett ink red
        static let redSoft    = Color(red: 0.93, green: 0.18, blue: 0.27).opacity(0.18)
        static let blue       = Color(red: 0.15, green: 0.82, blue: 0.96)   // #26D2F5 — cyan
        static let blueSoft   = Color(red: 0.15, green: 0.82, blue: 0.96).opacity(0.18)
        static let magenta    = Color(red: 1.00, green: 0.10, blue: 0.55)   // #FF1A8C — hot pink
        static let parchment  = Color(red: 0.96, green: 0.91, blue: 0.81)   // stamp paper

        // Holographic palette — used by HoloShimmer for animated rainbow accents
        static let holo1 = Color(red: 1.00, green: 0.10, blue: 0.55)        // pink
        static let holo2 = Color(red: 1.00, green: 0.65, blue: 0.10)        // orange
        static let holo3 = Color(red: 0.98, green: 0.93, blue: 0.20)        // yellow
        static let holo4 = Color(red: 0.20, green: 0.93, blue: 0.55)        // green
        static let holo5 = Color(red: 0.15, green: 0.82, blue: 0.96)        // cyan
        static let holo6 = Color(red: 0.55, green: 0.20, blue: 0.96)        // purple
    }

    // MARK: - Typography
    // Mixing Apple's built-in design families to dodge the generic SF Pro
    // monoculture. Rounded for vendor-sign confidence, monospaced for retro
    // price-display feel, serif for stamp / receipt aesthetics.

    enum Typography {
        // Massive vendor-sign headlines
        static let displayHuge   = Font.system(size: 56, weight: .black,   design: .rounded)
        static let displayLarge  = Font.system(size: 44, weight: .black,   design: .rounded)
        static let displayMed    = Font.system(size: 32, weight: .heavy,   design: .rounded)

        // Beckett price-guide scoreboard numerics
        static let displayNum    = Font.system(size: 40, weight: .black,   design: .monospaced)
        static let priceLg       = Font.system(size: 24, weight: .black,   design: .monospaced)
        static let priceMd       = Font.system(size: 18, weight: .bold,    design: .monospaced)
        static let priceSm       = Font.system(size: 13, weight: .semibold, design: .monospaced)

        // Titles + body
        static let headline      = Font.system(size: 22, weight: .heavy,   design: .rounded)
        static let title         = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body          = Font.system(size: 15, weight: .regular)
        static let bodyMono      = Font.system(size: 15, weight: .medium,  design: .monospaced)

        // Captions + labels
        static let caption       = Font.system(size: 12, weight: .medium)
        static let captionMono   = Font.system(size: 11, weight: .medium,  design: .monospaced)
        static let label         = Font.system(size: 11, weight: .black,   design: .rounded).smallCaps()

        // Stamp / receipt — italic serif for rubber-stamp marks
        static let stamp         = Font.system(size: 18, weight: .heavy,   design: .serif).italic()
        static let stampSm       = Font.system(size: 12, weight: .heavy,   design: .serif).italic()
    }

    // MARK: - Spacing (12pt base grid)

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
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Holographic gradient builder

    /// Static holo gradient (linear, used for borders + accents).
    static func holoGradient(angle: Double = 0) -> LinearGradient {
        LinearGradient(
            colors: [Colors.holo1, Colors.holo2, Colors.holo3, Colors.holo4, Colors.holo5, Colors.holo6],
            startPoint: UnitPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5),
            endPoint:   UnitPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
        )
    }
}

// MARK: - Surface card modifier

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

// MARK: - Status stamp (replaces the old StatusPill)
// Rotated rubber-stamp mark — feels like an old-school price guide

struct StatusPill: View {
    let status: String

    private var palette: (bg: Color, fg: Color, label: String) {
        switch status.lowercased() {
        case "bought", "holding":
            return (Theme.Colors.blueSoft, Theme.Colors.blue, "IN STOCK")
        case "sold":
            return (Theme.Colors.redSoft, Theme.Colors.red, "SOLD")
        case "traded":
            return (Theme.Colors.amberSoft, Theme.Colors.amber, "TRADED")
        default:
            return (Color.white.opacity(0.08), Theme.Colors.textSecondary, status.uppercased())
        }
    }

    var body: some View {
        Text(palette.label)
            .font(Theme.Typography.stampSm)
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(palette.fg.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    )
            )
            .foregroundStyle(palette.fg)
            .rotationEffect(.degrees(-2))
    }
}

// MARK: - Big number tile (used on Profile)

struct StatTile: View {
    let label: String
    let value: String
    let accent: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(1.2)
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
