// TrendsView.swift
// Three trends in Health-style cards: VO₂ max (28 days), weekly distance
// (12 weeks) and pace (28 days). Each card leads with the latest number,
// with its chart underneath.

import SwiftUI
import Charts

struct TrendsView: View {

    @State private var vo2Max: [VO2MaxSnapshot] = []
    @State private var runs: [RunRecord] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MetricCard(
                    title: "VO₂ max",
                    systemImage: "lungs.fill",
                    tint: .accentColor,
                    detail: "Last 28 days",
                    value: recentVO2.last.map { String(format: "%.1f", $0.value) } ?? "—",
                    unit: "ml/kg/min",
                    layout: .compact
                ) {
                    vo2MaxChart.frame(height: 150).padding(.top, 6)
                }
                MetricCard(
                    title: "Weekly distance",
                    systemImage: "figure.run",
                    tint: BrandPalette.track,
                    detail: "Last 12 weeks",
                    value: String(format: "%.1f", thisWeekKm),
                    unit: "km this week",
                    layout: .compact
                ) {
                    weeklyDistanceChart.frame(height: 150).padding(.top, 6)
                }
                MetricCard(
                    title: "Pace",
                    systemImage: "speedometer",
                    tint: .teal,
                    detail: "Last 28 days",
                    value: averagePaceLabel,
                    unit: "/km avg",
                    layout: .compact
                ) {
                    paceChart.frame(height: 150).padding(.top, 6)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Trends")
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - VO₂ max

    private var recentVO2: [VO2MaxSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        return vo2Max.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    private var vo2MaxChart: some View {
        Chart(recentVO2) { snap in
            AreaMark(x: .value("Date", snap.date), y: .value("VO₂ max", snap.value))
                .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", snap.date), y: .value("VO₂ max", snap.value))
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .trailing) }
    }

    // MARK: - Weekly distance

    private var weeklyDistances: [(week: Date, km: Double)] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -84, to: Date()) ?? Date()
        let recent = runs.filter { $0.startDate >= cutoff }
        let weekly = Dictionary(grouping: recent) { run -> Date in
            cal.dateInterval(of: .weekOfYear, for: run.startDate)?.start ?? run.startDate
        }.mapValues { $0.reduce(0) { $0 + $1.distanceKm } }
        return weekly.map { (week: $0.key, km: $0.value) }.sorted { $0.week < $1.week }
    }

    private var thisWeekKm: Double {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
        return weeklyDistances.first { $0.week == start }?.km ?? 0
    }

    private var weeklyDistanceChart: some View {
        Chart(weeklyDistances, id: \.week) { entry in
            BarMark(x: .value("Week", entry.week, unit: .weekOfYear), y: .value("km", entry.km))
                .foregroundStyle(BrandPalette.trackFill)
                .cornerRadius(4)
        }
        .chartYAxis { AxisMarks(position: .trailing) }
    }

    // MARK: - Pace

    private var recentPacedRuns: [RunRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        return runs
            .filter { $0.startDate >= cutoff && ($0.averagePace ?? 0) > 0 }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Mean pace over the window as "5:32", or "—" without paced runs.
    private var averagePaceLabel: String {
        let paces = recentPacedRuns.compactMap(\.averagePace)
        guard !paces.isEmpty else { return "—" }
        let mean = Int((paces.reduce(0, +) / Double(paces.count)).rounded())
        return String(format: "%d:%02d", mean / 60, mean % 60)
    }

    /// Faster is up: the pace axis is reversed so a better run reads as a
    /// higher point, like every other trend on this screen.
    private var paceChart: some View {
        Chart(recentPacedRuns) { run in
            LineMark(x: .value("Date", run.startDate), y: .value("Pace s/km", run.averagePace ?? 0))
                .foregroundStyle(Color.teal)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", run.startDate), y: .value("Pace s/km", run.averagePace ?? 0))
                .foregroundStyle(Color.teal)
                .symbolSize(18)
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60))
                    }
                }
            }
        }
    }

    private func load() async {
        // Paint from cache immediately so the charts aren't blank.
        if let cached = await HealthDataCache.shared.load() {
            self.vo2Max = cached.vo2Max
            self.runs = cached.runs
        }
        async let v = HealthKitService.shared.fetchVO2Max(daysBack: 90)
        async let r = HealthKitService.shared.fetchRuns(daysBack: 90)
        self.vo2Max = await v
        self.runs = await r
    }
}

#if DEBUG
#Preview("Trends") {
    NavigationStack { TrendsView() }
}
#endif
