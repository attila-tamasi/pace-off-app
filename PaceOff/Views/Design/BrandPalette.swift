// BrandPalette.swift
// Shared brand styling: gradient, slogan typography, soft-glow modifier.
// Used by the splash, auth gate, and onboarding slides so the launch arc
// feels like one continuous piece.

import SwiftUI

enum BrandPalette {

    /// Vertical brand gradient — accent at the top fading into a deeper warm
    /// tone. Use as a full-bleed background for hero screens.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color(red: 0.78, green: 0.31, blue: 0.10),
                Color(red: 0.42, green: 0.16, blue: 0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Soft, slow drifting orb used as a backdrop accent on top of the
    /// gradient. Two of these layered at different positions give the screen
    /// gentle motion without distracting from content.
    @ViewBuilder
    static func driftingOrb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.45)
    }
}

// MARK: - Soft glow modifier

extension View {
    /// Soft outer glow — used behind the figure.run hero glyph so it reads
    /// as luminous against the gradient.
    func brandSoftGlow(color: Color = .white, radius: CGFloat = 30) -> some View {
        self
            .shadow(color: color.opacity(0.45), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.25), radius: radius * 1.6, x: 0, y: 0)
    }
}

// MARK: - Slogan text style

struct BrandSloganStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 36, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
    }
}

struct BrandSubtitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.title3, design: .rounded, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func brandSlogan() -> some View { modifier(BrandSloganStyle()) }
    func brandSubtitle() -> some View { modifier(BrandSubtitleStyle()) }
}
