// AuthGateView.swift
// Hard auth gate. Sign in with Apple is the only way forward — there is no
// skip path. Legal links are pinned at the bottom; the rest of the screen is
// the brand hero shared with the onboarding slides.

import SwiftUI
import AuthenticationServices

struct AuthGateView: View {

    let onAuthenticated: () -> Void

    @EnvironmentObject private var appleSignIn: AppleSignInService

    @State private var errorMessage: String?

    var body: some View {
        BrandHero(
            symbol: "figure.run",
            headline: "Show up. Run anyway.",
            subtitle: "A no-excuses running coach in your pocket."
        ) {
            VStack(spacing: 18) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.25),
                                    in: Capsule())
                        .transition(.opacity)
                }

                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleResult(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                .accessibilityHint("Continue with your Apple ID")

                LegalLinksFooter(style: .overlay)
                    .padding(.top, 4)
            }
        }
    }

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        Task { @MainActor in
            let ok = appleSignIn.handleAuthorization(result)
            if ok {
                withAnimation(.easeInOut) { errorMessage = nil }
                onAuthenticated()
            } else if case .failure(let error) = result,
                      (error as? ASAuthorizationError)?.code != .canceled {
                withAnimation(.easeInOut) {
                    errorMessage = "Sign in didn't complete. Please try again."
                }
            }
        }
    }
}

#Preview {
    AuthGateView(onAuthenticated: {})
        .environmentObject(AppleSignInService.shared)
}
