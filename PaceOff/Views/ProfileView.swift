// ProfileView.swift
// The Profile tab — identity hero up top, goal & prediction in the middle,
// and a single Settings-app-style grouped list for everything else.

import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AppleSignInService.self) private var appleSignIn
    @Environment(HealthKitService.self) private var health

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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                identityHero
                goalAndPredictionCard
                preferencesList
                signOutButton.padding(.top, 4)
            }
            .padding(20)
        }
        .task(id: profileStore.profile?.goal) { await refreshPrediction() }
        .task(id: profileStore.profile?.goalDate) { await refreshPrediction() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isEditing = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditView(
                profile: profileStore.profile ?? UserProfile(),
                photo: profileStore.photo
            )
            .environment(profileStore)
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

    // MARK: - Identity hero

    private var identityHero: some View {
        VStack(spacing: 14) {
            avatar
            VStack(spacing: 2) {
                Text(displayName)
                    .font(.system(.title, design: .rounded, weight: .bold))
                if let subtitle = identitySubtitle {
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            statChipRow
            if case .signedIn = appleSignIn.state {
                signedInBadge
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.accentColor.opacity(0.12), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }

    private var avatar: some View {
        Group {
            if let photo = profileStore.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15))
                    Image(systemName: "person.fill")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: 116, height: 116)
        .clipShape(Circle())
        .overlay(Circle().stroke(.background, lineWidth: 3))
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    private var displayName: String {
        let name = profileStore.profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Runner" : name
    }

    private var identitySubtitle: String? {
        var parts: [String] = []
        if let age = profileStore.profile?.age() {
            parts.append("\(age) yrs")
        }
        if let goal = profileStore.profile?.goal {
            parts.append(goal.displayName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statChipRow: some View {
        HStack(spacing: 10) {
            statChip(label: "GOAL",
                     value: profileStore.profile?.goal.shortName ?? "—",
                     systemImage: "target")
            statChip(label: "PB",
                     value: profileStore.profile?.personalBest?.formattedTime ?? "—",
                     systemImage: "trophy.fill")
            if let countdown = goalCountdownChipText {
                statChip(label: "RACE DAY",
                         value: countdown,
                         systemImage: "flag.checkered")
            }
        }
    }

    private var goalCountdownChipText: String? {
        guard let goalDate = profileStore.profile?.goalDate, goalDate > Date() else { return nil }
        // Render in the same vocabulary GoalPrediction uses elsewhere.
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: Date(), to: goalDate).day ?? 0
        if days <= 0 { return nil }
        if days < 14 { return "\(days)d" }
        return "\(days / 7)w"
    }

    private func statChip(label: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(.caption2, weight: .semibold))
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .kerning(0.8)
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var signedInBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "applelogo")
                .font(.system(.caption, weight: .semibold))
            Text("Signed in with Apple")
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.systemBackground).opacity(0.7)))
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Goal + prediction

    private var goalAndPredictionCard: some View {
        let goal = profileStore.profile?.goal ?? .tenK
        let pb = profileStore.profile?.personalBest

        return card {
            VStack(alignment: .leading, spacing: 16) {

                // Header
                HStack {
                    cardLabel("GOAL", systemImage: "target")
                    Spacer()
                    if let countdown = prediction?.formattedCountdown() {
                        Text("RACE IN \(countdown.uppercased())")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .kerning(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(goal.displayName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(String(format: "%.1f km", goal.distanceKm))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Divider()

                // PB
                if let pb {
                    HStack(alignment: .firstTextBaseline) {
                        cardLabel("PB · \(goal.shortName)", systemImage: "trophy.fill")
                        Spacer()
                        Text("\(pb.formattedTime) · \(String(pb.year))")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        cardLabel("PB · \(goal.shortName)", systemImage: "trophy.fill")
                        Spacer()
                        Text("Not logged")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Projection
                if let prediction {
                    Divider()
                    predictionInline(prediction)
                }
            }
        }
    }

    @ViewBuilder
    private func predictionInline(_ p: GoalPrediction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                cardLabel("PROJECTED", systemImage: "wand.and.stars")
                Spacer()
                Text("Confidence: \(p.confidence.displayName)")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.formattedProjectedTime)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(p.formattedProjectedPace)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Annotations — only render the ones we actually have.
            VStack(alignment: .leading, spacing: 4) {
                if let gap = p.formattedGapToPersonalBest {
                    annotation(
                        text: gap,
                        systemImage: (p.gapToPersonalBestSeconds ?? 0) < 0
                            ? "arrow.down.right"
                            : "arrow.up.right",
                        color: (p.gapToPersonalBestSeconds ?? 0) < 0 ? .green : .orange
                    )
                }
                if let vo2 = p.formattedVO2Adjustment {
                    annotation(text: vo2, systemImage: "waveform.path.ecg", color: .orange)
                }
                if let training = p.formattedTrainingImprovement {
                    annotation(text: training, systemImage: "figure.run", color: .green)
                }
                if let ageGraded = p.formattedAgeGradedEquivalent {
                    annotation(text: "Age-graded equivalent \(ageGraded)",
                               systemImage: "person.text.rectangle",
                               color: .secondary)
                }
            }

            Text(predictionBasisDescription(p.basis))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private func annotation(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(.caption, weight: .semibold))
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .medium))
        }
        .foregroundStyle(color)
    }

    private func predictionBasisDescription(_ basis: GoalPrediction.Basis) -> String {
        switch basis {
        case .recentRun(let distance, _):
            let km = String(format: "%.1f", distance / 1000)
            return "Projected from your recent \(km) km run."
        case .agedPersonalBest(let years):
            if years == 0 {
                return "Anchored on this year's PB."
            } else if years == 1 {
                return "From a 1-year-old PB (light age decay applied)."
            } else {
                return "From a \(years)-year-old PB (decayed for age)."
            }
        }
    }

    private func refreshPrediction() async {
        guard let profile = profileStore.profile else {
            prediction = nil
            return
        }
        let snapshot = await HealthDataCache.shared.load()
        let runs = snapshot?.runs ?? []
        let vo2 = snapshot?.vo2Max ?? []
        let age = profile.age() ?? snapshot?.userAge
        prediction = GoalPredictionService().predict(
            goal: profile.goal,
            runs: runs,
            age: age,
            personalBest: profile.personalBest,
            vo2MaxHistory: vo2,
            goalDate: profile.goalDate
        )
    }

    // MARK: - Preferences (collapsed Settings)

    private var preferencesList: some View {
        VStack(spacing: 0) {
            preferenceSectionHeader("PREFERENCES")
            VStack(spacing: 0) {
                notificationRow
                divider
                voiceRow
                divider
                healthRow
                divider
                ForEach(LegalDocument.allCases) { doc in
                    legalRow(doc)
                    if doc != LegalDocument.allCases.last { divider }
                }
                divider
                aboutRow
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }

    private func preferenceSectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private var divider: some View {
        Divider().padding(.leading, 56)
    }

    private var notificationRow: some View {
        DisclosureGroup {
            VStack(spacing: 10) {
                Stepper("Morning push: \(formatHour(morningHour))",
                        value: $morningHour, in: 5...11)
                Stepper("Afternoon: \(formatHour(afternoonHour))",
                        value: $afternoonHour, in: 12...19)
                Stepper("Evening last call: \(formatHour(eveningHour))",
                        value: $eveningHour, in: 19...23)
                Text("Evening only fires if you've skipped at least one day this week.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
        } label: {
            preferenceLabel(icon: "bell.badge.fill",
                            color: .red,
                            title: "Notifications",
                            value: "Daily pushes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var voiceRow: some View {
        preferenceRow(icon: "waveform",
                      color: .purple,
                      title: "Voice",
                      value: "Drill Sergeant")
    }

    private var healthRow: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await health.requestAuthorization() }
                } label: {
                    Label("Re-request Health permissions", systemImage: "arrow.clockwise")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Link(destination: URL(string: "x-apple-health://")!) {
                    Label("Manage in the Health app", systemImage: "arrow.up.right.square")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)

                Text("Age is read from Apple Health. Open Health → tap your profile → Health Details to set or change your date of birth.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            preferenceLabel(icon: "heart.text.square.fill",
                            color: .pink,
                            title: "Health",
                            value: health.userAge().map { "Age \($0)" } ?? "Set in Health")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func legalRow(_ doc: LegalDocument) -> some View {
        Button { legalDocument = doc } label: {
            preferenceLabel(icon: "doc.text",
                            color: .gray,
                            title: doc.title,
                            value: nil,
                            showsChevron: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var aboutRow: some View {
        preferenceRow(icon: "info.circle",
                      color: .blue,
                      title: "About",
                      value: "v\(appVersion) (\(buildNumber))")
    }

    /// A static (non-tappable) row — same chrome as DisclosureGroup labels.
    private func preferenceRow(icon: String, color: Color, title: String, value: String?) -> some View {
        preferenceLabel(icon: icon, color: color, title: title, value: value)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    /// The shared visual treatment for every settings row — icon tile + title + trailing value.
    private func preferenceLabel(icon: String, color: Color, title: String,
                                 value: String?, showsChevron: Bool = false) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 30, height: 30)

            Text(title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
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

    // MARK: - Helpers

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
        .environment(PreviewProfileStore.populated)
        .environment(PreviewAppleSignInService.signedIn)
        .environment(HealthKitService.shared)
}

#Preview("Profile (empty)") {
    NavigationStack { ProfileView() }
        .environment(PreviewProfileStore.empty)
        .environment(PreviewAppleSignInService.notSignedIn)
        .environment(HealthKitService.shared)
}
#endif
