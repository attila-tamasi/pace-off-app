// OnboardingFlow.swift
// Post-auth onboarding — a nine-step guided setup that lands the user on
// the Today tab with a fully populated profile and the two OS permission
// prompts already answered. Replaces the old three-page TabView
// OnboardingView + non-dismissable ProfileSetupSheetView pair; those had
// no shared visual language and forced the user through two disconnected
// flows for what feels like one job.
//
// Design vocabulary matches the Profile tab (the user's stated favourite):
// system-grouped background, rounded typography, accent gradient hero,
// glass CTAs, cards with 22–24pt corner radius and subtle shadows.
//
// The flow owns a draft `UserProfile` that mutates step by step and gets
// committed to `ProfileStore` on the final "Done" step. Optional steps
// (birthday, race day, PB) render a "Skip for now" secondary action.

import SwiftUI
import PhotosUI

// MARK: - Steps

/// The nine steps, in order. `rawValue` doubles as the ordering index.
public enum OnboardingStep: Int, CaseIterable {
    case welcome, name, birthday, goal, raceDay, personalBest, health, notifications, done

    /// 0..1 — how far through we are. Welcome shows nearly-empty progress
    /// (0.05 rather than 0) so the bar isn't invisible on the first screen.
    var progress: Double {
        Double(rawValue) / Double(OnboardingStep.done.rawValue)
    }

    var canGoBack: Bool { self != .welcome && self != .done }
}

// MARK: - Flow root

struct OnboardingFlow: View {

    /// Called when the user finishes the "Done" step. The app shell then
    /// flips `onboardingComplete = true` and routes to the main tabs.
    let onComplete: () -> Void

    @Environment(ProfileStore.self) private var profileStore
    @Environment(HealthKitService.self) private var health
    @Environment(NotificationScheduler.self) private var notifications

    @State private var step: OnboardingStep = .welcome
    @State private var draft: UserProfile = .init()
    @State private var draftPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var isRequestingPermission = false

