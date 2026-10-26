// MetricCard.swift
// Health-app-style data card: a coloured symbol and category name on top
// (with an optional time or chevron on the right), a big rounded value
// with its unit, an optional note, and an optional mini chart. Cards are
// solid grouped-background surfaces, as in Health: Liquid Glass stays on
// the navigation layer, where Apple uses it, so the numbers stay crisp.

import SwiftUI
import Charts

/// Where a `MetricCard` puts its mini chart.
enum MetricCardLayout {
    /// Full-width card: the chart sits to the right of the value.
    case wide
    /// Half-width card: the chart sits under the value.
    case compact
}

struct MetricCard<Accessory: View>: View {

    let title: String
    let systemImage: String
    let tint: Color
    var detail: String? = nil
    var showsChevron: Bool = false
    let value: String
    var unit: String? = nil
    var note: String? = nil
    var layout: MetricCardLayout = .wide
    @ViewBuilder var chart: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch layout {
            case .wide:
                HStack(alignment: .bottom, spacing: 12) {
                    valueBlock
                    Spacer(minLength: 0)
                    chart()
                }
            case .compact:
                valueBlock
                Spacer(minLength: 0)
                chart()
            }
        }
        .padding(16)
        // Fills the height it's offered, so cards side by side in an
        // HStack with a fixed vertical size line up like Health's.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension MetricCard where Accessory == EmptyView {
    init(title: String,
         systemImage: String,
         tint: Color,
         detail: String? = nil,
         showsChevron: Bool = false,
         value: String,
         unit: String? = nil,
         note: String? = nil,
         layout: MetricCardLayout = .wide) {
        self.init(title: title, systemImage: systemImage, tint: tint,
                  detail: detail, showsChevron: showsChevron,
                  value: value, unit: unit, note: note, layout: layout) {
            EmptyView()
        }
    }
}

/// Section heading in the Health app's style: bold title, optional link
/// on the right.
struct MetricSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.title3, weight: .bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26)
            .padding(.bottom, 10)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Mini charts

/// Axis-free line for a card: the shape of the last few readings, with a
/// dot on the latest one.
struct Sparkline: View {
    let points: [TrendPoint]
    let tint: Color

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(tint)
            }
            if let last = points.last {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Value", last.value)
                )
                .foregroundStyle(tint)
                .symbolSize(30)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

/// Seven narrow bars, one per day, in the track's orange, labelled with
/// the weekday's initial.
struct DailyDistanceBars: View {
    let days: [TrendPoint]

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Distance", day.value)
            )
            .foregroundStyle(BrandPalette.trackFill)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Metric cards") {
    let cal = Calendar.current
    let points = (0..<7).map { offset in
        TrendPoint(date: cal.date(byAdding: .day, value: offset - 6, to: Date())!,
                   value: [55, 58, 54, 61, 59, 63, 62][offset])
    }
    return ScrollView {
        VStack(spacing: 10) {
            MetricCard(title: "Readiness", systemImage: "checkmark.circle.fill", tint: .green,
                       detail: "7:10", value: "Ready",
                       note: "HRV and resting HR are both at your baseline.")
            HStack(spacing: 10) {
                MetricCard(title: "HRV", systemImage: "heart.fill", tint: .pink,
                           showsChevron: true, value: "62", unit: "ms", layout: .compact) {
                    Sparkline(points: points, tint: .pink).frame(height: 30)
                }
                MetricCard(title: "Resting", systemImage: "heart.fill", tint: .pink,
                           value: "51", unit: "bpm", layout: .compact) {
                    Sparkline(points: points.map { TrendPoint(date: $0.date, value: 120 - $0.value) }, tint: .pink)
                        .frame(height: 30)
                }
            }
            MetricCard(title: "Last 7 days", systemImage: "figure.run", tint: BrandPalette.track,
                       detail: "5-day streak", value: "32.0", unit: "km") {
                DailyDistanceBars(days: points).frame(width: 150, height: 64)
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
#endif
