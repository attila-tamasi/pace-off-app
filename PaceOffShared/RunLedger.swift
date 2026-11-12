// RunLedger.swift
// Pace Off's memory of past days: the prescription each day showed (kind,
// distance, pace band, what changed it) and the day each run belongs to.
// Health keeps the runs; nothing else keeps what Pace Off asked for. The
// run review, plan adherence for past weeks, shoes, the recap and an
// adaptive plan read it.
//
// Written by a fresh Health sync (foreground or background): today's row is
// replaced by each later refresh the same day, past days are never
// rewritten. Stored as `run-ledger.json` in the App Group container, on the
// device only, and erased with the runner's other data.

import Foundation

/// A day's prescription as it was shown.
public struct LedgerPrescription: Codable, Equatable, Sendable {
    public let kind: DayPrescription.Kind
    public let source: DayPrescription.Source
    public let workoutKind: WorkoutKind?
    public let distanceMeters: Double?
    public let paceMinSecPerKm: Double?
    public let paceMaxSecPerKm: Double?
    /// What readiness did to the plan's workout, nil when nothing.
    public let adjustment: DayPrescription.Adjustment?
    /// The distance the single-run cap kept the run to, when it cut it.
    public let cappedAtMeters: Double?
    /// The plan's own distance that day, when it differs from the one shown.
    public let planDistanceMeters: Double?
    /// The day's readiness, nil when unknown.
    public let readiness: ReadinessLevel?

    public init(_ day: DayPrescription, readiness: ReadinessLevel?) {
        kind = day.kind
        source = day.source
        workoutKind = day.workoutKind
        distanceMeters = day.distanceMeters
        paceMinSecPerKm = day.paceMinSecPerKm
        paceMaxSecPerKm = day.paceMaxSecPerKm
        adjustment = day.adjustment
        cappedAtMeters = day.cappedAtMeters
        let planDistance = day.planWorkout?.distanceMeters
        planDistanceMeters = planDistance == day.distanceMeters ? nil : planDistance
        self.readiness = readiness
    }
}

/// One day in the ledger.
public struct LedgerDay: Codable, Equatable, Sendable {
    /// The start of the day.
    public let day: Date
    public let prescription: LedgerPrescription?
    /// The runner's check-in answer that day, nil when skipped.
    public let feeling: CheckInFeeling?
    /// When the row was last written.
    public let recordedAt: Date

    public init(day: Date, prescription: LedgerPrescription?, feeling: CheckInFeeling? = nil, recordedAt: Date) {
        self.day = day
        self.prescription = prescription
        self.feeling = feeling
        self.recordedAt = recordedAt
    }
}

/// A run and the day it belongs to, by its Health workout UUID.
public struct LedgerRun: Codable, Equatable, Sendable {
    public let id: UUID
    public let day: Date

    public init(id: UUID, day: Date) {
        self.id = id
        self.day = day
    }
}

/// The whole ledger, as stored.
public struct RunLedgerFile: Codable, Equatable, Sendable {
    public static let currentSchema = 1
    /// Rows older than this are dropped, so the file stays small.
    public static let keepDays = 730

    public var schemaVersion: Int
    /// Oldest first.
    public var days: [LedgerDay]
    /// Oldest first.
    public var runs: [LedgerRun]

    public init(schemaVersion: Int = RunLedgerFile.currentSchema, days: [LedgerDay] = [], runs: [LedgerRun] = []) {
        self.schemaVersion = schemaVersion
        self.days = days
        self.runs = runs
    }

    /// Missing fields decode as empty, so a file written by an older or
    /// newer version still opens.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchema
        days = (try? c.decodeIfPresent([LedgerDay].self, forKey: .days)) ?? []
        runs = (try? c.decodeIfPresent([LedgerRun].self, forKey: .runs)) ?? []
    }

    public func day(_ date: Date, calendar: Calendar = .current) -> LedgerDay? {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.day == start }
    }

    /// The runs recorded on `date`'s day.
    public func runIDs(on date: Date, calendar: Calendar = .current) -> [UUID] {
        let start = calendar.startOfDay(for: date)
        return runs.filter { $0.day == start }.map(\.id)
    }

    /// The ledger with today's row written: today's prescription replaces
    /// any row already there for today, a past day's row is never touched,
    /// and each run not seen before is filed under the day it started on.
    public func recording(prescription: DayPrescription?,
                          readiness: ReadinessLevel?,
                          feeling: CheckInFeeling? = nil,
                          runs newRuns: [RunRecord],
                          now: Date,
                          calendar: Calendar = .current) -> RunLedgerFile {
        let today = calendar.startOfDay(for: now)
        var file = self
        file.days.removeAll { $0.day == today }
        file.days.append(LedgerDay(day: today,
                                   prescription: prescription.map { LedgerPrescription($0, readiness: readiness) },
                                   feeling: feeling,
                                   recordedAt: now))
        let known = Set(file.runs.map(\.id))
        for run in newRuns.sorted(by: { $0.startDate < $1.startDate }) where !known.contains(run.id) {
            let day = calendar.startOfDay(for: run.startDate)
            guard day <= today else { continue }
            file.runs.append(LedgerRun(id: run.id, day: day))
        }
        if let earliest = calendar.date(byAdding: .day, value: -Self.keepDays, to: today) {
            file.days.removeAll { $0.day < earliest }
            file.runs.removeAll { $0.day < earliest }
        }
        file.days.sort { $0.day < $1.day }
        return file
    }
}

/// Reads and writes `RunLedgerFile`. An actor: the foreground refresh and
/// the background task can land together.
public actor RunLedger {

    public static let shared = RunLedger(fileURL: AppGroup.containerURL?.appendingPathComponent(RunLedger.filename))

    /// Filename inside the App Group container.
    public static let filename = "run-ledger.json"

    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The ledger on disk; empty when there's none yet or it can't be read.
    public func load() -> RunLedgerFile {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(RunLedgerFile.self, from: data)
        else { return RunLedgerFile() }
        return file
    }

    /// Writes today's row (`RunLedgerFile.recording`) and returns the ledger.
    @discardableResult
    public func record(prescription: DayPrescription?,
                       readiness: ReadinessLevel?,
                       feeling: CheckInFeeling? = nil,
                       runs: [RunRecord],
                       now: Date = Date()) -> RunLedgerFile {
        let file = load().recording(prescription: prescription, readiness: readiness, feeling: feeling,
                                    runs: runs, now: now)
        if let fileURL, let data = try? JSONEncoder().encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return file
    }
}
