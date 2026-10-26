// BrandHero.swift
// Full-screen brand composition for the auth gate: the splash's backdrop
// (hero gradient + the icon's running track), the brand mark, the
// wordmark, a headline and subtitle, and a bottom-pinned footer slot.
// Sharing the splash's backdrop makes launch → sign-in one continuous
// picture.

import SwiftUI

struct BrandHero<Footer: View>: View {

    let headline: String
    let subtitle: String
    /// Bottom-pinned content (CTA buttons, legal links, etc.).
    let footer: () -> Footer

    @State private var sloganOpacity: Double = 0
    @State private var sloganOffset: CGFloat = 16
    @State private var footerOpacity: Double = 0
    @State private var footerOffset: CGFloat = 24

    init(
        headline: String,
        subtitle: String,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.headline = headline
        self.subtitle = subtitle
        self.footer = footer
    }

    var body: some View {
        ZStack {
            BrandBackdrop()

            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    BrandMark(size: 104)
                        .shadow(color: BrandPalette.navy.opacity(0.45), radius: 18, y: 10)

                    Text("Pace Off")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(subtitle).brandSubtitle()
                    }
                    .padding(.horizontal, 28)
                    .opacity(sloganOpacity)
                    .offset(y: sloganOffset)
                }
                // Same top offset as the splash, so the mark doesn't move
                // when the splash hands over.
                .padding(.top, 64)

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

#Preview("Hero") {
    BrandHero(
        headline: "Show up. Run anyway.",
        subtitle: "A no-excuses running coach in your pocket."
    ) {
        Text("Footer slot").foregroundStyle(.white)
    }
}
