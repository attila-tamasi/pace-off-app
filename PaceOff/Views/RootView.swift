// RootView.swift
// Tab bar — Today / History / Trends / Settings.

import SwiftUI

struct RootView: View {
    @State private var selection: AppTab = .today

    enum AppTab: Hashable { case today, history, trends, settings }

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
            SwiftUI.Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
    }
}
