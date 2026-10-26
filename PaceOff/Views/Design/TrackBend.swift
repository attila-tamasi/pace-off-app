// TrackBend.swift
// The icon's running-track bend, drawn rather than shipped as an image so
// it scales to any frame and can animate: a quarter of a ring whose centre
// sits at or past the bottom-trailing corner, orange lanes split by white
// lines, and an optional glowing dot for the runner.
//
// `BrandBackdrop` places it full-screen on the hero gradient. The splash
// and the auth gate share that backdrop, so the hand-off between them is
// seamless.

import SwiftUI

struct TrackBend: View {

    /// Centre of the ring as a unit point of the frame. As on the icon it
    /// usually sits at, or past, the bottom-trailing corner.
    var center: UnitPoint = .bottomTrailing
    /// Radius of the track's centre line, as a fraction of the frame width.
    var radius: CGFloat = 0.72
    /// Width of the track, as a fraction of the frame width.
    var width: CGFloat = 0.36
    /// How much of the bend is drawn, 0…1. Animate it to draw the track in.
    var progress: CGFloat = 1
    /// Where the runner sits along the bend, 0…1, or nil for no runner.
    var runner: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: center.x * geo.size.width, y: center.y * geo.size.height)
            let r = radius * geo.size.width
            let band = width * geo.size.width
            let line = max(1.5, band * 0.014)

            ZStack {
                TrackArc(center: c, radius: r)
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [BrandPalette.trackDeep, BrandPalette.track, BrandPalette.trackLight],
                            center: center,
                            startAngle: .degrees(180),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: band, lineCap: .butt)
                    )
                    .shadow(color: BrandPalette.navy.opacity(0.4), radius: band * 0.09, y: band * 0.06)

                // Three white lines split the track into four lanes.
                ForEach(1..<4) { lane in
                    TrackArc(center: c, radius: r - band / 2 + band * CGFloat(lane) / 4)
                        .trim(from: 0, to: progress)
                        .stroke(.white.opacity(0.85), lineWidth: line)
                }

                if let runner {
                    let angle = Double.pi + Double.pi / 2 * Double(runner)
                    let laneRadius = r + band * 0.125
                    let dot = max(6, band * 0.05)
                    Circle()
                        .fill(.white)
                        .frame(width: dot, height: dot)
                        .shadow(color: .white.opacity(0.9), radius: dot * 0.8)
                        .shadow(color: .white.opacity(0.5), radius: dot * 2.2)
                        .position(
                            x: c.x + laneRadius * CGFloat(cos(angle)),
                            y: c.y + laneRadius * CGFloat(sin(angle))
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.4)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A quarter ring's centre line, from the leading side round to the top.
/// Drawn as a fine polyline so the direction, and so `trim`, is the same
/// on every OS: the track draws in from the bottom-leading end.
private struct TrackArc: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 96
        for step in 0...steps {
            let angle = Double.pi + Double.pi / 2 * Double(step) / Double(steps)
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

// MARK: - Full-screen backdrop

/// The hero gradient with the track sweeping across the lower half of the
/// screen, as on the icon. `progress` and `runner` pass through to
/// `TrackBend` so the splash can animate the same picture the auth gate
/// shows still.
struct BrandBackdrop: View {
    var progress: CGFloat = 1
    var runner: CGFloat? = 0.6

    var body: some View {
        ZStack {
            BrandPalette.heroGradient
            TrackBend(
                center: UnitPoint(x: 1.18, y: 1.26),
                radius: 1.14,
                width: 0.385,
                progress: progress,
                runner: runner
            )
        }
        .ignoresSafeArea()
    }
}

#Preview("Backdrop") {
    BrandBackdrop()
}

#Preview("Track in a card") {
    ZStack(alignment: .bottomTrailing) {
        BrandPalette.cardGradient
        TrackBend(radius: 0.75, width: 0.27)
            .frame(width: 150, height: 150)
    }
    .frame(height: 200)
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    .padding()
}