    var body: some View {
        ZStack {
            currentStep
                .id(step) // fresh view identity per step → clean transitions
                .transition(stepTransition)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .onAppear(perform: hydrateFromProfile)
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
    }

    /// Slide + fade based on direction — forward slides in from the right,
    /// back from the left. `stepTransition` reads the current step and
    /// picks a direction; SwiftUI applies the reverse for the outgoing view.
    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Step router

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .welcome:      WelcomeStep(onNext: advance)
        case .name:         NameStep(draft: $draft, draftPhoto: $draftPhoto, photoItem: $photoItem,
                                     onNext: advance, onBack: back)
        case .birthday:     BirthdayStep(draft: $draft, onNext: advance, onBack: back, onSkip: skip)
        case .goal:         GoalStep(draft: $draft, onNext: advance, onBack: back)
        case .raceDay:      RaceDayStep(draft: $draft, onNext: advance, onBack: back, onSkip: skip)
        case .personalBest: PersonalBestStep(draft: $draft, onNext: advance, onBack: back, onSkip: skip)
        case .health:       HealthPermissionStep(
                                isRequesting: $isRequestingPermission,
                                onAllow: { await requestHealth(); advance() },
                                onBack: back
                            )
        case .notifications: NotificationsStep(
                                isRequesting: $isRequestingPermission,
                                onAllow: { await requestNotifications(); advance() },
                                onBack: back
                            )
        case .done:         DoneStep(name: draft.displayName,
                                     goal: draft.goal,
                                     goalDate: draft.goalDate,
                                     onFinish: finish)
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func back() {
        guard step.canGoBack, let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// "Skip for now" — clears the optional field this step edits, then
    /// advances. Guarantees skipped steps never carry a stale draft value.
    private func skip() {
        switch step {
        case .birthday:     draft.birthday = nil
        case .raceDay:      draft.goalDate = nil
        case .personalBest: draft.personalBest = nil
        default: break
        }
        advance()
    }

    private func finish() {
        // Commit photo first so `hasPhoto` is truthful when `save` writes.
        profileStore.setPhoto(draftPhoto)
        profileStore.save(draft)
        onComplete()
    }

    // MARK: - Permission requests

    private func requestHealth() async {
        isRequestingPermission = true
        await health.requestAuthorization()
        isRequestingPermission = false
    }

    private func requestNotifications() async {
        isRequestingPermission = true
        await notifications.requestAuthorization()
        isRequestingPermission = false
    }

    // MARK: - Hydrate from Sign in with Apple

    /// Sign in with Apple only surfaces the display name on the very first
    /// grant, so if the ProfileStore already has one, use it as the draft's
    /// starting name. Same for the Apple user ID and any pre-existing goal.
    private func hydrateFromProfile() {
        if let existing = profileStore.profile {
            draft = existing
        }
        draftPhoto = profileStore.photo
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        draftPhoto = image
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    let onNext: () -> Void

    @State private var pulse = false

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.welcome.progress,
            title: "Welcome to Pace Off.",
            subtitle: "A running coach that knows when to push you and when you need rest. Setup takes about 60 seconds.",
            primaryTitle: "Get started",
            onPrimary: onNext,
            onBack: nil
        ) {
            VStack(spacing: 24) {
                Image(systemName: "figure.run")
                    .font(.system(size: 96, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, options: .repeating)
                    .brandSoftGlow(color: .accentColor, radius: 20)
                    .padding(.top, 8)
                highlightsCard
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            highlightRow(icon: "target",
                         title: "Personalised training",
                         detail: "Pick your race distance — plans are built around your VO₂ max and PB.")
            Divider().padding(.leading, 44)
            highlightRow(icon: "moon.zzz.fill",
                         title: "Green / Yellow / Red readiness",
                         detail: "HRV and resting HR tell you when to hold back.")
            Divider().padding(.leading, 44)
            highlightRow(icon: "lock.shield.fill",
                         title: "Stays on your device",
                         detail: "No accounts, no analytics, no cloud. Data never leaves your phone.")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
    }

    private func highlightRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 1: Name (+ optional photo)

private struct NameStep: View {
    @Binding var draft: UserProfile
    @Binding var draftPhoto: UIImage?
    @Binding var photoItem: PhotosPickerItem?
    let onNext: () -> Void
    let onBack: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.name.progress,
            title: "What should we call you?",
            subtitle: "You'll see this on your profile and in daily nudges.",
            primaryTitle: "Continue",
            primaryEnabled: !draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty,
            onPrimary: onNext,
            onBack: onBack
        ) {
            VStack(spacing: 24) {
                ProfilePhotoPicker(image: draftPhoto, photoItem: $photoItem)

                TextField("Your name", text: $draft.displayName)
                    .textContentType(.name)
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    )
                    .focused($nameFocused)
                    .submitLabel(.next)
                    .onSubmit(onNext)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // Auto-focus the name field. Small delay lets the transition
            // finish so the keyboard doesn't scoop up the animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { nameFocused = true }
        }
    }
}

// MARK: - Step 2: Birthday (optional)

private struct BirthdayStep: View {
    @Binding var draft: UserProfile
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.birthday.progress,
            title: "When were you born?",
            subtitle: "Age lets us age-grade your race projections. We only use it locally.",
            primaryTitle: "Continue",
            primaryEnabled: draft.birthday != nil,
            onPrimary: onNext,
            secondaryTitle: "Skip for now",
            onSecondary: onSkip,
            onBack: onBack
        ) {
            VStack(spacing: 16) {
                BirthdayPicker(birthday: $draft.birthday)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    )
            }
        }
    }
}

// MARK: - Step 3: Goal

private struct GoalStep: View {
    @Binding var draft: UserProfile
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.goal.progress,
            title: "What are you training for?",
            subtitle: "Your plan and pace targets are built around this. Change it anytime.",
            primaryTitle: "Continue",
            primaryEnabled: true,
            onPrimary: onNext,
            onBack: onBack
        ) {
            GoalGridPicker(selection: $draft.goal)
        }
    }
}

// MARK: - Step 4: Race day (optional)

private struct RaceDayStep: View {
    @Binding var draft: UserProfile
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.raceDay.progress,
            title: "Do you have a race date?",
            subtitle: "If yes, we shorten the plan to fit and taper into it. Skip if you're training open-ended.",
            primaryTitle: draft.goalDate == nil ? "Not yet" : "Continue",
            onPrimary: onNext,
            secondaryTitle: draft.goalDate == nil ? nil : "Skip for now",
            onSecondary: draft.goalDate == nil ? nil : onSkip,
            onBack: onBack
        ) {
            VStack(spacing: 16) {
                GoalDatePicker(goalDate: $draft.goalDate)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    )
            }
        }
    }
}

