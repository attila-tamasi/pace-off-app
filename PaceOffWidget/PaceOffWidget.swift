// PaceOffWidget.swift
// Lock Screen widget — today's target distance + status dot.
// PRD §9.3.

import WidgetKit
import SwiftUI

struct PaceOffEntry: TimelineEntry {
    let date: Date
    let target: RunTarget?
    let voiceLine: String
    let runCompletedToday: Bool
}

struct PaceOffProvider: TimelineProvider {

    func placeholder(in context: Context) -> PaceOffEntry {
        PaceOffEntry(date: Date(), target: nil, voiceLine: "Lace up.", runCompletedToday: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PaceOffEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaceOffEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh hourly so the status dot can flip from amber → red after 12:00
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> PaceOffEntry {
        let defaults = AppGroup.sharedDefaults
        var target: RunTarget?
        if let data = defaults?.data(forKey: AppGroup.Keys.lastTodayTarget) {
            target = try? JSONDecoder().decode(RunTarget.self, from: data)
        }
        let voice = defaults?.string(forKey: AppGroup.Keys.lastTodayVoiceLine) ?? "Open Pace Off."
        let done = defaults?.bool(forKey: AppGroup.Keys.runCompletedToday) ?? false
        return PaceOffEntry(date: Date(), target: target, voiceLine: voice, runCompletedToday: done)
    }
}

struct PaceOffWidget: Widget {
    let kind = "PaceOffWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaceOffProvider()) { entry in
            PaceOffWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Target")
        .description("Your push for today, on the Lock Screen.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
            .systemSmall,
        ])
    }
}

struct PaceOffWidgetView: View {
    let entry: PaceOffEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(distanceShort)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                    Text("km")
                        .font(.system(.caption2, design: .rounded))
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(distanceShort) km")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(entry.voiceLine)
                        .font(.system(.caption2, design: .rounded))
                        .lineLimit(2)
                }
                Spacer()
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(statusColor).frame(width: 10, height: 10)
                    Text("TODAY")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(.secondary)
                }
                Text("\(distanceShort) km")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(entry.voiceLine)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var distanceShort: String {
        guard let t = entry.target else { return "—" }
        return String(format: "%.1f", t.distanceKm)
    }

    private var inlineText: String {
        guard let t = entry.target else { return "Pace Off: open me" }
        return "Pace Off: \(String(format: "%.1f", t.distanceKm)) km"
    }

    private var statusColor: Color {
        if entry.runCompletedToday { return .green }
        let hour = Calendar.current.component(.hour, from: entry.date)
        if hour >= 12 { return .red }
        return .orange
    }
}
