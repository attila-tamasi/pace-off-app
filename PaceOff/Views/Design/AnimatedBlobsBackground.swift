// AnimatedBlobsBackground.swift
// Reusable full-bleed backdrop: warm brand gradient with six soft, blurred,
// long-period drifting blobs in palette colours. Used by SplashView and
// available to any other screen that wants a richer hero backdrop than the
// static gradient.
//
// All motion uses SwiftUI's implicit animation with `repeatForever(autoreverses:)`,
// so there are no Timers and the system can park the animation on low-power /
// background scene phases.

import SwiftUI

struct AnimatedBlobsBackground: View {

    /// Whether the blobs are visible. Pass false (or call onDisappear)
    /// before navigation to free the animation graph.
    var isAnimating: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BrandPalette.heroGradient
                ForEach(Self.blobs) { blob in
                    BlobView(blob: blob, canvas: geo.size, isAnimating: isAnimating)
                }
            }
        }
        .ignoresSafeArea()
        .compositingGroup() // collapse the blur layers into one GPU pass
    }

    // MARK: - Blob recipes

    /// Each blob has its own size, colour, opacity, blur, animation duration,
    /// and offset path. Sizes/positions are expressed as fractions of the
    /// shorter canvas dimension so the backdrop scales onto iPad.
    fileprivate struct Blob: Identifiable {
        let id: Int
        let color: Color
        let sizeFraction: CGFloat
        let opacity: Double
        let blurFraction: CGFloat
        let start: UnitPoint
        let end: UnitPoint
        let duration: Double
    }

    private static let blobs: [Blob] = [
        // Top-left, accent orange — the dominant blob.
        Blob(id: 0,
             color: Color.accentColor,
             sizeFraction: 0.95,
             opacity: 0.55,
             blurFraction: 0.18,
             start: UnitPoint(x: 0.18, y: 0.18),
             end:   UnitPoint(x: 0.34, y: 0.32),
             duration: 14),
        // Bottom-right, deeper coral.
        Blob(id: 1,
             color: Color(red: 0.94, green: 0.36, blue: 0.20),
             sizeFraction: 0.85,
             opacity: 0.60,
             blurFraction: 0.20,
             start: UnitPoint(x: 0.82, y: 0.78),
             end:   UnitPoint(x: 0.68, y: 0.66),
             duration: 16),
        // Top-right, sunny yellow halo.
        Blob(id: 2,
             color: Color(red: 1.00, green: 0.86, blue: 0.40),
             sizeFraction: 0.55,
             opacity: 0.55,
             blurFraction: 0.16,
             start: UnitPoint(x: 0.80, y: 0.22),
             end:   UnitPoint(x: 0.66, y: 0.30),
             duration: 11),
        // Mid-left, soft peach.
        Blob(id: 3,
             color: Color(red: 1.00, green: 0.71, blue: 0.55),
             sizeFraction: 0.50,
             opacity: 0.50,
             blurFraction: 0.14,
             start: UnitPoint(x: 0.10, y: 0.55),
             end:   UnitPoint(x: 0.22, y: 0.45),
             duration: 13),
        // Lower-left, warm rose.
        Blob(id: 4,
             color: Color(red: 0.88, green: 0.42, blue: 0.32),
             sizeFraction: 0.45,
             opacity: 0.55,
             blurFraction: 0.13,
             start: UnitPoint(x: 0.22, y: 0.88),
             end:   UnitPoint(x: 0.36, y: 0.78),
             duration: 18),
        // Upper-mid, soft cream highlight.
        Blob(id: 5,
             color: Color(red: 1.00, green: 0.96, blue: 0.88),
             sizeFraction: 0.40,
             opacity: 0.45,
             blurFraction: 0.12,
             start: UnitPoint(x: 0.55, y: 0.10),
             end:   UnitPoint(x: 0.45, y: 0.22),
             duration: 9),
    ]
}

// MARK: - Individual blob

private struct BlobView: View {
    let blob: AnimatedBlobsBackground.Blob
    let canvas: CGSize
    let isAnimating: Bool

    @State private var atEnd = false

    var body: some View {
        let shorter = min(canvas.width, canvas.height)
        let size = shorter * blob.sizeFraction
        let blur = shorter * blob.blurFraction
        let target = atEnd ? blob.end : blob.start
        let cx = target.x * canvas.width
        let cy = target.y * canvas.height

        Circle()
            .fill(blob.color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .opacity(blob.opacity)
            .position(x: cx, y: cy)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(
                    .easeInOut(duration: blob.duration)
                    .repeatForever(autoreverses: true)
                ) {
                    atEnd = true
                }
            }
    }
}

#Preview("Animated blobs (full-bleed)") {
    AnimatedBlobsBackground()
}

#Preview("Over content") {
    ZStack {
        AnimatedBlobsBackground()
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(.white)
            Text("Pace Off")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
