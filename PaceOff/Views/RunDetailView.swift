// RunDetailView.swift
// Full breakdown of a single run including the GPS route map and running dynamics.

import SwiftUI
import MapKit
import CoreLocation

struct RunDetailView: View {
    let run: RunRecord

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var isLoadingRoute: Bool = true
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Map height as a fraction of the available screen height. Matches the
    /// proportion used on the Today screen so the experience feels consistent.
    private let mapHeightFraction: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    mapSection
                        .frame(height: geo.size.height * mapHeightFraction)
                        .clipped()

                    VStack(alignment: .leading, spacing: 24) {
                        header
                        metricsGrid
                        if hasDynamics { dynamicsSection }
                    }
                    .padding(20)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(run.startDate.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: run.id) { await loadRoute() }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if !routeCoordinates.isEmpty {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(
                        .blue.gradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                if let start = routeCoordinates.first {
                    Annotation("Start", coordinate: start) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let end = routeCoordinates.last, routeCoordinates.count > 1 {
                    Annotation("Finish", coordinate: end) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        } else {
            ZStack {
                Color(.systemGray6)
                VStack(spacing: 10) {
                    if isLoadingRoute {
                        ProgressView()
                        Text("Loading route…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No route recorded")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("This run was indoors, on a treadmill,\nor location wasn't shared.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func loadRoute() async {
        isLoadingRoute = true
        let coords = await HealthKitService.shared.fetchRunRoute(for: run)
        routeCoordinates = coords
        isLoadingRoute = false
        updateCamera(for: coords)
    }

    private func updateCamera(for coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLng = coords[0].longitude, maxLng = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.005),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.005)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Header & metrics

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
