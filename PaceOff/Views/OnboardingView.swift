// OnboardingView.swift
// Three slides shown after the auth gate, before profile setup:
//   Welcome → Health → Notifications.
// Profile setup has its own non-dismissable sheet (ProfileSetupSheetView)
// presented after onComplete fires.

import SwiftUI

struct OnboardingView: View {

    let onComplete: () -> Void

    @EnvironmentObject private var health: HealthKitService
    @EnvironmentObject private var notifications: NotificationScheduler

    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            healthPermission.tag(1)
            notificationPermission.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 0 · Welcome

    private var welcome: some View {
        slide(
            symbol: "figure.run",
            headline: "Pace Off pushes you to run.",
            subtitle: "Apple Health is the source of truth. No backend, no analytics — your training stays with you.",
            buttonLabel: "Continue",
            action: { withAnimation { page = 1 } }
        )
    }

    // MARK: - 1 · Health permission

    private var healthPermission: some View {
        slide(
            symbol: "heart.text.square.fill",
            headline: "Read your run data.",
            subtitle: "Pace Off pulls VO₂ max, runs, heart rate, HRV, and running dynamics from Apple Health. Nothing leaves your device.",
            buttonLabel: "Allow Health Access",
            action: {
                Task {
                    await health.requestAuthorization()
                    withAnimation { page = 2 }
                }
            }
        )
    }

    // MARK: - 2 · Notification permission

    private var notificationPermission: some View {
        slide(
            symbol: "bell.badge.fill",
            headline: "This app works because it interrupts you.",
            subtitle: "Three pushes a day, max. Morning, afternoon, evening if you've skipped.",
            buttonLabel: "Allow Notifications",
            action: {
                Task {
                    await notifications.requestAuthorization()
                    onComplete()
                }
            }
        )
    }

    // MARK: - Shared slide layout

    private func slide(symbol: String,
                       headline: String,
                       subtitle: String,
                       buttonLabel: String,
                       action: @escaping () -> Void) -> some View {
        BrandHero(
            symbol: symbol,
            headline: headline,
            subtitle: subtitle,
            symbolSize: 96,
            showsBackdrop: false
        ) {
            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            // Leave space for the page-indicator dots.
            .padding(.bottom, 28)
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
        .environmentObject(HealthKitService.shared)
        .environmentObject(NotificationScheduler.shared)
}
