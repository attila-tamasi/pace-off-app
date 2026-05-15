// LegalLinksFooter.swift
// Small reusable row of tappable legal links: "Terms · Privacy · EULA".
// Used at the bottom of AuthGateView and on the Profile tab's legal card.

import SwiftUI

struct LegalLinksFooter: View {

    enum Style {
        /// Light-on-dark, used over the auth-gate gradient backdrop.
        case overlay
        /// Tinted secondary, used on standard system backgrounds.
        case inline
    }

    var style: Style = .overlay

    @State private var presented: LegalDocument?

    var body: some View {
        HStack(spacing: 8) {
            link(.terms)
            dot
            link(.privacy)
            dot
            link(.eula)
        }
        .font(.system(.footnote, design: .rounded, weight: .medium))
        .sheet(item: $presented) { doc in
            LegalView(document: doc)
        }
    }

    private func link(_ doc: LegalDocument) -> some View {
        Button { presented = doc } label: {
            Text(doc.shortLabel)
                .foregroundStyle(textColor)
                .underline(false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(doc.title)")
    }

    private var dot: some View {
        Text("·")
            .foregroundStyle(textColor.opacity(0.6))
    }

    private var textColor: Color {
        switch style {
        case .overlay: return .white
        case .inline:  return .accentColor
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        LegalLinksFooter(style: .inline)
        ZStack {
            BrandPalette.heroGradient.ignoresSafeArea()
            LegalLinksFooter(style: .overlay)
        }
        .frame(height: 200)
    }
}
