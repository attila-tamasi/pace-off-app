// ProfileView.swift
// The Profile tab — a read-only summary of the runner's identity, goal, and
// personal best, with an Edit button that presents the ProfileEditView sheet.

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var appleSignIn: AppleSignInService

    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                goalCard
                personalBestCard
                accountCard
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
    }

    // MARK: - Header (photo + name + age)

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

    // MARK: - Account (Sign in with Apple status)

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
}
