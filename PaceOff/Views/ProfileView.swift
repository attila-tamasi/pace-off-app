// ProfileView.swift
// The Profile tab — read-only identity summary on top, plus all the
// configuration cards that used to live in the Settings tab.

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appleSignIn: AppleSignInService
    @EnvironmentObject private var health: HealthKitService
    @EnvironmentObject private var planStore: TrainingPlanStore

    @AppStorage(AppGroup.Keys.notificationMorningHour, store: AppGroup.sharedDefaults)
    private var morningHour: Int = 8
    @AppStorage(AppGroup.Keys.notificationAfternoonHour, store: AppGroup.sharedDefaults)
    private var afternoonHour: Int = 17
    @AppStorage(AppGroup.Keys.notificationEveningHour, store: AppGroup.sharedDefaults)
    private var eveningHour: Int = 21

    @State private var isEditing = false
    @State private var legalDocument: LegalDocument?
    @State private var confirmingSignOut = false
    @State private var prediction: GoalPrediction?
    @State private var planSettingsPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                goalCard
                personalBestCard
                if let prediction { predictionCard(prediction) }
                trainingPlanCard
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
        .task(id: profileStore.profile?.goal) { await refreshPrediction() }
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
        .sheet(isPresented: $planSettingsPresented) {
            TrainingPlanSettingsView()
                .environmentObject(planStore)
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

    // MARK: - Goal projection

    private func predictionCard(_ prediction: GoalPrediction) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                cardLabel("PROJECTED · \(prediction.goal.shortName)",
                          systemImage: "wand.and.stars")

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(prediction.formattedProjectedTime)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(prediction.formattedProjectedPace)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let gap = prediction.formattedGapToPersonalBest {
                    HStack(spacing: 6) {
                        Image(systemName: prediction.gapToPersonalBestSeconds ?? 0 < 0
                              ? "arrow.down.forward"
                              : "arrow.up.forward")
                            .font(.system(.caption, weight: .semibold))
                        Text(gap)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(prediction.gapToPersonalBestSeconds ?? 0 < 0 ? .green : .orange)
                }

                if let ageGraded = prediction.formattedAgeGradedEquivalent {
                    Text("Age-graded: \(ageGraded) (open equivalent)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(predictionBasisDescription(prediction.basis))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text("Conf: \(prediction.confidence.displayName)")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
        }
    }

    private func predictionBasisDescription(_ basis: GoalPrediction.Basis) -> String {
        switch basis {
        case .recentRun(let distance, _):
            let km = String(format: "%.1f", distance / 1000)
            return "Riegel from a recent \(km) km run."
        case .personalBestExtrapolation:
            return "Based on your personal best."
        }
    }

    private func refreshPrediction() async {
        guard let profile = profileStore.profile else {
            prediction = nil
            return
        }
        let snapshot = await HealthDataCache.shared.load()
        let runs = snapshot?.runs ?? []
        let age = profile.age() ?? snapshot?.userAge
        prediction = GoalPredictionService().predict(
            goal: profile.goal,
            runs: runs,
            age: age,
            personalBest: profile.personalBest
        )
    }

    // MARK: - Training plan

    @ViewBuilder
    private var trainingPlanCard: some View {
        if let plan = planStore.activePlan {
            activePlanCard(plan)
        } else {
            startPlanCard
        }
    }

    private func activePlanCard(_ plan: TrainingPlan) -> some View {
        let today = plan.todayWorkout()
        let weeksLeft = plan.weeksRemaining()
        return Button {
            planSettingsPresented = true
        } label: {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        cardLabel("TRAINING PLAN", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(plan.displayName)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    HStack(spacing: 14) {
                        miniStat("WEEKS LEFT", value: "\(weeksLeft)")
                        miniStat("RUNS/WK", value: "\(plan.tier.runsPerWeek)")
                        miniStat("LONG", value: plan.longRunDay.shortName)
                    }
                    if let workout = today, workout.kind != .rest {
                        Divider().padding(.vertical, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TODAY · \(workout.kind.displayName.uppercased())")
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .kerning(0.8)
                                .foregroundStyle(.secondary)
                            Text(workout.summary)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                        }
                    } else if today?.kind == .rest {
                        Divider().padding(.vertical, 2)
                        Text("TODAY · REST")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func miniStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
        }
    }

    private var startPlanCard: some View {
        NavigationLink {
            TrainingPlanPickerView()
                .environmentObject(profileStore)
                .environmentObject(health)
                .environmentObject(planStore)
        } label: {
            card {
                HStack(spacing: 14) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(.title2, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Build a training plan")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("Multi-week plan tailored to your goal and current fitness.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
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
        .environmentObject(TrainingPlanStore.shared)
}

#Preview("Profile (empty)") {
    NavigationStack { ProfileView() }
        .environmentObject(PreviewProfileStore.empty)
        .environmentObject(PreviewAppleSignInService.notSignedIn)
        .environmentObject(HealthKitService.shared)
        .environmentObject(TrainingPlanStore.shared)
}
#endif
