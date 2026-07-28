// OnboardingStepScaffold.swift
// Shared chrome every onboarding step lives inside — progress bar, back
// button, title/subtitle block, content slot, sticky footer with primary
// CTA and an optional secondary "Skip". The look is deliberately quiet:
// system-grouped background, big rounded typography, iOS 26 glassy CTA.
// Only the *content* slot ever changes between steps, which keeps the
// motion between screens smooth and predictable.

import SwiftUI

// MARK: - Progress bar

/// Slim progress bar rendered as a capsule with a filled leading portion.
/// Animates when `progress` changes so stepping forward/back has motion.
struct OnboardingProgressBar: View {
    let progress: Double   // 0.0 ... 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor.gradient)
                    .frame(width: max(6, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

// MARK: - Scaffold

/// A single onboarding step. Every step consumes this scaffold so the flow
/// feels like one document. The scaffold is intentionally opinionated —
/// steps just fill in the title / subtitle / content and let the scaffold
/// carry everything else.
struct OnboardingStepScaffold<Content: View>: View {

    /// 0..1 — how far through the flow this step sits.
    let progress: Double
    let title: String
    let subtitle: String?
    /// The main body of the step. Steps hand back their own input control.
    let content: () -> Content

    /// Primary CTA label. Nil hides the button (rare — the "you're all
    /// set" step still needs one; usually always set).
    let primaryTitle: String?
    /// Grays out the primary CTA when false.
    let primaryEnabled: Bool
    /// Called when the CTA is tapped.
    let onPrimary: () -> Void

    /// Optional secondary action shown as a plain-styled button below the
    /// primary — used for "Skip" / "Do this later" on optional steps.
    let secondaryTitle: String?
    let onSecondary: (() -> Void)?

    /// If set, shows a back chevron in the top bar that calls this closure.
    let onBack: (() -> Void)?

    init(
        progress: Double,
        title: String,
        subtitle: String? = nil,
        primaryTitle: String? = "Continue",
        primaryEnabled: Bool = true,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondary: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.onPrimary = onPrimary
        self.secondaryTitle = secondaryTitle
        self.onSecondary = onSecondary
        self.onBack = onBack
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    titleBlock
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(backdrop)
    }

    // MARK: - Top bar (back + progress)

    private var topBar: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Back")
                .transition(.opacity.combined(with: .scale))
            }
            OnboardingProgressBar(progress: progress)
                .animation(.easeInOut(duration: 0.35), value: progress)
        }
    }

    // MARK: - Title + subtitle

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            if let primaryTitle {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!primaryEnabled)
            }
            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Backdrop

    /// Soft ambient backdrop — a very subtle accent-tinted gradient at the
    /// top fading into the system grouped background, plus two drifting
    /// blurred orbs like the splash / auth gate use. Doesn't compete with
    /// the content because it's quiet on purpose.
    private var backdrop: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.16),
                    Color.accentColor.opacity(0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            BrandPalette.driftingOrb(color: Color.accentColor.opacity(0.22), size: 260)
                .offset(x: -140, y: -220)
            BrandPalette.driftingOrb(color: Color.orange.opacity(0.14), size: 220)
                .offset(x: 150, y: -140)
        }
        .ignoresSafeArea()
    }
}

#if DEBUG
#Preview("Scaffold — with back + secondary") {
    OnboardingStepScaffold(
        progress: 0.5,
        title: "What should we call you?",
        subtitle: "You'll see this on your profile and in daily nudges.",
        primaryTitle: "Continue",
        primaryEnabled: true,
        onPrimary: {},
        secondaryTitle: "Skip for now",
        onSecondary: {},
        onBack: {}
    ) {
        TextField("Your name", text: .constant(""))
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
