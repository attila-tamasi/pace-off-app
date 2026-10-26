// SplashView.swift
// First view shown on cold launch. The icon's track draws itself in across
// the hero gradient, the runner lights up on it, and the brand mark and
// wordmark settle in. Then it hands off to whatever flow stage comes next
// via `onFinished`. The auth gate uses the same backdrop, so that hand-off
// is seamless.

import SwiftUI

struct SplashView: View {

    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trackProgress: CGFloat = 0
    @State private var showsRunner = false
    @State private var markScale: CGFloat = 0.7
    @State private var markOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 12
    @State private var wordmarkOpacity: Double = 0

    var body: some View {
        ZStack {
            BrandBackdrop(progress: trackProgress, runner: showsRunner ? 0.6 : nil)

            VStack(spacing: 20) {
                BrandMark(size: 104)
                    .shadow(color: BrandPalette.navy.opacity(0.45), radius: 18, y: 10)
                    .scaleEffect(markScale)
                    .opacity(markOpacity)

                Text("Pace Off")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                    .offset(y: wordmarkOffset)
                    .opacity(wordmarkOpacity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 64)
        }
        .onAppear { runAnimation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace Off")
    }

    private func runAnimation() {
        if reduceMotion {
            trackProgress = 1
            showsRunner = true
            markScale = 1
            markOpacity = 1
            wordmarkOffset = 0
            wordmarkOpacity = 1
        } else {
            withAnimation(.easeOut(duration: 0.8)) {
                trackProgress = 1
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.1)) {
                markScale = 1
                markOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                wordmarkOffset = 0
                wordmarkOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.75)) {
                showsRunner = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
