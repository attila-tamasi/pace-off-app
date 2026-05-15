// ProfileEditView.swift
// The profile editor — a Form-based sheet presented from the Profile tab.
// Also defines the reusable editing controls (photo picker, goal grid,
// personal-best editor) that the onboarding flow embeds directly.

import SwiftUI
import PhotosUI

// MARK: - Edit sheet

struct ProfileEditView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    // Working copy — committed to the store only on "Save".
    @State private var draft: UserProfile
    @State private var draftPhoto: UIImage?
    @State private var photoItem: PhotosPickerItem? = nil

    init(profile: UserProfile, photo: UIImage?) {
        _draft = State(initialValue: profile)
        _draftPhoto = State(initialValue: photo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfilePhotoPicker(image: draftPhoto, photoItem: $photoItem)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Your name", text: $draft.displayName)
                        .textContentType(.name)
                }

                Section("Birthday") {
                    BirthdayPicker(birthday: $draft.birthday)
                }

                Section("Goal") {
                    GoalGridPicker(selection: $draft.goal)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section("Personal Best") {
                    PersonalBestEditor(goal: draft.goal, personalBest: $draft.personalBest)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                        dismiss()
                    }
                    .disabled(draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task { await loadPhoto(newItem) }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        draftPhoto = image
    }

    private func commit() {
        // Photo first, so the store's `hasPhoto` flag is correct when we save.
        profileStore.setPhoto(draftPhoto)
        profileStore.save(draft)
    }
}

// MARK: - Reusable controls

/// Circular profile photo with a PhotosPicker overlay. Shows a placeholder
/// glyph when no photo is set.
struct ProfilePhotoPicker: View {
    let image: UIImage?
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(Color(.secondarySystemBackground))
                            Image(systemName: "person.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay(Circle().stroke(.separator, lineWidth: 1))

                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.accentColor, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
    }
}

/// Birthday entry — a toggle for "set" plus a graphical date picker so users
/// who'd rather not share a birthday can leave it blank.
struct BirthdayPicker: View {
    @Binding var birthday: Date?

    @State private var isSet: Bool
    @State private var date: Date

    init(birthday: Binding<Date?>) {
        _birthday = birthday
        _isSet = State(initialValue: birthday.wrappedValue != nil)
        _date = State(initialValue: birthday.wrappedValue ?? Self.defaultDate)
    }

    private static var defaultDate: Date {
        Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    }

    var body: some View {
        Toggle("Add my birthday", isOn: $isSet)
            .onChange(of: isSet) { _, on in
                birthday = on ? date : nil
            }
        if isSet {
            DatePicker(
                "Birthday",
                selection: $date,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .onChange(of: date) { _, newDate in
                birthday = newDate
            }
        }
    }
}

/// Two-by-two grid of the four standard race-distance goals.
struct GoalGridPicker: View {
    @Binding var selection: RunningGoal

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(RunningGoal.allCases) { goal in
                let isSelected = goal == selection
                Button {
                    selection = goal
                } label: {
                    VStack(spacing: 4) {
                        Text(goal.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(String(format: "%.1f km", goal.distanceKm))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Personal-best editor: a toggle for "have you run this distance?", and when
/// on, H:MM:SS wheels plus the year it was achieved.
struct PersonalBestEditor: View {
    let goal: RunningGoal
    @Binding var personalBest: PersonalBest?

    @State private var hasPB: Bool
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var year: Int

    private static let currentYear = Calendar.current.component(.year, from: Date())
    private var yearRange: [Int] { Array((Self.currentYear - 40)...Self.currentYear).reversed() }

    init(goal: RunningGoal, personalBest: Binding<PersonalBest?>) {
        self.goal = goal
        _personalBest = personalBest
        let pb = personalBest.wrappedValue
        _hasPB = State(initialValue: pb != nil)
        let total = Int(pb?.durationSeconds ?? 0)
        _hours = State(initialValue: total / 3600)
        _minutes = State(initialValue: (total % 3600) / 60)
        _seconds = State(initialValue: total % 60)
        _year = State(initialValue: pb?.year ?? Self.currentYear)
    }

    var body: some View {
        Toggle("I've raced a \(goal.displayName)", isOn: $hasPB)
            .onChange(of: hasPB) { _, on in
                syncBinding(enabled: on)
            }

        if hasPB {
            HStack(spacing: 0) {
                wheel(value: $hours, range: 0...9, label: "hr")
                colon
                wheel(value: $minutes, range: 0...59, label: "min")
                colon
                wheel(value: $seconds, range: 0...59, label: "sec")
            }
            .frame(maxWidth: .infinity)

            Picker("Year", selection: $year) {
                ForEach(yearRange, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .onChange(of: year) { _, _ in syncBinding(enabled: true) }
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 18)
    }

    private func wheel(value: Binding<Int>, range: ClosedRange<Int>, label: String) -> some View {
        VStack(spacing: 2) {
            Picker(label, selection: value) {
                ForEach(Array(range), id: \.self) { n in
                    Text(String(format: "%02d", n)).tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 64, height: 100)
            .clipped()
            .onChange(of: value.wrappedValue) { _, _ in syncBinding(enabled: true) }
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func syncBinding(enabled: Bool) {
        guard enabled else {
            personalBest = nil
            return
        }
        let total = Double(hours * 3600 + minutes * 60 + seconds)
        personalBest = PersonalBest(durationSeconds: total, year: year)
    }
}

#if DEBUG
#Preview("Edit Profile sheet") {
    ProfileEditView(profile: .sample, photo: nil)
        .environmentObject(PreviewProfileStore.populated)
}

#Preview("Photo picker — empty / set") {
    VStack(spacing: 32) {
        ProfilePhotoPicker(image: nil, photoItem: .constant(nil))
        ProfilePhotoPicker(
            image: UIImage(systemName: "person.crop.circle.fill"),
            photoItem: .constant(nil)
        )
    }
    .padding()
}

#Preview("Birthday picker") {
    StatefulPreviewWrapper(Date?.none) { binding in
        Form { BirthdayPicker(birthday: binding) }
    }
}

#Preview("Goal grid") {
    StatefulPreviewWrapper(RunningGoal.tenK) { binding in
        Form {
            GoalGridPicker(selection: binding)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }
}

#Preview("Personal best editor") {
    StatefulPreviewWrapper(PersonalBest?.some(PersonalBest(durationSeconds: 5_482, year: 2024))) { binding in
        Form {
            PersonalBestEditor(goal: .halfMarathon, personalBest: binding)
        }
    }
}

/// Drives `@State`-flavoured bindings for previews that need mutable input.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
#endif
