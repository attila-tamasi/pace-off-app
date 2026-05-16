// ProfileSetupSheetView.swift
// Profile creation step, extracted from the old OnboardingView page 2 and
// presented as a non-dismissable sheet after onboarding completes.
//
// Auth has already happened by the time we get here, so there's no
// "Continue with Apple" button on this screen — and no "set it up manually"
// fork. Reuses the editing controls defined in ProfileEditView.swift.

import SwiftUI
import PhotosUI

struct ProfileSetupSheetView: View {

    let onComplete: () -> Void

    @Environment(ProfileStore.self) private var profileStore

    @State private var draft: UserProfile
    @State private var draftPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem? = nil

    init(initialProfile: UserProfile?, initialPhoto: UIImage?, onComplete: @escaping () -> Void) {
        _draft = State(initialValue: initialProfile ?? UserProfile())
        _draftPhoto = State(initialValue: initialPhoto)
        self.onComplete = onComplete
    }

    var body: some View {
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
                .padding(.top, 32)

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
                    fieldLabel("RACE DAY (OPTIONAL)")
                    VStack(spacing: 0) {
                        GoalDatePicker(goalDate: $draft.goalDate)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                    }
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    commit()
                    onComplete()
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
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled()
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

    private func commit() {
        profileStore.setPhoto(draftPhoto)
        profileStore.save(draft)
    }
}

#Preview {
    ProfileSetupSheetView(
        initialProfile: nil,
        initialPhoto: nil,
        onComplete: {}
    )
    .environment(ProfileStore.shared)
}
