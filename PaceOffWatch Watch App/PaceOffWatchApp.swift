// PaceOffWatchApp.swift
// watchOS app entry point.

import SwiftUI

@main
struct PaceOffWatchApp: App {

    @State private var session = WorkoutSessionManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if session.isRunning {
                    RunningWorkoutView()
                        .environment(session)
                } else {
                    WatchTodayView()
                        .environment(session)
                }
            }
        }
    }
}
