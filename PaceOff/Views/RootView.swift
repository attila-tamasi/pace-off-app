// RootView.swift
// Tab bar — Today / History / Trends / Profile. Settings has been folded
// into the Profile tab. By the time we reach this view the onboarding
// flow has committed a valid UserProfile — no defensive setup sheet.

import SwiftUI

struct RootView: View {

    @State private var selection: AppTab = .today

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
    }
}
