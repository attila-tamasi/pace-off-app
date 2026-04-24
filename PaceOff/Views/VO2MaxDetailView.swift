// VO2MaxDetailView.swift
// 1-year VO₂ max trend chart + plain-English explanation of the metric.
// Pushed from TodayView when the VO₂ MAX stat card is tapped.

import SwiftUI
import Charts

struct VO2MaxDetailView: View {

    @State private var snapshots: [VO2MaxSnapshot] = []
    @State private var isLoading = true
    @State private var userAge: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                summaryHeader

                chartCard

                explanationCard

                if let band = ageBand {
                    ageContextCard(band: band)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("VO₂ Max")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Sections

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latestValueText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("ml/kg·min")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let trend = trendLabel {
                HStack(spacing: 6) {
                    Image(systemName: trend.icon)
                    Text(trend.text)
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(trend.color)
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAST 12 MONTHS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)

            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                } else if snapshots.isEmpty {
                    emptyState
                } else {
                    chart
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var chart: some View {
        Chart(snapshots, id: \.date) { snap in
            LineMark(
                x: .value("Date", snap.date),
                y: .value("VO₂ Max", snap.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.tint)

            AreaMark(
                x: .value("Date", snap.date),
                y: .value("VO₂ Max", snap.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(
                colors: [.accentColor.opacity(0.25), .accentColor.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            ))

            PointMark(
                x: .value("Date", snap.date),
                y: .value("VO₂ Max", snap.value)
            )
            .foregroundStyle(.tint)
            .symbolSize(24)
        }
        .chartYScale(domain: yScaleDomain)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(height: 240)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lungs")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No VO₂ max data yet")
                .font(.system(.headline, design: .rounded))
            Text("Apple Watch records VO₂ max during outdoor walks and runs of 20+ minutes. Take a few outdoor runs and your number will appear here.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT IT MEANS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)

            Text("VO₂ max is the maximum amount of oxygen your body can use per minute during all-out exercise, measured in millilitres per kilogram per minute (ml/kg·min). It's the single best lab proxy for cardiorespiratory fitness.")
                .font(.system(.body, design: .rounded))

            Text("The number tends to climb when you run consistently — especially mixing easy distance with the occasional hard effort — and tends to drift down when you skip weeks. Day-to-day jitter is normal; what matters is the slope over weeks.")
                .font(.system(.body, design: .rounded))

            Text("Pace Off uses the slope of your VO₂ max over the last 6 weeks to decide today's push. A rising line means you're absorbing the work — expect bigger asks. A falling line means recovery — expect a softer day.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func ageContextCard(band: AgeBand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE YOU STAND")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)

            if let value = snapshots.last?.value, let age = userAge {
                Text("At \(age), a VO₂ max of \(String(format: "%.1f", value)) ml/kg·min sits in the \(band.classification(for: value)) range for your age group.")
                    .font(.system(.body, design: .rounded))
            } else {
                Text("Add your date of birth in the Health app to see how your VO₂ max compares to others your age.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("These bands are general fitness references — not medical guidance.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Derived data

    private var latestValueText: String {
        guard let v = snapshots.last?.value else { return "—" }
        return String(format: "%.1f", v)
    }

    private var trendLabel: (text: String, icon: String, color: Color)? {
        guard snapshots.count >= 4 else { return nil }
        // Simple linear regression slope per week over the last 6 weeks
        let cutoff = Calendar.current.date(byAdding: .day, value: -42, to: Date()) ?? Date()
        let recent = snapshots.filter { $0.date >= cutoff }
        guard recent.count >= 3 else { return nil }
        let slope = weeklySlope(recent)
        if slope > 0.05 {
            return ("Up \(String(format: "%.2f", slope)) ml/kg·min per week", "arrow.up.right", .green)
        } else if slope < -0.05 {
            return ("Down \(String(format: "%.2f", abs(slope))) ml/kg·min per week", "arrow.down.right", .orange)
        } else {
            return ("Stable over the last 6 weeks", "arrow.right", .secondary)
        }
    }

    private var yScaleDomain: ClosedRange<Double> {
        let values = snapshots.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 30...60 }
        let pad = max(2.0, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }

    private var ageBand: AgeBand? {
        guard let age = userAge else { return AgeBand(age: 35) } // generic fallback band so the card still teaches something
        return AgeBand(age: age)
    }

    private func weeklySlope(_ data: [VO2MaxSnapshot]) -> Double {
        guard let first = data.first?.date else { return 0 }
        let xs = data.map { $0.date.timeIntervalSince(first) / (7 * 24 * 3600) } // weeks
        let ys = data.map(\.value)
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = (n * sumX2) - (sumX * sumX)
        guard denom != 0 else { return 0 }
        return ((n * sumXY) - (sumX * sumY)) / denom
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        snapshots = await HealthKitService.shared.fetchVO2Max(daysBack: 365)
        userAge = HealthKitService.shared.userAge()
        isLoading = false
    }
}

/// Rough VO₂ max bands used to give the user context. These are reference
/// ranges drawn from common fitness literature (Cooper Institute / ACSM-style
/// bandings) and intentionally coarse — Pace Off is not a medical app.
private struct AgeBand {
    let age: Int

    func classification(for value: Double) -> String {
        // Female- and male-specific thresholds vary; we use a reasonable midpoint
        // because the app does not currently read biological sex from HealthKit.
        let (poor, fair, good, excellent): (Double, Double, Double, Double)
        switch age {
        case ..<30:    (poor, fair, good, excellent) = (35, 42, 49, 56)
        case 30..<40:  (poor, fair, good, excellent) = (33, 40, 47, 54)
        case 40..<50:  (poor, fair, good, excellent) = (31, 38, 44, 51)
        case 50..<60:  (poor, fair, good, excellent) = (28, 35, 41, 48)
        case 60..<70:  (poor, fair, good, excellent) = (25, 31, 37, 44)
        default:       (poor, fair, good, excellent) = (22, 28, 33, 39)
        }
        switch value {
        case ..<poor:           return "below average"
        case poor..<fair:       return "fair"
        case fair..<good:       return "good"
        case good..<excellent:  return "excellent"
        default:                return "elite"
        }
    }
}
