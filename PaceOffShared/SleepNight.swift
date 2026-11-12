// SleepNight.swift
// One night's time asleep, from Health's sleep analysis: the asleep stages
// added up (core, deep, REM, unspecified), never split by stage. Against a
// sleep lab the Apple Watch under-reads deep sleep by about 43 minutes, so
// only the total is used. Pure and Sendable; HealthKitService hands in the
// asleep intervals.

import Foundation

public struct SleepNight: Codable, Sendable, Equatable {
    /// The start of the day the runner woke on: a night from Monday to
    /// Tuesday is Tuesday's.
    public let night: Date
    public let asleepSeconds: Double

    public init(night: Date, asleepSeconds: Double) {
        self.night = night
        self.asleepSeconds = asleepSeconds
    }

    public var asleepHours: Double { asleepSeconds / 3600 }

    /// Asleep intervals summed per night, oldest first. Overlapping
    /// intervals (the watch and the phone both recording) count once. A
    /// night runs noon to noon and belongs to the day it ends on, so sleep
    /// from 23:00 to 07:00 and a doze at 01:00 land on the same night.
    public static func nights(from intervals: [DateInterval], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var byNight: [Date: Double] = [:]
        for interval in merged {
            let night = calendar.startOfDay(for: interval.start.addingTimeInterval(12 * 3600))
            byNight[night, default: 0] += interval.duration
        }
        return byNight.map { SleepNight(night: $0.key, asleepSeconds: $0.value) }.sorted { $0.night < $1.night }
    }
}
