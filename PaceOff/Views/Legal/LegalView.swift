// LegalView.swift
// Enum-driven scrollable long-form legal screens. The copy below is honest
// placeholder text aligned with Pace Off's privacy stance (Data Not Collected,
// HealthKit-sourced, on-device-only). It MUST be reviewed and replaced by
// counsel before App Store submission.

import SwiftUI

enum LegalDocument: String, Identifiable, CaseIterable {
    case terms
    case privacy
    case eula

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms:   return "Terms of Service"
        case .privacy: return "Privacy Policy"
        case .eula:    return "End User License Agreement"
        }
    }

    var shortLabel: String {
        switch self {
        case .terms:   return "Terms"
        case .privacy: return "Privacy"
        case .eula:    return "EULA"
        }
    }
}

struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    placeholderBanner

                    Text(document.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))

                    Text("Last updated: \(Self.lastUpdated)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)

                    Divider().padding(.vertical, 4)

                    body(for: document)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.shortLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var placeholderBanner: some View {
        Label("Placeholder copy. Replace with counsel-reviewed text before App Store submission.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func body(for document: LegalDocument) -> some View {
        switch document {
        case .terms:   termsBody
        case .privacy: privacyBody
        case .eula:    eulaBody
        }
    }

    // MARK: - Terms

    private var termsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("1. The agreement",
                    "By installing and using Pace Off (\"the App\"), you agree to these Terms of Service. If you do not agree, do not use the App.")
            section("2. What the App does",
                    "Pace Off is a personal running-motivation tool. It reads workout, heart-rate, and related data from Apple Health on your device, and uses it to schedule local notifications, generate suggested workout targets, and surface progress. It does not provide medical advice and is not a substitute for professional guidance.")
            section("3. Your responsibility",
                    "Running carries inherent risk of injury. You are responsible for assessing your own fitness, consulting a physician where appropriate, and stopping any activity that causes pain or distress. The App's suggestions are informational only.")
            section("4. Accounts",
                    "Sign in with Apple is used to bind the App to your Apple ID locally on this device. Pace Off does not run a server; there is no account to log into elsewhere, and nothing about you is transmitted to us.")
            section("5. License",
                    "You are granted a personal, non-exclusive, non-transferable license to use Pace Off as distributed via the App Store. See the EULA for full license terms.")
            section("6. No warranty",
                    "The App is provided \"as is\". To the maximum extent permitted by law we disclaim all warranties, including fitness for a particular purpose and non-infringement.")
            section("7. Limitation of liability",
                    "We are not liable for any incidental, indirect, or consequential damages arising from your use of the App, to the maximum extent permitted by law.")
            section("8. Changes",
                    "We may update these terms. Continued use of the App after an update constitutes acceptance of the revised terms.")
            section("9. Contact",
                    "Questions? Reach out via the support contact listed on the App Store product page.")
        }
    }

    // MARK: - Privacy

    private var privacyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Short version",
                    "Pace Off does not collect your data. Everything stays on your iPhone, Apple Watch, and Apple Health. We do not run servers, do not have analytics, and do not have ads.")
            section("What stays on-device",
                    "Your profile (name, optional birthday, goal, optional personal best, optional photo), notification preferences, and a small amount of cached state used to decide which push to send next. This is stored in iOS's private app storage and the App Group container that the iPhone, Watch, and widget share.")
            section("What we read from Apple Health",
                    "With your permission, the App reads workouts, heart rate, heart-rate variability, VO₂ max, running dynamics, and similar fitness data from HealthKit. This data is read on your device only. We do not copy it off your device.")
            section("Sign in with Apple",
                    "If you sign in with Apple, the App stores Apple's app-scoped identifier and (on first grant) your name locally. Nothing is sent to a server, because the App does not have one.")
            section("Notifications",
                    "Notifications are scheduled locally by iOS. The App does not use remote push.")
            section("Third parties",
                    "Pace Off does not share data with third parties. Apple's HealthKit, Sign in with Apple, and notification systems are governed by Apple's own privacy policy.")
            section("Children",
                    "The App is not directed at children under 13.")
            section("Your controls",
                    "You can revoke HealthKit access from the Health app, revoke Sign in with Apple from iOS Settings, and uninstall the App at any time. Uninstalling removes all on-device data.")
            section("Changes",
                    "If our practices ever change, we'll update this policy and surface the change inside the App before it takes effect.")
        }
    }

    // MARK: - EULA

    private var eulaBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("1. License grant",
                    "Subject to your compliance with these terms and the App Store Terms of Service, you are granted a limited, non-exclusive, non-transferable license to install and use Pace Off on devices you own or control.")
            section("2. Restrictions",
                    "You may not copy, modify, reverse engineer, decompile, or create derivative works of the App, except to the extent such restriction is prohibited by applicable law.")
            section("3. Ownership",
                    "The App and all related intellectual property remain the property of the developer. No rights are granted other than those expressly set out here.")
            section("4. Auto-updates",
                    "The App may be updated through the App Store. Updates may add, change, or remove functionality.")
            section("5. Termination",
                    "This license terminates automatically if you violate these terms. On termination, you must uninstall the App and destroy any copies.")
            section("6. Disclaimers",
                    "The App is provided \"as is\" without warranty. See the Terms of Service for full disclaimers and limitations of liability.")
            section("7. Apple's role",
                    "You acknowledge that this license is between you and the developer, not Apple. Apple is not responsible for the App or its content. Apple has no obligation to provide support for the App.")
            section("8. Governing law",
                    "This agreement is governed by the laws of the developer's principal place of business, without regard to its conflict-of-laws provisions.")
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text(body)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    private static var lastUpdated: String {
        // Best-effort static date so the placeholder reads like a real policy.
        "May 2026"
    }
}

#Preview("Terms") {
    LegalView(document: .terms)
}

#Preview("Privacy") {
    LegalView(document: .privacy)
}
