// ReadinessDetailView.swift
// How today's readiness came about, opened from Today's Readiness card:
// the verdict, HRV, resting heart rate and last night's sleep each against
// its baseline with what it says on its own (the heart signals open their
// detail screens), how the three combine, and what each colour does to
// today's target.

import SwiftUI

struct ReadinessDetailView: View {

    @Environment(TodayViewModel.self) private var todayVM

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let readiness = todayVM.readiness {
                    verdict(readiness)
                    MetricSectionHeader(title: "The signals")
                    VStack(spacing: 10) {
                        signalCard(.hrv, value: readiness.hrvMs, baseline: readiness.hrvBaselineMs)
                        signalCard(.restingHeartRate, value: readiness.restingHR, baseline: readiness.restingHRBaseline)
                        sleepCard(hours: readiness.sleepHours, baseline: readiness.sleepBaselineHours)
                        feelingCard(readiness.feeling)
                    }
                } else {
                    notYet
                }
                rulesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Readiness")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Verdict

    private func verdict(_ readiness: DailyReadiness) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor(readiness.level))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(label(readiness.level))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            }
            Text(readiness.sentence)
                .font(.system(.body, design: .rounded, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text(workedOut(readiness.computedAt))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Signals

    /// One signal against its baseline, and what it says on its own. Opens
    /// the signal's detail screen.
    private func signalCard(_ metric: HeartTrend.Metric, value: Double?, baseline: Double?) -> some View {
        let isHRV = metric == .hrv
        let unit = isHRV ? "ms" : "bpm"
        let level = value.flatMap { v in baseline.flatMap { HeartTrend.level(for: metric, value: v, baseline: $0) } }
        let note: String
        if let value, let baseline, baseline > 0 {
            let change = value / baseline - 1
            // Rounded toward zero, so the shown percent never crosses a
            // threshold the grade hasn't.
            let percent = Int((abs(change) * 100).rounded(.towardZero))
            let direction = percent == 0 ? "on" : (change > 0 ? "\(percent)% above" : "\(percent)% below")
            let window = isHRV ? ReadinessEngine.hrvBaselineWindowDays : ReadinessEngine.rhrBaselineWindowDays
            note = "\(direction) your \(window)-day baseline of \(Int(baseline.rounded())) \(unit)"
        } else {
            // Readiness keeps a signal's numbers only when it has both a
            // recent reading and a baseline to compare it with.
            note = "Not counted today: no reading since yesterday, or not enough days yet for a baseline"
        }

        return NavigationLink {
            HeartTrendDetailView(metric: metric)
        } label: {
            MetricCard(
                title: isHRV ? "HRV" : "Resting HR",
                systemImage: "heart.fill",
                tint: .pink,
                detail: level.map { label($0) },
                showsChevron: true,
                value: value.map { "\(Int($0.rounded()))" } ?? "—",
                unit: unit,
                note: note
            ) {
                if let level {
                    Circle()
                        .fill(dotColor(level))
                        .frame(width: 14, height: 14)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Last night's time asleep against the 14-night average, and what it
    /// says on its own.
    private func sleepCard(hours: Double?, baseline: Double?) -> some View {
        let level = hours.flatMap { h in baseline.map { ReadinessEngine.sleepLevel(hours: h, baseline: $0) } }
        let note: String
        if let hours, let baseline, baseline > 0 {
            let change = hours / baseline - 1
            // Rounded toward zero, so the shown percent never crosses a
            // threshold the grade hasn't.
            let percent = Int((abs(change) * 100).rounded(.towardZero))
            let direction = percent == 0 ? "on" : (change > 0 ? "\(percent)% above" : "\(percent)% below")
            note = "\(direction) your \(ReadinessEngine.sleepBaselineWindowDays)-night average of \(ReadinessEngine.sleepText(hours: baseline))"
        } else {
            note = "Not counted today: no night recorded, or fewer than \(ReadinessEngine.minSleepBaselineNights) nights for an average"
        }
        return MetricCard(
            title: "Sleep",
            systemImage: "bed.double.fill",
            tint: .teal,
            detail: level.map { label($0) },
            showsChevron: false,
            value: hours.map { ReadinessEngine.sleepText(hours: $0) } ?? "—",
            unit: "asleep",
            note: note
        ) {
            if let level {
                Circle()
                    .fill(dotColor(level))
                    .frame(width: 14, height: 14)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The runner's own answer this morning and what it does.
    private func feelingCard(_ feeling: CheckInFeeling?) -> some View {
        let level: ReadinessLevel? = feeling.map {
            switch $0 {
            case .fresh, .normal: return .green
            case .tired, .sore: return .yellow
            case .unwell: return .red
            }
        }
        let note: String = switch feeling {
        case nil: "Not answered today. Answer on Today, and it joins the watch's signals"
        case .fresh?, .normal?: "Counts as on track. It never lifts what the watch says"
        case .tired?, .sore?: "Counts as one signal off: with another one off, the day turns red"
        case .unwell?: "Unwell turns the day red: rest today"
        }
        return MetricCard(
            title: "How you feel",
            systemImage: "hand.raised.fill",
            tint: BrandPalette.track,
            detail: level.map { label($0) },
            showsChevron: false,
            value: feeling?.displayName ?? "—",
            note: note
        ) {
            if let level {
                Circle()
                    .fill(dotColor(level))
                    .frame(width: 14, height: 14)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
            }
        }
    }

    private var notYet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No readiness today")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Readiness needs a reading from Apple Watch since yesterday, and \(ReadinessEngine.minHRVBaselineDays) days of HRV, \(ReadinessEngine.minRHRBaselineDays) days of resting heart rate or \(ReadinessEngine.minSleepBaselineNights) nights of sleep to compare it with. Until it has both, the card stays hidden and today's target ignores it.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Rules

    private var rulesCard: some View {
        let hrvYellow = percent(HeartTrend.yellowThreshold(for: .hrv))
        let hrvRed = percent(HeartTrend.redThreshold(for: .hrv))
        let rhrYellow = percent(HeartTrend.yellowThreshold(for: .restingHeartRate))
        let rhrRed = percent(HeartTrend.redThreshold(for: .restingHeartRate))
        let sleepYellow = percent(ReadinessEngine.sleepYellowShort)
        let sleepRed = percent(ReadinessEngine.sleepRedShort)
        return VStack(alignment: .leading, spacing: 12) {
            Text("HOW IT'S DECIDED")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)

            Text("Each signal is graded against your own baseline, and your morning answer counts as one more. The worst one sets the day, and when two are off the day turns red. Unwell turns it red on its own.")
                .font(.system(.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            ruleRow(.green, "Ready",
                    "HRV less than \(hrvYellow)% below, resting HR less than \(rhrYellow)% above and sleep less than \(sleepYellow)% short. Today's target is set as usual.")
            ruleRow(.yellow, "Ease off",
                    "HRV \(hrvYellow)% or more below, resting HR \(rhrYellow)% or more above, or sleep \(sleepYellow)% or more short. The target goes no higher than your usual distance and an aggressive tone softens.")
            ruleRow(.red, "Rest",
                    "HRV \(hrvRed)% or more below, resting HR \(rhrRed)% or more above, sleep \(sleepRed)% or more short, or two signals off. The target is capped at \(Int((PushTargetEngine.redReadinessCapFactor * 100).rounded()))% of your usual distance and the day turns to recovery.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func ruleRow(_ level: ReadinessLevel, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(dotColor(level))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    /// "Worked out at 07:12", with the day when it isn't today's.
    private func workedOut(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Worked out at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Worked out \(date.formatted(date: .abbreviated, time: .shortened)), not yet refreshed today"
    }

    private func percent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }

    private func label(_ level: ReadinessLevel) -> String {
        switch level {
        case .green: return "Ready"
        case .yellow: return "Ease off"
        case .red: return "Rest"
        }
    }

    private func dotColor(_ level: ReadinessLevel) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

#if DEBUG
#Preview("Readiness") {
    NavigationStack { ReadinessDetailView() }
        .environment(TodayViewModel.preview(readiness: .sampleRed))
}

#Preview("Readiness, no history") {
    NavigationStack { ReadinessDetailView() }
        .environment(TodayViewModel.preview(readiness: nil))
}
#endif
