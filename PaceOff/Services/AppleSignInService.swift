// AppleSignInService.swift
// Thin wrapper around Sign in with Apple (AuthenticationServices).
//
// Pace Off has no backend, so "authentication" here means: obtain Apple's
// stable, app-scoped user identifier and (on first grant) the user's name,
// store them locally in the profile, and on each launch verify the
// credential is still authorized. If the user revokes access in iOS
// Settings, `credentialState` flips to `.revoked` and we clear the link.

import Foundation
import AuthenticationServices

@MainActor
public final class AppleSignInService: ObservableObject {

    public static let shared = AppleSignInService()

    public enum State: Equatable {
        case unknown          // not checked yet this launch
        case notSignedIn      // user skipped, or never signed in
        case signedIn         // credential present and authorized
        case revoked          // user revoked access in Settings
    }

    @Published public private(set) var state: State = .unknown

    private init() {}

    /// Process the result handed back by SwiftUI's `SignInWithAppleButton`.
    /// On success, persists the identity into the shared `ProfileStore`.
    /// Returns true when a usable credential was obtained.
    @discardableResult
    public func handleAuthorization(_ result: Result<ASAuthorization, Error>) -> Bool {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                state = .notSignedIn
                return false
            }
            ProfileStore.shared.applyAppleCredential(
                userID: credential.user,
                fullName: credential.fullName
            )
            state = .signedIn
            return true

        case .failure:
            // User cancelled or the request errored — leave them unsigned,
            // they can still build a local-only profile.
            if state != .signedIn { state = .notSignedIn }
            return false
        }
    }

    /// On app launch, confirm a previously-linked Apple ID is still authorized.
    /// No-op when the user never signed in.
    public func refreshCredentialState() async {
        guard let userID = ProfileStore.shared.profile?.appleUserID else {
            state = .notSignedIn
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        let result: ASAuthorizationAppleIDProvider.CredentialState =
            await withCheckedContinuation { continuation in
                provider.getCredentialState(forUserID: userID) { credentialState, _ in
                    continuation.resume(returning: credentialState)
                }
            }
        switch result {
        case .authorized:
            state = .signedIn
        case .revoked:
            state = .revoked
            ProfileStore.shared.update { $0.appleUserID = nil }
        case .notFound, .transferred:
            state = .notSignedIn
            ProfileStore.shared.update { $0.appleUserID = nil }
        @unknown default:
            state = .notSignedIn
        }
    }
}
