// AppleIntelligenceCopy.swift
// On-device Apple Intelligence rewriter for the drill-sergeant voice lines.
//
// Uses the FoundationModels framework (iOS 26+) to ask Apple's on-device LLM
// to rewrite a canned VoiceCopy line in a fresh, more creative variation —
// keeping the meaning and the drill-sergeant register, but avoiding the
// repetition that comes from a fixed copy table.
//
// Everything runs on-device; no network call is made and no data leaves the
// phone. On hardware/OS combinations without Apple Intelligence support, or
// when the model is downloading / temporarily unavailable, `rewrite` returns
// nil and callers fall back to the canned VoiceCopy line. A rewrite is used
// only when `NarrationCheck` finds the original's numbers in it, so the
// model can change the wording of the advice, never the advice.
//
// Foreground only: the system rate-limits the model for apps in the
// background, so the background refresh uses the canned lines.

import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
public final class AppleIntelligenceCopy {

    public static let shared = AppleIntelligenceCopy()

    public enum Kind {
        case todayCard       // ~12 words, two short sentences
        case notification    // ~8 words, one punchy sentence
    }

    /// Hard wall-clock cap. Even on-device inference can take a second or two
    /// on first call (the model warms up); we never want to block UI or a
    /// background refresh task long enough to matter.
    private static let timeoutSeconds: TimeInterval = 4.0

    private let log = Logger(subsystem: "com.paceoff.app", category: "AppleIntelligence")

    private struct CacheKey: Hashable {
        let kind: Kind
        let original: String
    }

    /// Accepted rewrites by the canned line they came from, so a refresh
    /// that produces the same line shows the same rewrite without asking
    /// the model again.
    private var accepted: [CacheKey: String] = [:]
    private static let cacheLimit = 16

    private init() {}

    /// Rewrite `original` in a fresh variation. Returns `nil` (callers should
    /// fall back) when Apple Intelligence is unavailable, the model errors,
    /// or its line fails `NarrationCheck`. Call from the foreground only.
    public func rewrite(_ original: String, kind: Kind) async -> String? {
        guard !original.isEmpty else { return nil }
        let key = CacheKey(kind: kind, original: original)
        if let cached = accepted[key] { return cached }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let line = await rewriteWithFoundationModels(original, kind: kind) else { return nil }
            if accepted.count >= Self.cacheLimit { accepted.removeAll() }
            accepted[key] = line
            return line
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func rewriteWithFoundationModels(_ original: String, kind: Kind) async -> String? {
        // Bail early if the device doesn't have Apple Intelligence enabled
        // (older Apple silicon, region restrictions, "downloading model", etc).
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            log.info("Apple Intelligence unavailable: \(String(describing: reason), privacy: .public)")
            return nil
        @unknown default:
            return nil
        }

        let instructions = Self.systemInstructions(for: kind)
        let prompt = Self.userPrompt(original: original, kind: kind)

        do {
            return try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: prompt)
                    return await Self.sanitize(response.content, original: original)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                    return nil // timeout sentinel
                }
                let first = try await group.next()
                group.cancelAll()
                return first ?? nil
            }
        } catch {
            log.error("Foundation model rewrite failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
    #endif

    // MARK: - Prompt construction

    private static func systemInstructions(for kind: Kind) -> String {
        switch kind {
        case .todayCard:
            return """
            You are the voice of Pace Off, a running app written in a drill-sergeant tone.
            Your job: rewrite the user's input into one fresh variation that keeps the same meaning, numbers, and intent.
            Constraints:
            - Maximum 14 words. No emoji. No exclamation points.
            - Direct and a little blunt, but never cruel.
            - Preserve every distance, day count, and number exactly, written in digits as given. Add no other numbers.
            - Output only the rewritten line. No quotes, no preamble.
            """
        case .notification:
            return """
            You are the voice of Pace Off, a running app written in a drill-sergeant tone.
            Your job: rewrite the user's input into one fresh push-notification variation.
            Constraints:
            - Maximum 9 words. No emoji. No exclamation points.
            - Punchy, direct, ends with a period.
            - Preserve every distance, day count, and number exactly, written in digits as given. Add no other numbers.
            - Output only the rewritten line. No quotes, no preamble.
            """
        }
    }

    private static func userPrompt(original: String, kind: Kind) -> String {
        "Rewrite this line: \(original)"
    }

    /// Strip the quotes the model sometimes wraps its line in, then keep the
    /// line only if `NarrationCheck` accepts it: the original's numbers,
    /// none added, within the length cap.
    private static func sanitize(_ raw: String, original: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trim wrapping quotes if the model added them.
        if let first = s.first, let last = s.last,
           (first == "\"" || first == "“") && (last == "\"" || last == "”") {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard NarrationCheck.accepts(s, for: original) else { return nil }
        return s
    }
}
