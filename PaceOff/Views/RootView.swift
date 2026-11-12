// RootView.swift
// Tab bar — Today / History / Trends / Plan. Profile lives behind the
// avatar on Today, as in the Health app. By the time we reach this view
// the onboarding flow has committed a valid UserProfile — no defensive
// setup sheet.

import SwiftUI

struct RootView: View {

    @State private var navigation = AppNavigation()

    var body: some View {
        TabView(selection: $navigation.tab) {
            SwiftUI.Tab("Today", systemImage: "figure.run", value: AppNavigation.Tab.today) {
                NavigationStack { TodayView() }
            }
            SwiftUI.Tab("History", systemImage: "clock.arrow.circlepath", value: AppNavigation.Tab.history) {
                NavigationStack { HistoryView() }
            }
            SwiftUI.Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: AppNavigation.Tab.trends) {
                NavigationStack { TrendsView() }
            }
            SwiftUI.Tab("Plan", systemImage: "list.bullet.rectangle.portrait", value: AppNavigation.Tab.plan) {
                NavigationStack { PlanTabView() }
            }
        }
        .environment(navigation)
        .onReceive(NotificationCenter.default.publisher(for: .paceOffOpenToday)) { _ in
            navigation.tab = .today
        }
    }
}

/// Which tab is showing, shared through the environment so a screen deep
/// in one tab can switch to another.
@MainActor
@Observable
final class AppNavigation {
    enum Tab: Hashable { case today, history, trends, plan }

    var tab: Tab = .today
}
