// RunDetailView.swift
// Full breakdown of a single run including running dynamics.

import SwiftUI

struct RunDetailView: View {
    let run: RunRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricsGrid
                if hasDynamics { dynamicsSection }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(run.startDate.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(run.startDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f km", run.distanceKm))
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text("\(run.formattedPace) · \(run.formattedDuration)")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("HEART RATE", value: run.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—", icon: "heart.fill")
            metric("ENERGY", value: run.activeEnergyKcal.map { "\(Int($0)) kcal" } ?? "—", icon: "flame.fill")
        }
    }

    private var hasDynamics: Bool {
        run.averagePowerWatts != nil
            || run.averageStrideLengthMeters != nil
            || run.averageVerticalOscillationCm != nil
            || run.averageGroundContactMs != nil
            || run.averageCadenceSpm != nil
    }

    private var dynamicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RUNNING DYNAMICS")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let p = run.averagePowerWatts {
                    metric("POWER", value: "\(Int(p)) W", icon: "bolt.fill")
                }
                if let s = run.averageStrideLengthMeters {
                    metric("STRIDE", value: String(format: "%.2f m", s), icon: "ruler")
                }
                if let v = run.averageVerticalOscillationCm {
                    metric("VERTICAL OSC.", value: String(format: "%.1f cm", v), icon: "arrow.up.and.down")
                }
                if let g = run.averageGroundContactMs {
                    metric("GROUND CONTACT", value: "\(Int(g)) ms", icon: "shoe")
                }
                if let c = run.averageCadenceSpm {
                    metric("CADENCE", value: "\(Int(c)) spm", icon: "metronome")
                }
            }
        }
    }

    private func metric(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
