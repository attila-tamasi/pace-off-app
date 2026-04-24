// OnboardingView.swift
// Three screens: welcome → Health permission → Notification permission.

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

    private var welcome: some View {
        page(icon: "figure.run",
            title: "Pace Off pushes you to run.",
            subtitle: "Apple Health is the source of truth.",
            buttonLabel: "Continue",
            action: { withAnimation { page = 1 } }
        )
    }

    private var healthPermission: some View {
        page(icon: "heart.text.square.fill",
            title: "Read your run data.",
            subtitle: "Pace Off pulls VO₂ max, runs, heart rate, and running dynamics from Apple Health. Nothing leaves your device.",
            buttonLabel: "Allow Health Access",
            action: {
                Task {
                    await health.requestAuthorization()
                    withAnimation { page = 2 }
                }
            }
        )
    }

    private var notificationPermission: some View {
        page(icon: "bell.badge.fill",
            title: "This app works because it interrupts you.",
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

    private func page(icon: String, title: String, subtitle: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
        .environmentObject(HealthKitService.shared)
        .environmentObject(NotificationScheduler.shared)
}

