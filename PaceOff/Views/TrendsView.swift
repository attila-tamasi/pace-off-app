// TrendsView.swift
// Three sparklines: VO2Max (28d), weekly distance (12w), pace (28d).

import SwiftUI
import Charts

struct TrendsView: View {

    @State private var vo2Max: [VO2MaxSnapshot] = []
    @State private var runs: [RunRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                trendCard(
                    title: "VO₂ MAX",
                    subtitle: "Last 28 days",
                    chart: vo2MaxChart
                )
                trendCard(
                    title: "WEEKLY DISTANCE",
                    subtitle: "Last 12 weeks",
                    chart: weeklyDistanceChart
                )
                trendCard(
                    title: "PACE",
                    subtitle: "Last 28 days",
                    chart: paceChart
                )
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Trends")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func trendCard<Content: View>(title: String, subtitle: String, @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            chart()
                .frame(height: 160)
                .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func vo2MaxChart() -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let data = vo2Max.filter { $0.date >= cutoff }
        return Chart(data) { snap in
            LineMark(x: .value("Date", snap.date), y: .value("VO2Max", snap.value))
//                .foregroundStyle(.accent)
            AreaMark(x: .value("Date", snap.date), y: .value("VO2Max", snap.value))
                .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartYAxis(.hidden)
    }

    private func weeklyDistanceChart() -> some View {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -84, to: Date()) ?? Date()
        let recent = runs.filter { $0.startDate >= cutoff }
        let weekly = Dictionary(grouping: recent) { run -> Date in
            cal.dateInterval(of: .weekOfYear, for: run.startDate)?.start ?? run.startDate
        }.mapValues { $0.reduce(0) { $0 + $1.distanceKm } }
        let entries = weekly.map { (week: $0.key, km: $0.value) }.sorted { $0.week < $1.week }
        return Chart(entries, id: \.week) { e in
            BarMark(x: .value("Week", e.week, unit: .weekOfYear), y: .value("km", e.km))
//                .foregroundStyle(.accentColor)
                .cornerRadius(4)
        }
        .chartYAxis(.hidden)
    }

    private func paceChart() -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recent = runs.filter { $0.startDate >= cutoff && ($0.averagePace ?? 0) > 0 }
        return Chart(recent) { run in
            LineMark(
                x: .value("Date", run.startDate),
                y: .value("Pace s/km", run.averagePace ?? 0)
            )
//            .foregroundStyle(.accentColor)
        }
        .chartYAxis(.hidden)
    }

    private func load() async {
        async let v = HealthKitService.shared.fetchVO2Max(daysBack: 90)
        async let r = HealthKitService.shared.fetchRuns(daysBack: 90)
        self.vo2Max = await v
        self.runs = await r
    }
}
