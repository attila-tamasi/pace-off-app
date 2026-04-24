// TodayView.swift
// The single most important screen in the app.
// Hero target card, "what you did today" card (when applicable), supporting data grid.

import SwiftUI

struct TodayView: View {

    @EnvironmentObject private var todayVM: TodayViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Date header
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .padding(.horizontal, 4)

                // Hero target card
                heroCard

                // What you actually did today (only when there's a run)
                if let run = todayVM.todayRun {
                    todayRunCard(run)
                }

                // Below-the-fold supporting data
                supportingGrid
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pace Off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await todayVM.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(todayVM.isRefreshing)
            }
        }
        .refreshable { await todayVM.refresh() }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S TARGET")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(todayVM.target?.formattedDistance.replacingOccurrences(of: " km", with: "") ?? "—")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("km")
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(todayVM.voiceLine)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
        .overlay(alignment: .topTrailing) { toneBadge }
    }

    private var toneBadge: some View {
        Group {
            if let t = todayVM.target {
                Text(t.tone.displayName.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .kerning(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(toneColor(t.tone).opacity(0.15), in: Capsule())
                    .foregroundStyle(toneColor(t.tone))
                    .padding(20)
            }
        }
    }

    private func toneColor(_ tone: Tone) -> Color {
        switch tone {
        case .neutral, .firm: return .accentColor
        case .aggressive, .restart: return .red
        case .recovery: return .orange
        case .victory: return .green
        case .shortfall: return .yellow
        }
    }

    private var supportingGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(
                    label: "YESTERDAY",
                    value: todayVM.yesterday.map { String(format: "%.1f km", $0.distanceKm) } ?? "—",
                    icon: "calendar"
                )
                NavigationLink(value: TodayDestination.vo2Max) {
                    statCard(
                        label: "VO₂ MAX",
                        value: todayVM.currentVO2Max.map { String(format: "%.1f", $0) } ?? "—",
                        icon: "lungs.fill",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                statCard(
                    label: "STREAK",
                    value: todayVM.currentStreak == 0 ? "0" : "\(todayVM.currentStreak) day\(todayVM.currentStreak == 1 ? "" : "s")",
                    icon: "flame.fill"
                )
                statCard(
                    label: "DAYS SKIPPED",
                    value: todayVM.target.map { "\($0.daysSinceLastRun)" } ?? "—",
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }
        .navigationDestination(for: TodayDestination.self) { dest in
            switch dest {
            case .vo2Max: VO2MaxDetailView()
            }
        }
    }

    private func statCard(label: String, value: String, icon: String, showsChevron: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "You did this today" card. Shown only when `todayVM.todayRun != nil`.
    /// Compares actual distance to the asked-for target so the user can see
    /// at a glance whether they hit it, beat it, or fell short.
    private func todayRunCard(_ run: RunRecord) -> some View {
        let askedKm = (todayVM.target?.distanceMeters ?? 0) / 1000
        let actualKm = run.distanceKm
        let hit = askedKm > 0 && actualKm >= askedKm * 0.95
        let label: String
        let color: Color
        if hit {
            label = "TARGET HIT"; color = .green
        } else if askedKm == 0 {
            label = "LOGGED"; color = .accentColor
        } else {
            label = "SHORT BY \(String(format: "%.1f km", askedKm - actualKm))"
            color = .orange
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOU RAN TODAY")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .kerning(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", actualKm))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("km")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                runStat(label: "TIME", value: run.formattedDuration)
                runStat(label: "PACE", value: run.formattedPace)
                if let hr = run.averageHeartRate {
                    runStat(label: "AVG HR", value: "\(Int(hr.rounded())) bpm")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
        }
    }

    private func runStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
        }
    }
}

private enum TodayDestination: Hashable {
    case vo2Max
}
