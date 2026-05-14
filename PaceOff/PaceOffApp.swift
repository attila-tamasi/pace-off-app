// PaceOffApp.swift
// iOS app entry point.

import SwiftUI

@main
struct PaceOffApp: App {

    @StateObject private var health = HealthKitService.shared
    @StateObject private var notifications = NotificationScheduler.shared
    @StateObject private var todayVM = TodayViewModel()
    @StateObject private var profileStore = ProfileStore.shared
    @StateObject private var appleSignIn = AppleSignInService.shared

    @AppStorage(AppGroup.Keys.onboardingComplete, store: AppGroup.sharedDefaults)
    private var onboardingComplete: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // BGTaskScheduler refuses registrations after launch finishes, so we
        // register the handler here, before any scene attaches.
        BackgroundRefreshService.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    RootView()
                        .environmentObject(health)
                        .environmentObject(notifications)
                        .environmentObject(todayVM)
                        .environmentObject(profileStore)
                        .environmentObject(appleSignIn)
                        .task {
                            await todayVM.refresh()
                            await appleSignIn.refreshCredentialState()
                        }
                } else {
                    OnboardingView(onComplete: { onboardingComplete = true })
                        .environmentObject(health)
                        .environmentObject(notifications)
                        .environmentObject(profileStore)
                        .environmentObject(appleSignIn)
                }
            }
            .preferredColorScheme(.none) // respect system
            .tint(.accentColor)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Whenever we head into the background, queue another refresh so
            // iOS has a fresh request to dispatch ~6 hours from now.
            if newPhase == .background {
                BackgroundRefreshService.shared.scheduleNext()
            }
        }
    }
}
