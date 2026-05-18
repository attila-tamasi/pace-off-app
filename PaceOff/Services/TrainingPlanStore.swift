// TrainingPlanStore.swift
// Stores the user's *active* training plan as a JSON blob in the App Group
// container — same persistence pattern HealthDataCache uses. Single shared
// instance, MainActor-isolated so the UI can observe @Published changes.

import Foundation
import Combine

@MainActor
public final class TrainingPlanStore: ObservableObject {

    public static let shared = TrainingPlanStore()

    /// Filename inside the App Group container.
    public static let filename = "training-plan.json"

    @Published public private(set) var activePlan: TrainingPlan?

    private let fileManager = FileManager.default

    public init() {
        load()
    }

    // MARK: - URLs

    private var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(Self.filename)
    }

    // MARK: - Read

    /// Read the plan file off disk and update `activePlan`. No-op if there
    /// is no plan file yet.
    public func load() {
        guard let url = fileURL, fileManager.fileExists(atPath: url.path) else {
            activePlan = nil
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let plan = try? decoder.decode(TrainingPlan.self, from: data) {
            activePlan = plan
        } else {
            activePlan = nil
        }
    }

    // MARK: - Write

    /// Persist a plan as the active plan. Replaces any existing plan.
    @discardableResult
    public func setActive(_ plan: TrainingPlan) -> Bool {
        guard let url = fileURL else {
            activePlan = plan // hold in memory anyway so the UI updates
            return false
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(plan)
            try data.write(to: url, options: .atomic)
            activePlan = plan
            return true
        } catch {
            return false
        }
    }

    // MARK: - Clear

    /// Remove the active plan from memory and disk. Called on sign-out and
    /// from the UI when the user explicitly ends a plan.
    public func clear() {
        activePlan = nil
        if let url = fileURL {
            try? fileManager.removeItem(at: url)
        }
    }
}
