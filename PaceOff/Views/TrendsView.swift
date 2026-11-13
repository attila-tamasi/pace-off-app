// TrendsView.swift
// Three trends in Health-style cards: VO₂ max (28 days), weekly distance
// (12 weeks) and pace (28 days). Each card leads with the latest number,
// with its chart underneath.

import SwiftUI
import Charts

struct TrendsView: View {

    @State private var vo2Max: [VO2MaxSnapshot] = []
    @State private var runs: [RunRecord] = []

    /// The runner's unit (kilometres or miles).
    private var units: UnitFormatter { .runner }
    /// False until there's something to show (the cache) or the Health
    /// read is back, so the empty lines never show while still loading.
    @State private var loaded = false

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
                    if recentVO2.isEmpty {
                        emptyChart(loaded ? "No VO₂ max readings in the last 28 days. Apple Watch records one on outdoor runs and walks." : "Loading…")
                    } else {
                        vo2MaxChart.frame(height: 150).padding(.top, 6)
                    }
                }
                MetricCard(
                    title: "Weekly distance",
                    systemImage: "figure.run",
                    tint: BrandPalette.track,
                    detail: "Last 12 weeks",
                    value: units.numberOneDecimal(thisWeekKm * 1000),
                    unit: "\(units.unit.symbol) this week",
                    layout: .compact
                ) {
                    if weeklyDistances.isEmpty {
                        emptyChart(loaded ? "No runs in the last 12 weeks. Runs saved to Apple Health show up here." : "Loading…")
                    } else {
                        weeklyDistanceChart.frame(height: 150).padding(.top, 6)
                    }
                }
                MetricCard(
                    title: "Pace",
                    systemImage: "speedometer",
                    tint: .teal,
                    detail: "Last 28 days",
                    value: averagePaceLabel,
                    unit: "/\(units.unit.symbol) avg",
                    layout: .compact
                ) {
                    if recentPacedRuns.isEmpty {
                        emptyChart(loaded ? "No runs with a pace in the last 28 days." : "Loading…")
                    } else {
                        paceChart.frame(height: 150).padding(.top, 6)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Trends")
        .task { await load() }
        .refreshable { await load() }
    }

    /// What a card shows in place of its chart when there's nothing to draw.
    private func emptyChart(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.top, 6)
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
        // Twelve whole weeks: this one and the eleven before it.
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let cutoff = cal.date(byAdding: .weekOfYear, value: -11, to: thisWeek) ?? thisWeek
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
            BarMark(x: .value("Week", entry.week, unit: .weekOfYear), y: .value(units.unit.symbol, units.value(entry.km * 1000)))
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
        return units.paceNumber(secondsPerKm: paces.reduce(0, +) / Double(paces.count))
    }

    /// Faster is up: the pace axis is reversed so a better run reads as a
    /// higher point, like every other trend on this screen.
    private var paceChart: some View {
        Chart(recentPacedRuns) { run in
            LineMark(x: .value("Date", run.startDate), y: .value("Pace", units.secondsPerUnit(secondsPerKm: run.averagePace ?? 0)))
                .foregroundStyle(Color.teal)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", run.startDate), y: .value("Pace", units.secondsPerUnit(secondsPerKm: run.averagePace ?? 0)))
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
        if let cached = await HealthDataCache.shared.load(), !cached.isEmpty {
            self.vo2Max = cached.vo2Max
            self.runs = cached.runs
            loaded = true
        }
        async let v = HealthKitService.shared.fetchVO2Max(daysBack: 90)
        async let r = HealthKitService.shared.fetchRuns(daysBack: 90)
        // A read that comes back empty over cached data is more likely a
        // locked or failed read than data gone: keep what's on screen.
        let freshVO2 = await v
        let freshRuns = await r
        if !freshVO2.isEmpty || vo2Max.isEmpty { self.vo2Max = freshVO2 }
        if !freshRuns.isEmpty || runs.isEmpty { self.runs = freshRuns }
        loaded = true
    }
}

#if DEBUG
#Preview("Trends") {
    NavigationStack { TrendsView() }
}
#endif
