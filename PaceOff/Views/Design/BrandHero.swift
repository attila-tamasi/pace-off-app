// BrandHero.swift
// Reusable hero composition: animated gradient backdrop with two drifting
// blurred orbs, an SF Symbol with a soft pulse, and headline + subtitle.
// Used by AuthGateView and each onboarding slide so they share visual DNA.

import SwiftUI

struct BrandHero<Footer: View>: View {

    /// SF Symbol name. The auth gate uses "figure.run".
    /// NOTE: replace with a custom illustration asset when artwork is ready —
    /// just swap the `Image(systemName:)` below for `Image("brand-hero")`.
    let symbol: String
    let headline: String
    let subtitle: String
    /// Symbol size in points. Defaults to the auth-gate hero size.
    let symbolSize: CGFloat
    /// Whether the gradient backdrop is drawn. Onboarding slides set this
    /// to false so they can use the plain system background.
    let showsBackdrop: Bool
    /// Bottom-pinned content (CTA buttons, legal links, page dots, etc.).
    let footer: () -> Footer

    @State private var sloganOpacity: Double = 0
    @State private var sloganOffset: CGFloat = 16
    @State private var footerOpacity: Double = 0
    @State private var footerOffset: CGFloat = 24
    @State private var orbDrift: CGFloat = 0

    init(
        symbol: String,
        headline: String,
        subtitle: String,
        symbolSize: CGFloat = 140,
        showsBackdrop: Bool = true,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.symbol = symbol
        self.headline = headline
        self.subtitle = subtitle
        self.symbolSize = symbolSize
        self.showsBackdrop = showsBackdrop
        self.footer = footer
    }

    var body: some View {
        ZStack {
            if showsBackdrop {
                backdrop
                    .ignoresSafeArea()
            }

            VStack(spacing: 28) {
                Spacer(minLength: 24)

                // Replace this Image with `Image("brand-hero-illustration")`
                // when a custom asset is available.
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(showsBackdrop ? .white : .accentColor)
                    .symbolEffect(.pulse, options: .repeating)
                    .brandSoftGlow(color: showsBackdrop ? .white : .accentColor,
                                   radius: showsBackdrop ? 30 : 18)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    if showsBackdrop {
                        Text(headline).brandSlogan()
                        Text(subtitle).brandSubtitle()
                    } else {
                        Text(headline)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .opacity(sloganOpacity)
                .offset(y: sloganOffset)

                Spacer(minLength: 16)

                footer()
                    .opacity(footerOpacity)
                    .offset(y: footerOffset)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .onAppear { runEntryAnimations() }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            BrandPalette.heroGradient

            BrandPalette.driftingOrb(color: .white.opacity(0.22), size: 360)
                .offset(x: -120 + orbDrift, y: -220 - orbDrift * 0.5)

            BrandPalette.driftingOrb(color: .yellow.opacity(0.18), size: 300)
                .offset(x: 130 - orbDrift, y: 240 + orbDrift * 0.4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                orbDrift = 60
            }
        }
    }

    private func runEntryAnimations() {
        withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
            sloganOpacity = 1
            sloganOffset = 0
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.55)) {
            footerOpacity = 1
            footerOffset = 0
        }
    }
}

// Convenience initialiser for slides that don't need a footer.
extension BrandHero where Footer == EmptyView {
    init(
        symbol: String,
        headline: String,
        subtitle: String,
        symbolSize: CGFloat = 140,
        showsBackdrop: Bool = true
    ) {
        self.init(
            symbol: symbol,
            headline: headline,
            subtitle: subtitle,
            symbolSize: symbolSize,
            showsBackdrop: showsBackdrop,
            footer: { EmptyView() }
        )
    }
}

#Preview("Hero — backdrop") {
    BrandHero(
        symbol: "figure.run",
        headline: "Show up. Run anyway.",
        subtitle: "A no-excuses running coach in your pocket."
    ) {
        Text("Footer slot").foregroundStyle(.white)
    }
}

#Preview("Hero — plain") {
    BrandHero(
        symbol: "heart.text.square.fill",
        headline: "Read your run data.",
        subtitle: "VO₂ max, runs, HR, HRV — straight from Apple Health.",
        symbolSize: 96,
        showsBackdrop: false
    )
}
