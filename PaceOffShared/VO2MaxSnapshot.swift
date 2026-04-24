// VO2MaxSnapshot.swift
// A single VO2Max reading from HealthKit, used to compute the trend slope.

import Foundation

public struct VO2MaxSnapshot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    /// VO2Max in ml/kg/min — Apple Health's native unit.
    public let value: Double

    public init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

public struct RestingHeartRateSnapshot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let bpm: Double

    public init(id: UUID = UUID(), date: Date, bpm: Double) {
        self.id = id
        self.date = date
        self.bpm = bpm
    }
}
