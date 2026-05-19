// RootView.swift
// Tab bar — Today / History / Trends / Profile. Settings has been folded
// into the Profile tab.

import SwiftUI

struct RootView: View {
    @Environment(ProfileStore.self) private var profileStore

    @State private var selection: AppTab = .today
    @State private var presentingProfileSetup = false

    enum AppTab: Hashable { case today, history, trends, profile }

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "figure.run", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            SwiftUI.Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryView() }
            }
            SwiftUI.Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.trends) {
                NavigationStack { TrendsView() }
            }
            SwiftUI.Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack { ProfileView() }
            }
        }
        .onAppear {
            // Defensive: if we reached the main tab bar without a complete
            // profile (e.g. mid-flow flag drift), force the setup sheet.
            if !profileStore.isSetUp {
                presentingProfileSetup = true
            }
        }
        .sheet(isPresented: $presentingProfileSetup) {
            ProfileSetupSheetView(
                initialProfile: profileStore.profile,
                initialPhoto: profileStore.photo,
                onComplete: { presentingProfileSetup = false }
            )
            .environment(profileStore)
            .interactiveDismissDisabled()
        }
    }
}