// MARK: - Step 5: Personal Best (optional)

private struct PersonalBestStep: View {
    @Binding var draft: UserProfile
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.personalBest.progress,
            title: "What's your \(draft.goal.displayName) PB?",
            subtitle: "We use it to anchor your pace zones. If you've never raced this distance, skip and we'll estimate from HealthKit.",
            primaryTitle: "Continue",
            onPrimary: onNext,
            secondaryTitle: "Skip for now",
            onSecondary: onSkip,
            onBack: onBack
        ) {
            VStack(spacing: 16) {
                PersonalBestEditor(goal: draft.goal, personalBest: $draft.personalBest)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    )
            }
        }
    }
}

// MARK: - Step 6: Health permission

private struct HealthPermissionStep: View {
    @Binding var isRequesting: Bool
    let onAllow: () async -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.health.progress,
            title: "Read your run data.",
            subtitle: "Pace Off computes everything on-device from your Apple Health data. Nothing is uploaded anywhere.",
            primaryTitle: isRequesting ? "Requesting…" : "Allow Health Access",
            primaryEnabled: !isRequesting,
            onPrimary: { Task { await onAllow() } },
            onBack: onBack
        ) {
            VStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.pink)
                    .brandSoftGlow(color: .pink, radius: 16)
                    .padding(.vertical, 8)

                readList
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var readList: some View {
        VStack(alignment: .leading, spacing: 12) {
            readRow(icon: "figure.run", label: "Running workouts", detail: "Distance, pace, HR, running dynamics")
            readRow(icon: "lungs.fill", label: "VO₂ max", detail: "Anchors your paces + race projection")
            readRow(icon: "waveform.path.ecg", label: "Resting HR + HRV", detail: "Powers the daily readiness signal")
            readRow(icon: "gift.fill", label: "Date of birth", detail: "For age-graded race projections")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func readRow(icon: String, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Step 7: Notifications

private struct NotificationsStep: View {
    @Binding var isRequesting: Bool
    let onAllow: () async -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.notifications.progress,
            title: "Let us nudge you.",
            subtitle: "Three pushes a day, tops. Morning push, afternoon check-in, evening last-call if you've skipped.",
            primaryTitle: isRequesting ? "Requesting…" : "Allow Notifications",
            primaryEnabled: !isRequesting,
            onPrimary: { Task { await onAllow() } },
            secondaryTitle: "Not now",
            onSecondary: { Task { await onAllow() } },
            onBack: onBack
        ) {
            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.red)
                    .brandSoftGlow(color: .red, radius: 16)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(2, delay: 3)))
                    .padding(.vertical, 8)

                Text("You can change timing or turn any of them off later in Profile → Notifications.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Step 8: Done

private struct DoneStep: View {
    let name: String
    let goal: RunningGoal
    let goalDate: Date?
    let onFinish: () -> Void

    @State private var celebrate = false

    var body: some View {
        OnboardingStepScaffold(
            progress: OnboardingStep.done.progress,
            title: firstName.isEmpty ? "You're set." : "You're set, \(firstName).",
            subtitle: "Your Today screen is ready. Your first target lands in a moment.",
            primaryTitle: "Open Pace Off",
            onPrimary: onFinish,
            onBack: nil
        ) {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: 140, height: 140)
                    Image(systemName: "checkmark")
                        .font(.system(size: 68, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(celebrate ? 1 : 0.4)
                        .opacity(celebrate ? 1 : 0)
                }
                .brandSoftGlow(color: .accentColor, radius: 24)

                summaryCard
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.1)) {
                    celebrate = true
                }
            }
        }
    }

    private var firstName: String {
        name.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryRow(icon: "target", label: "GOAL", value: goal.displayName)
            if let goalDate {
                Divider().padding(.leading, 34)
                summaryRow(
                    icon: "flag.checkered",
                    label: "RACE DAY",
                    value: goalDate.formatted(.dateTime.month().day().year())
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Onboarding — start") {
    OnboardingFlow(onComplete: {})
        .environment(ProfileStore.shared)
        .environment(HealthKitService.shared)
        .environment(NotificationScheduler.shared)
}
#endif
