// ProfileStore.swift
// Owns the user's locally-stored profile. The UserProfile struct is persisted
// as JSON in App Group UserDefaults; the profile photo is written as a JPEG
// into the App Group container directory (binary blobs don't belong in
// UserDefaults). Everything stays on-device.

import Foundation
import SwiftUI
import UIKit
import Observation

@MainActor
@Observable
public final class ProfileStore {

    public static let shared = ProfileStore()

    /// The current profile. `nil` until the user completes onboarding.
    public private(set) var profile: UserProfile?

    /// Decoded profile photo, loaded lazily from the App Group container.
    public private(set) var photo: UIImage?

    private var defaults: UserDefaults? { AppGroup.sharedDefaults }

    public init() {
        load()
    }

    /// True once a profile exists and has at least a name.
    public var isSetUp: Bool { profile?.isComplete == true }

    // MARK: - Load / Save

    private func load() {
        if let data = defaults?.data(forKey: AppGroup.Keys.userProfile),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.profile = decoded
            if decoded.hasPhoto {
                self.photo = Self.loadPhotoFromDisk()
            }
        }
    }

    /// Persist the whole profile. Used by both onboarding and the Profile tab.
    public func save(_ newProfile: UserProfile) {
        var toStore = newProfile
        // Keep the `hasPhoto` flag honest with what's actually on disk.
        toStore.hasPhoto = (photo != nil)
        self.profile = toStore
        if let data = try? JSONEncoder().encode(toStore) {
            defaults?.set(data, forKey: AppGroup.Keys.userProfile)
        }
    }

    /// Convenience for partial edits from the UI — mutate a copy and save.
    public func update(_ mutate: (inout UserProfile) -> Void) {
        var working = profile ?? UserProfile()
        mutate(&working)
        save(working)
    }

    // MARK: - Photo

    /// Store a new profile photo. Downscales to a sensible max dimension and
    /// writes JPEG into the App Group container. Pass `nil` to remove it.
    public func setPhoto(_ image: UIImage?) {
        guard let image else {
            photo = nil
            Self.deletePhotoFromDisk()
            update { $0.hasPhoto = false }
            return
        }
        let scaled = Self.downscale(image, maxDimension: 512)
        photo = scaled
        Self.writePhotoToDisk(scaled)
        update { $0.hasPhoto = true }
    }

    private static func photoURL() -> URL? {
        AppGroup.containerURL?.appendingPathComponent(AppGroup.profilePhotoFilename)
    }

    private static func loadPhotoFromDisk() -> UIImage? {
        guard let url = photoURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func writePhotoToDisk(_ image: UIImage) {
        guard let url = photoURL(),
              let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func deletePhotoFromDisk() {
        guard let url = photoURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Aspect-fit downscale so the longest side is `maxDimension` points.
    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Sign in with Apple

    // MARK: - Sign out

    /// Clear the on-device profile and signal the app shell to return the
    /// user to the auth gate. Apple Health data is untouched.
    public func signOut() {
        Self.deletePhotoFromDisk()
        photo = nil
        profile = nil
        defaults?.removeObject(forKey: AppGroup.Keys.userProfile)
        defaults?.set(false, forKey: AppGroup.Keys.authComplete)
        defaults?.set(false, forKey: AppGroup.Keys.onboardingComplete)
        // Drop the on-disk Health snapshot too — it's keyed to this user.
        Task { await HealthDataCache.shared.clear() }
        NotificationCenter.default.post(name: .paceOffSignOut, object: nil)
    }

    /// Fold a successful Sign in with Apple credential into the profile:
    /// store the stable user ID, and pre-fill the display name on first
    /// sign-in (Apple only provides the name once, on the very first grant).
    public func applyAppleCredential(userID: String, fullName: PersonNameComponents?) {
        update { p in
            p.appleUserID = userID
            if let fullName {
                let formatter = PersonNameComponentsFormatter()
                let name = formatter.string(from: fullName).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && p.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                    p.displayName = name
                }
            }
        }
    }

    #if DEBUG
    /// Force the store into a specific state for SwiftUI previews. Bypasses
    /// disk and UserDefaults — only the in-memory observed properties are
    /// touched, so previews never pollute real user data.
    func previewLoad(profile: UserProfile?, photo: UIImage?) {
        self.profile = profile
        self.photo = photo
    }
    #endif
}
