// PaceOffWatchApp.swift
// watchOS app entry point.

import SwiftUI

@main
struct PaceOffWatchApp: App {

    @StateObject private var session = WorkoutSessionManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if session.isRunning {
                    RunningWorkoutView()
                        .environmentObject(session)
                } else {
                    WatchTodayView()
                        .environmentObject(session)
                }
            }
        }
    }
}
