// PaceOffApp.swift
// iOS app entry point.

import SwiftUI

@main
struct PaceOffApp: App {

    @StateObject private var health = HealthKitService.shared
    @StateObject private var notifications = NotificationScheduler.shared
    @StateObject private var todayVM = TodayViewModel()

    @AppStorage(AppGroup.Keys.onboardingComplete, store: AppGroup.sharedDefaults)
    private var onboardingComplete: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    RootView()
                        .environmentObject(health)
                        .environmentObject(notifications)
                        .environmentObject(todayVM)
                        .task {
                            await todayVM.refresh()
                        }
                } else {
                    OnboardingView(onComplete: { onboardingComplete = true })
                        .environmentObject(health)
                        .environmentObject(notifications)
                }
            }
            .preferredColorScheme(.none) // respect system
            .tint(.accentColor)
        }
    }
}
