// HeartTrendDetailView.swift
// HRV or resting heart rate over a week, a month or three months, against
// the baseline the readiness card compares with, plus what the number
// means. Pushed from the Recovery cards on Today.

import SwiftUI
import Charts

struct HeartTrendDetailView: View {
    let metric: HeartTrend.Metric

    @State private var samples: [(date: Date, value: Double)]
    @State private var range: HeartTrend.Range = .month
    @State private var isLoading = true

    /// `samples` seeds the screen before Health answers (previews pass
    /// their own).
    init(metric: HeartTrend.Metric, samples: [(date: Date, value: Double)] = []) {
        self.metric = metric
        _samples = State(initialValue: samples)
    }

    var body: some View {
        let trend = HeartTrend(metric: metric, samples: samples, range: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(trend)
                chartCard(trend)
                readinessCard(trend)
                explanationCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(copy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Summary

    private func summary(_ trend: HeartTrend) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(latestLabel(trend))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trend.latest.map { "\(Int($0.value.rounded()))" } ?? "—")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(copy.unit)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let line = baselineLine(trend) {
                Label(line.text, systemImage: line.icon)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(line.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func latestLabel(_ trend: HeartTrend) -> String {
        guard let latest = trend.latest else { return "NO RECENT READING" }
        return Calendar.current.isDateInToday(latest.date) ? "TODAY" : "YESTERDAY"
    }

    /// "8% below your 30-day baseline of 68 ms", coloured by what the
    /// readiness card makes of it; or how far the baseline still is.
    private func baselineLine(_ trend: HeartTrend) -> (text: String, icon: String, color: Color)? {
        let window = "\(trend.baselineWindowDays)-day"
        if let change = trend.change, let baseline = trend.baseline, let level = trend.level {
            let percent = Int((abs(change) * 100).rounded())
            let base = "\(window) baseline of \(Int(baseline.rounded())) \(copy.unit)"
            let color: Color
            switch level {
            case .green: color = .green
            case .yellow: color = .orange
            case .red: color = .red
            }
            if percent == 0 {
                return ("On your \(base)", "equal", color)
            }
            return change > 0
                ? ("\(percent)% above your \(base)", "arrow.up.right", color)
                : ("\(percent)% below your \(base)", "arrow.down.right", color)
        }
        guard trend.latest != nil else { return nil }
        let left = max(0, trend.baselineDaysNeeded - trend.baselineDaysSoFar)
        return ("Your baseline appears after \(left) more day\(left == 1 ? "" : "s") of readings",
                "hourglass", Color.secondary)
    }

    // MARK: - Chart

    private func chartCard(_ trend: HeartTrend) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Range", selection: $range) {
                ForEach(HeartTrend.Range.allCases) { range in
                    Text(rangeLabel(range)).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if let average = trend.average {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVERAGE")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(average.rounded()))")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text(copy.unit)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let low = trend.low, let high = trend.high {
                        Text("Range \(Int(low.rounded()))–\(Int(high.rounded())) \(copy.unit)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if trend.days.isEmpty {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    emptyState
                }
            } else {
                chart(trend)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func chart(_ trend: HeartTrend) -> some View {
        let format: Date.FormatStyle = trend.range == .week
            ? Date.FormatStyle.dateTime.weekday(.abbreviated)
            : Date.FormatStyle.dateTime.day().month(.abbreviated)
        return Chart {
            ForEach(trend.days) { day in
                LineMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(copy.unit, day.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.pink)
                PointMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(copy.unit, day.value)
                )
                .foregroundStyle(Color.pink)
                .symbolSize(trend.range == .threeMonths ? 12 : 30)
            }
            if let baseline = trend.baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Baseline \(Int(baseline.rounded()))")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: xDomain(trend))
        .chartYScale(domain: yDomain(trend))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: format)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 220)
    }

    /// The whole range, so a week with two readings still spans a week.
    private func xDomain(_ trend: HeartTrend) -> ClosedRange<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(trend.range.days - 1), to: today) ?? today
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
        return start...end
    }

    /// The readings and the baseline, padded so neither sits on the edge.
    private func yDomain(_ trend: HeartTrend) -> ClosedRange<Double> {
        var values = trend.days.map(\.value)
        if let baseline = trend.baseline { values.append(baseline) }
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let pad = max(3, (hi - lo) * 0.15)
        return max(0, lo - pad)...(hi + pad)
    }

    private func rangeLabel(_ range: HeartTrend.Range) -> String {
        switch range {
        case .week: return "Week"
        case .month: return "Month"
        case .threeMonths: return "3 Months"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: copy.symbol)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(copy.emptyTitle)
                .font(.system(.headline, design: .rounded))
            Text(copy.emptyBody)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Readiness

    private func readinessCard(_ trend: HeartTrend) -> some View {
        let yellow = Int((trend.yellowThreshold * 100).rounded())
        let red = Int((trend.redThreshold * 100).rounded())
        let direction = metric == .hrv ? "below" : "above"
        return VStack(alignment: .leading, spacing: 12) {
            Text("HOW READINESS USES IT")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)

            Text("Readiness compares \(copy.readingName) with your average over the previous \(trend.baselineWindowDays) days. It needs \(trend.baselineDaysNeeded) days of readings before it trusts that average.")
                .font(.system(.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                thresholdRow(color: .green, label: "Ready", text: "Less than \(yellow)% \(direction) your baseline")
                thresholdRow(color: .yellow, label: "Ease off", text: "\(yellow)% or more \(direction): today's target stays at your usual distance")
                thresholdRow(color: .red, label: "Rest", text: "\(red)% or more \(direction): the target is cut to 60% and the day turns to recovery")
            }

            Text("The other signal counts too: when HRV and resting heart rate are both off, the day turns red.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func thresholdRow(color: Color, label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT IT MEANS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            ForEach(copy.explanation, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.system(.body, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Pace Off is not a medical app. See a doctor about readings that worry you.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Copy

    private struct Copy {
        let title: String
        let unit: String
        let symbol: String
        let readingName: String
        let emptyTitle: String
        let emptyBody: String
        let explanation: [String]
    }

    private var copy: Copy {
        switch metric {
        case .hrv:
            return Copy(
                title: "Heart Rate Variability",
                unit: "ms",
                symbol: "waveform.path.ecg",
                readingName: "your latest HRV reading, usually last night's,",
                emptyTitle: "No HRV readings yet",
                emptyBody: "Apple Watch records HRV while you sleep. Wear it to bed, and the readings appear here the next morning.",
                explanation: [
                    "Heart rate variability is the small variation in time between heartbeats. Health measures it as SDNN, in milliseconds.",
                    "Above your own normal usually means you've recovered. A drop below it often follows hard training, short sleep, illness or stress.",
                    "Compare it with your own baseline, not with other people: normal values differ a lot from one person to the next.",
                ]
            )
        case .restingHeartRate:
            return Copy(
                title: "Resting Heart Rate",
                unit: "bpm",
                symbol: "heart",
                readingName: "your latest resting heart rate",
                emptyTitle: "No resting heart rate yet",
                emptyBody: "Apple Watch works it out from readings taken while you're still. Wear it through a day, and it appears here.",
                explanation: [
                    "Resting heart rate is how fast your heart beats when you're fully at rest.",
                    "As your running fitness grows, it tends to drift down over months.",
                    "A few beats above your normal often comes with fatigue, illness, heat, alcohol or too little sleep: a sign to keep the day easy.",
                ]
            )
        }
    }

    // MARK: - Loading

    /// The cached snapshot first, so the screen isn't empty while Health
    /// answers, then three months straight from Health.
    private func load() async {
        isLoading = true
        if samples.isEmpty, let cached = await HealthDataCache.shared.load() {
            switch metric {
            case .hrv:
                samples = cached.hrv.map { (date: $0.date, value: $0.sdnnMs) }
            case .restingHeartRate:
                samples = cached.restingHR.map { (date: $0.date, value: $0.bpm) }
            }
        }
        let days = HeartTrend.Range.threeMonths.days
        let fresh: [(date: Date, value: Double)]
        switch metric {
        case .hrv:
            fresh = await HealthKitService.shared.fetchHRVSeries(daysBack: days)
                .map { (date: $0.date, value: $0.sdnnMs) }
        case .restingHeartRate:
            fresh = await HealthKitService.shared.fetchRestingHeartRate(daysBack: days)
                .map { (date: $0.date, value: $0.bpm) }
        }
        if !fresh.isEmpty { samples = fresh }
        isLoading = false
    }
}

#if DEBUG
private func previewSamples(base: Double, spread: Double, latest: Double) -> [(date: Date, value: Double)] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let past = (1...89).compactMap { offset -> (date: Date, value: Double)? in
        guard let day = cal.date(byAdding: .hour, value: 3, to: cal.date(byAdding: .day, value: -offset, to: today)!) else { return nil }
        return (date: day, value: base + spread * sin(Double(offset) / 3))
    }
    let now = cal.date(byAdding: .hour, value: 3, to: today)!
    return past + [(date: now, value: latest)]
}

#Preview("HRV") {
    NavigationStack {
        HeartTrendDetailView(metric: .hrv, samples: previewSamples(base: 60, spread: 6, latest: 51))
    }
}

#Preview("Resting HR") {
    NavigationStack {
        HeartTrendDetailView(metric: .restingHeartRate, samples: previewSamples(base: 52, spread: 2, latest: 51))
    }
}

#Preview("HRV, no data") {
    NavigationStack {
        HeartTrendDetailView(metric: .hrv)
    }
}
#endif
