// ProfileView.swift
// The Profile tab — read-only identity summary on top, plus all the
// configuration cards that used to live in the Settings tab.

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appleSignIn: AppleSignInService
    @EnvironmentObject private var health: HealthKitService

    @AppStorage(AppGroup.Keys.notificationMorningHour, store: AppGroup.sharedDefaults)
    private var morningHour: Int = 8
    @AppStorage(AppGroup.Keys.notificationAfternoonHour, store: AppGroup.sharedDefaults)
    private var afternoonHour: Int = 17
    @AppStorage(AppGroup.Keys.notificationEveningHour, store: AppGroup.sharedDefaults)
    private var eveningHour: Int = 21

    @State private var isEditing = false
    @State private var legalDocument: LegalDocument?
    @State private var confirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                goalCard
                personalBestCard
                accountCard

                editProfileButton

                notificationsCard
                voiceCard
                healthCard
                legalCard
                aboutCard

                signOutButton
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditView(
                profile: profileStore.profile ?? UserProfile(),
                photo: profileStore.photo
            )
            .environmentObject(profileStore)
        }
        .sheet(item: $legalDocument) { doc in
            LegalView(document: doc)
        }
        .confirmationDialog("Sign out of Pace Off?",
                            isPresented: $confirmingSignOut,
                            titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                profileStore.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your on-device profile and returns you to the sign-in screen. Apple Health data is not touched.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Group {
                if let photo = profileStore.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color(.secondarySystemBackground))
                        Image(systemName: "person.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(.separator, lineWidth: 1))

            Text(displayName)
                .font(.system(.title2, design: .rounded, weight: .bold))

            if let ageLine {
                Text(ageLine)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var displayName: String {
        let name = profileStore.profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Runner" : name
    }

    private var ageLine: String? {
        guard let birthday = profileStore.profile?.birthday else { return nil }
        let formatted = birthday.formatted(.dateTime.month(.wide).day().year())
        if let age = profileStore.profile?.age() {
            return "\(age) · born \(formatted)"
        }
        return "Born \(formatted)"
    }

    // MARK: - Goal

    private var goalCard: some View {
        let goal = profileStore.profile?.goal ?? .tenK
        return card {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("GOAL", systemImage: "target")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goal.displayName)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(String(format: "%.1f km", goal.distanceKm))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Personal best

    private var personalBestCard: some View {
        let goal = profileStore.profile?.goal ?? .tenK
        let pb = profileStore.profile?.personalBest
        return card {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("PERSONAL BEST · \(goal.shortName)", systemImage: "trophy.fill")
                if let pb {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pb.formattedTime)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("· \(String(pb.year))")
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(pb.formattedPace(over: goal.distanceMeters))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No personal best logged yet.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Tap Edit to add the time and year you raced a \(goal.displayName).")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("ACCOUNT", systemImage: "applelogo")
                switch appleSignIn.state {
                case .signedIn:
                    Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.green)
                case .revoked:
                    Label("Apple sign-in was revoked", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.orange)
                case .notSignedIn, .unknown:
                    Text("This profile is stored only on your device.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var editProfileButton: some View {
        Button { isEditing = true } label: {
            HStack {
                Image(systemName: "pencil")
                Text("Edit Profile")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notifications card

    private var notificationsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardLabel("NOTIFICATIONS", systemImage: "bell.badge.fill")
                Stepper("Morning push: \(formatHour(morningHour))",
                        value: $morningHour, in: 5...11)
                Stepper("Afternoon reminder: \(formatHour(afternoonHour))",
                        value: $afternoonHour, in: 12...19)
                Stepper("Evening last call: \(formatHour(eveningHour))",
                        value: $eveningHour, in: 19...23)
                Text("The evening push only fires if you've already skipped at least one day this week.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Voice card

    private var voiceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("VOICE", systemImage: "waveform")
                HStack {
                    Text("Tone")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Text("Drill Sergeant")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("More voice options arrive in v1.1.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Health card

    private var healthCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                cardLabel("HEALTH", systemImage: "heart.text.square.fill")
                HStack {
                    Text("Age")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    if let age = health.userAge() {
                        Text("\(age)")
                            .font(.system(.body, design: .rounded, weight: .medium))
                    } else {
                        Text("Set in Health app")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await health.requestAuthorization() }
                } label: {
                    Label("Re-request Health permissions", systemImage: "arrow.clockwise")
                        .font(.system(.body, design: .rounded, weight: .medium))
                }
                Link(destination: URL(string: "x-apple-health://")!) {
                    Label("Manage in Settings", systemImage: "arrow.up.right.square")
                        .font(.system(.body, design: .rounded, weight: .medium))
                }
                Text("Age is read from your Apple Health profile. Open Health → tap your profile photo → Health Details to set or change your date of birth.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Legal card

    private var legalCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                cardLabel("LEGAL", systemImage: "doc.text")
                ForEach(LegalDocument.allCases) { doc in
                    Button {
                        legalDocument = doc
                    } label: {
                        HStack {
                            Text(doc.title)
                                .font(.system(.body, design: .rounded, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    if doc != LegalDocument.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - About card

    private var aboutCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel("ABOUT", systemImage: "info.circle")
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
                .font(.system(.body, design: .rounded))
                HStack {
                    Text("Build")
                    Spacer()
                    Text(buildNumber).foregroundStyle(.secondary)
                }
                .font(.system(.body, design: .rounded))
                Text("Pace Off does not collect any data. Everything stays in HealthKit and on your devices.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button(role: .destructive) {
            confirmingSignOut = true
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .controlSize(.large)
    }

    // MARK: - Card chrome

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
    }

    private func cardLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.secondary)
        }
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

#if DEBUG
#Preview("Profile (signed in)") {
    NavigationStack { ProfileView() }
        .environmentObject(PreviewProfileStore.populated)
        .environmentObject(PreviewAppleSignInService.signedIn)
        .environmentObject(HealthKitService.shared)
}

#Preview("Profile (empty)") {
    NavigationStack { ProfileView() }
        .environmentObject(PreviewProfileStore.empty)
        .environmentObject(PreviewAppleSignInService.notSignedIn)
        .environmentObject(HealthKitService.shared)
}
#endif
