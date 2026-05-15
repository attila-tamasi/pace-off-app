// SplashView.swift
// First view shown on cold launch. Plays a brief brand-mark animation then
// hands off to whatever flow stage comes next via `onFinished`.

import SwiftUI

struct SplashView: View {

    let onFinished: () -> Void

    @State private var glyphScale: CGFloat = 0.6
    @State private var glyphOpacity: Double = 0
    @State private var stridePulse: CGFloat = 1.0
    @State private var wordmarkOffset: CGFloat = 12
    @State private var wordmarkOpacity: Double = 0

    var body: some View {
        ZStack {
            BrandPalette.heroGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                // Replace with `Image("brand-mark")` once a custom mark exists.
                Image(systemName: "figure.run")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.white)
                    .brandSoftGlow()
                    .scaleEffect(glyphScale * stridePulse)
                    .opacity(glyphOpacity)

                Text("Pace Off")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                    .offset(y: wordmarkOffset)
                    .opacity(wordmarkOpacity)
            }
        }
        .onAppear { runAnimation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace Off")
    }

    private func runAnimation() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
            glyphScale = 1.0
            glyphOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
            wordmarkOffset = 0
            wordmarkOpacity = 1
        }
        // Subtle stride pulse so the figure looks like it's breathing.
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(0.45)) {
            stridePulse = 1.06
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
