// Tone.swift
// The voice register the app uses for a given push.
// PRD §8 — drill sergeant only in MVP, but the enum is the seam where future tones plug in.

import Foundation

public enum Tone: String, Codable, Sendable, CaseIterable {
    case neutral      // streak day 1, baseline
    case firm         // VO2Max plateau, 1 day skipped
    case aggressive   // VO2Max declining, 2 days skipped
    case restart      // 3+ days skipped — restart, don't catch up
    case recovery     // yesterday was a long run
    case victory      // run completed, hit target
    case shortfall    // run completed, missed target

    public var displayName: String {
        switch self {
        case .neutral:    return String(localized: "Neutral")
        case .firm:       return String(localized: "Firm")
        case .aggressive: return String(localized: "Aggressive")
        case .restart:    return String(localized: "Restart")
        case .recovery:   return String(localized: "Recovery")
        case .victory:    return String(localized: "Done")
        case .shortfall:  return String(localized: "Short")
        }
    }
}
