// PaceOffWidget.swift
// Lock Screen widget — today's target distance + status dot.
// PRD §9.3.

import WidgetKit
import SwiftUI

struct PaceOffEntry: TimelineEntry {
    let date: Date
    /// What the app last cached, whichever day that was.
    let cache: WidgetCache

    /// The cache as of this entry's moment: empty once it's from an
    /// earlier day.
    var today: WidgetCache { cache.asOf(date) }
    var dot: WidgetCache.Dot { cache.dot(at: date) }
}

struct PaceOffProvider: TimelineProvider {

    func placeholder(in context: Context) -> PaceOffEntry {
        PaceOffEntry(date: Date(), cache: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (PaceOffEntry) -> Void) {
        completion(PaceOffEntry(date: Date(), cache: WidgetCache.load(from: AppGroup.sharedDefaults)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaceOffEntry>) -> Void) {
        // One entry now, one at noon for the red dot and one at midnight,
        // when the cached day goes stale. The app reloads the timeline
        // whenever it writes a new day.
        let cache = WidgetCache.load(from: AppGroup.sharedDefaults)
        let entries = WidgetCache.timelineDates(from: Date()).map { PaceOffEntry(date: $0, cache: cache) }
        completion(Timeline(entries: entries, policy: .atEnd))
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
                    // The plan line beats the voice line when a plan is
                    // active — it's the more actionable of the two.
                    Text(planLine ?? voiceLine)
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
                if let planLine {
                    HStack(spacing: 4) {
                        Image(systemName: dayDone
                              ? "checkmark.circle.fill"
                              : today.isStrengthOnlyDay ? "dumbbell.fill" : "calendar")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(dayDone ? Color.green : Color.secondary)
                        Text(planLine)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Text(voiceLine)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(planLine == nil ? 3 : 2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Everything the views read goes through here, so nothing cached on an
    /// earlier day reaches the screen.
    private var today: WidgetCache { entry.today }

    private var voiceLine: String {
        today.voiceLine ?? "Open Pace Off."
    }

    /// Today's plan line (`WidgetCache.planLine`). Nil when no plan is
    /// active.
    private var planLine: String? { today.planLine }

    /// The plan's day is done: its run, or a strength-only day's session.
    private var dayDone: Bool {
        today.isStrengthOnlyDay ? today.strengthCompletedToday : today.planCompletedToday
    }

    private var distanceShort: String {
        guard let t = today.target else { return "—" }
        return "\(t.displayedDistanceKm)"
    }

    private var inlineText: String {
        guard let t = today.target else { return "Open Pace Off" }
        return "Pace Off: \(t.displayedDistanceKm) km"
    }

    /// Green once today is done or on a planned rest day (never the
    /// after-noon nag on one), orange then red while today's run is still
    /// ahead, grey with no target for today.
    private var statusColor: Color {
        switch entry.dot {
        case .neutral: return Color.secondary
        case .green: return Color.green
        case .orange: return Color.orange
        case .red: return Color.red
        }
    }
}

#if DEBUG
private extension PaceOffEntry {
    static var sampleTarget: RunTarget {
        RunTarget(
            distanceMeters: 7_700,
            tone: .firm,
            daysSinceLastRun: 1,
            vo2MaxSlope: -0.05,
            baselineMeters: 7_200,
            ceilingClamped: false,
            fatigueGuardActive: false,
            computedAt: Date()
        )
    }

    static var samplePending: PaceOffEntry {
        PaceOffEntry(date: Date(), cache: WidgetCache(
            target: sampleTarget,
            voiceLine: "Easy 8K. Keep the pace conversational.",
            planSummary: "8.0 km · 5:25–5:45/km"
        ))
    }

    static var sampleDone: PaceOffEntry {
        PaceOffEntry(date: Date(), cache: WidgetCache(
            target: sampleTarget,
            voiceLine: "Done. Recovery walk later if you can.",
            runCompletedToday: true,
            planSummary: "8.0 km · 5:25–5:45/km",
            planCompletedToday: true
        ))
    }

    static var sampleRestDay: PaceOffEntry {
        PaceOffEntry(date: Date(), cache: WidgetCache(
            target: sampleTarget,
            voiceLine: "Recovery is training too.",
            planSummary: "Rest"
        ))
    }

    static var sampleStrengthDay: PaceOffEntry {
        PaceOffEntry(date: Date(), cache: WidgetCache(
            target: sampleTarget,
            voiceLine: "Recovery is training too.",
            planSummary: "Rest",
            strengthSummary: "Kettlebell · 35 min"
        ))
    }

    /// Yesterday's done day, drawn the next morning.
    static var sampleStale: PaceOffEntry {
        PaceOffEntry(
            date: Date().addingTimeInterval(86_400),
            cache: sampleDone.cache
        )
    }
}

#Preview("Widget — system small", as: .systemSmall) {
    PaceOffWidget()
} timeline: {
    PaceOffEntry.samplePending
    PaceOffEntry.sampleDone
    PaceOffEntry.sampleRestDay
    PaceOffEntry.sampleStrengthDay
    PaceOffEntry.sampleStale
}

#Preview("Widget — accessory rectangular", as: .accessoryRectangular) {
    PaceOffWidget()
} timeline: {
    PaceOffEntry.samplePending
}

#Preview("Widget — accessory circular", as: .accessoryCircular) {
    PaceOffWidget()
} timeline: {
    PaceOffEntry.samplePending
}

#Preview("Widget — accessory inline", as: .accessoryInline) {
    PaceOffWidget()
} timeline: {
    PaceOffEntry.samplePending
}
#endif
