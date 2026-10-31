// RunStreak.swift
// The runner's current streak of consecutive running days. Pure, so the
// Today screen, the background refresh and the voice lines all count it the
// same way.

import Foundation

public enum RunStreak {

    /// Consecutive calendar days with at least one run, ending today, or
    /// ending yesterday when today has no run yet: a streak isn't broken
    /// until the day is over. 0 when neither today nor yesterday has a run.
    public static func current(runs: [RunRecord], today: Date, calendar: Calendar = .current) -> Int {
        let runDays = Set(runs.map { calendar.startOfDay(for: $0.startDate) })
        var cursor = calendar.startOfDay(for: today)
        if !runDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while runDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
