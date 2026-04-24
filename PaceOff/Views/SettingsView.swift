// SettingsView.swift
// Notification times, voice tone (locked in MVP), Health permissions, About.

import SwiftUI

struct SettingsView: View {

    @AppStorage(AppGroup.Keys.notificationMorningHour, store: AppGroup.sharedDefaults)
    private var morningHour: Int = 8
    @AppStorage(AppGroup.Keys.notificationAfternoonHour, store: AppGroup.sharedDefaults)
    private var afternoonHour: Int = 17
    @AppStorage(AppGroup.Keys.notificationEveningHour, store: AppGroup.sharedDefaults)
    private var eveningHour: Int = 21

    var body: some View {
        Form {
            Section("Voice") {
                HStack {
                    Text("Tone")
                    Spacer()
                    Text("Drill Sergeant").foregroundStyle(.secondary)
                }
                Text("More voice options arrive in v1.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Stepper("Morning push: \(formatHour(morningHour))", value: $morningHour, in: 5...11)
                Stepper("Afternoon reminder: \(formatHour(afternoonHour))", value: $afternoonHour, in: 12...19)
                Stepper("Evening last call: \(formatHour(eveningHour))", value: $eveningHour, in: 19...23)
                Text("The evening push only fires if you've already skipped at least one day this week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Health") {
                LabeledContent("Age") {
                    if let age = HealthKitService.shared.userAge() {
                        Text("\(age)")
                    } else {
                        Text("Set in Health app").foregroundStyle(.secondary)
                    }
                }
                Button("Re-request Health permissions") {
                    Task { await HealthKitService.shared.requestAuthorization() }
                }
                Link("Manage in Settings", destination: URL(string: "x-apple-health://")!)
                Text("Age is read from your Apple Health profile. Open Health → tap your profile photo → Health Details to set or change your date of birth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                Text("Pace Off does not collect any data. Everything stays in HealthKit and on your devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func formatHour(_ h: Int) -> String {
        var components = DateComponents(); components.hour = h; components.minute = 0
        return Calendar.current.date(from: components)?.formatted(.dateTime.hour().minute()) ?? "\(h):00"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
