// PaceOffApp.swift
// iOS app entry point. Owns the launch-flow state machine:
//   .splash → .auth → .onboarding → .profileSetup → .main

import SwiftUI

@main
struct PaceOffApp: App {

    @StateObject private var health = HealthKitService.shared
    @StateObject private var notifications = NotificationScheduler.shared
    @StateObject private var todayVM = TodayViewModel()
    @StateObject private var profileStore = ProfileStore.shared
    @StateObject private var appleSignIn = AppleSignInService.shared

    @AppStorage(AppGroup.Keys.authComplete, store: AppGroup.sharedDefaults)
    private var authComplete: Bool = false
    @AppStorage(AppGroup.Keys.onboardingComplete, store: AppGroup.sharedDefaults)
    private var onboardingComplete: Bool = false

    @State private var stage: Stage = .splash

    @Environment(\.scenePhase) private var scenePhase

    enum Stage {
        case splash
        case auth
        case onboarding
        case profileSetup
        case main
    }

    init() {
        // BGTaskScheduler refuses registrations after launch finishes, so we
        // register the handler here, before any scene attaches.
        BackgroundRefreshService.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            content
                .environmentObject(health)
                .environmentObject(notifications)
                .environmentObject(todayVM)
                .environmentObject(profileStore)
                .environmentObject(appleSignIn)
                .preferredColorScheme(.none)
                .tint(.accentColor)
                .animation(.easeInOut(duration: 0.35), value: stage)
                .onReceive(NotificationCenter.default.publisher(for: .paceOffSignOut)) { _ in
                    handleSignOut()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Returning to foreground — refresh the health cache so the
                // UI catches up with any data Apple Watch synced while we
                // were backgrounded.
                if stage == .main {
                    Task { await todayVM.refresh() }
                }
            case .background:
                // Queue another BG refresh so iOS has a fresh request to
                // dispatch ~6 hours from now.
                BackgroundRefreshService.shared.scheduleNext()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .splash:
            SplashView(onFinished: advanceFromSplash)
                .transition(.opacity)

        case .auth:
            AuthGateView(onAuthenticated: completeAuth)
                .transition(.opacity)

        case .onboarding:
            OnboardingView(onComplete: completeOnboarding)
                .transition(.opacity)

        case .profileSetup:
            ProfileSetupSheetView(
                initialProfile: profileStore.profile,
                initialPhoto: profileStore.photo,
                onComplete: completeProfileSetup
            )
            .transition(.opacity)

        case .main:
            RootView()
                .task {
                    // Show cached data immediately, then refresh in the
                    // background. First launch falls straight through to
                    // refresh() since hydrate is a no-op without a file.
                    await todayVM.hydrateFromCache()
                    await todayVM.refresh()
                    await appleSignIn.refreshCredentialState()
                }
                .transition(.opacity)
        }
    }

    // MARK: - Transitions

    private func advanceFromSplash() {
        if !authComplete {
            stage = .auth
        } else if !onboardingComplete {
            stage = .onboarding
        } else if !profileStore.isSetUp {
            stage = .profileSetup
        } else {
            stage = .main
        }
    }

    private func completeAuth() {
        authComplete = true
        stage = .onboarding
    }

    private func completeOnboarding() {
        onboardingComplete = true
        if profileStore.isSetUp {
            stage = .main
        } else {
            stage = .profileSetup
        }
    }

    private func completeProfileSetup() {
        stage = .main
    }

    private func handleSignOut() {
        // ProfileStore.signOut() already cleared persisted state; just reset
        // the flow flags and snap back to the auth gate.
        authComplete = false
        onboardingComplete = false
        stage = .auth
    }
}

extension Notification.Name {
    /// Posted by ProfileStore.signOut() so the app shell can reset its flow.
    static let paceOffSignOut = Notification.Name("PaceOffSignOut")
}
