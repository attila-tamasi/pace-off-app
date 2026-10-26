// BrandPalette.swift
// Shared brand styling, taken from the app icon: a sky-to-deep-blue
// background with an orange running track. The splash, auth gate,
// onboarding and the Today hero all draw from here, so the app and its
// icon read as one piece.

import SwiftUI

enum BrandPalette {

    // MARK: - Colours (sampled from the icon)

    /// Light sky blue, the icon's top-leading corner.
    static let sky = Color(red: 0.17, green: 0.53, blue: 0.99)
    /// Mid blue, the bulk of the icon's background.
    static let blue = Color(red: 0.08, green: 0.38, blue: 0.94)
    /// Deep blue, the icon's bottom-trailing corner.
    static let deepBlue = Color(red: 0.04, green: 0.25, blue: 0.85)
    /// Darkest blue, only for the bottom of full-screen gradients.
    static let navy = Color(red: 0.02, green: 0.17, blue: 0.62)

    /// The track's light orange, where the bend ends at the top.
    static let trackLight = Color(red: 1.00, green: 0.62, blue: 0.11)
    /// The track's main orange. Also the colour of running data.
    static let track = Color(red: 0.99, green: 0.42, blue: 0.11)
    /// The track's deep orange, where the bend starts at the bottom.
    static let trackDeep = Color(red: 0.94, green: 0.31, blue: 0.10)

    // MARK: - Gradients

    /// Full-bleed hero background: sky at the top to navy at the bottom,
    /// as on the icon.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [sky, blue, deepBlue, navy],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Card-sized hero gradient. Stops at deep blue so a card stays bright
    /// enough for white type without turning heavy.
    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [sky, blue, deepBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Short orange gradient for bars and small fills.
    static var trackFill: LinearGradient {
        LinearGradient(colors: [trackDeep, trackLight], startPoint: .bottom, endPoint: .top)
    }

    /// Soft, slow drifting orb used as a backdrop accent. Two of these
    /// layered at different positions give a screen gentle colour without
    /// distracting from content.
    @ViewBuilder
    static func driftingOrb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: size * 0.45)
    }
}

// MARK: - Brand mark

/// The app icon's artwork as an in-app image, with the icon's continuous
/// corner rounding. Decorative: the screens it sits on name the app in text.
struct BrandMark: View {
    var size: CGFloat = 92

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Soft glow modifier

extension View {
    /// Soft outer glow, so a hero glyph reads as luminous against its
    /// backdrop.
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
