// OnboardingView.swift
// Four screens: welcome → profile setup → Health permission → Notification permission.

import SwiftUI
import PhotosUI
import AuthenticationServices

struct OnboardingView: View {

    let onComplete: () -> Void

    @EnvironmentObject private var health: HealthKitService
    @EnvironmentObject private var notifications: NotificationScheduler
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appleSignIn: AppleSignInService

    @State private var page = 0

    // Working profile, committed to the store when the user leaves the
    // profile step.
    @State private var draft = UserProfile()
    @State private var draftPhoto: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil

    var body: some View {
        TabView(selection: $page) {
            welcome.tag(0)
            profileSetup.tag(1)
            healthPermission.tag(2)
            notificationPermission.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 0 · Welcome

    private var welcome: some View {
        page(icon: "figure.run",
            title: "Pace Off pushes you to run.",
            subtitle: "Apple Health is the source of truth.",
            buttonLabel: "Continue",
            action: { withAnimation { page = 1 } }
        )
    }

    // MARK: - 1 · Profile setup

    private var profileSetup: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Set up your profile")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Stored only on your device. It tailors your training and tracks the goal you're chasing.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)

                // Continue with Apple — optional. Gives us the user's name and
                // a stable, app-scoped identifier; nothing is sent anywhere.
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { @MainActor in
                        guard appleSignIn.handleAuthorization(result),
                              let stored = profileStore.profile else { return }
                        // Pull the name / ID the store just captured into our draft.
                        if draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft.displayName = stored.displayName
                        }
                        draft.appleUserID = stored.appleUserID
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())

                Text("or set it up manually")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)

                ProfilePhotoPicker(image: draftPhoto, photoItem: $photoItem)

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("NAME")
                    TextField("Your name", text: $draft.displayName)
                        .textContentType(.name)
                        .padding(14)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("BIRTHDAY")
                    VStack(spacing: 0) {
                        BirthdayPicker(birthday: $draft.birthday)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("GOAL")
                    GoalGridPicker(selection: $draft.goal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("PERSONAL BEST (OPTIONAL)")
                    VStack(spacing: 4) {
                        PersonalBestEditor(goal: draft.goal, personalBest: $draft.personalBest)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    commitProfile()
                    withAnimation { page = 2 }
                } label: {
                    Text("Continue")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 4)
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        draftPhoto = image
    }

    private func commitProfile() {
        profileStore.setPhoto(draftPhoto)
        profileStore.save(draft)
    }

    // MARK: - 2 · Health permission

    private var healthPermission: some View {
        page(icon: "heart.text.square.fill",
            title: "Read your run data.",
            subtitle: "Pace Off pulls VO₂ max, runs, heart rate, HRV, and running dynamics from Apple Health. Nothing leaves your device.",
            buttonLabel: "Allow Health Access",
            action: {
                Task {
                    await health.requestAuthorization()
                    withAnimation { page = 3 }
                }
            }
        )
    }

    // MARK: - 3 · Notification permission

    private var notificationPermission: some View {
        page(icon: "bell.badge.fill",
            title: "This app works because it interrupts you.",
            subtitle: "Three pushes a day, max. Morning, afternoon, evening if you've skipped.",
            buttonLabel: "Allow Notifications",
            action: {
                Task {
                    await notifications.requestAuthorization()
                    onComplete()
                }
            }
        )
    }

    // MARK: - Shared simple page

    private func page(icon: String, title: String, subtitle: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }
}

#Preview("Onboarding") {
    OnboardingView(onComplete: {})
        .environmentObject(HealthKitService.shared)
        .environmentObject(NotificationScheduler.shared)
        .environmentObject(ProfileStore.shared)
        .environmentObject(AppleSignInService.shared)
}
