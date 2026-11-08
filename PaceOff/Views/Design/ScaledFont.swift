// ScaledFont.swift
// A system font at a design size that still follows the text-size setting:
// the size scales with Dynamic Type relative to the text style nearest it,
// as @ScaledMetric does, so the big hero numbers grow and shrink with the
// rest of the screen.

import SwiftUI

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` that scales with Dynamic Type.
    /// It scales like the text style its size is nearest to, unless one is
    /// given.
    func scaledFont(size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo style: Font.TextStyle? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design,
                                  relativeTo: style ?? Font.TextStyle.nearest(to: size)))
    }
}

extension Font.TextStyle {
    /// The text style whose default size is nearest `size`, so a design size
    /// scales the way text of about that size does.
    static func nearest(to size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12:  return .caption2
        case ..<13:  return .caption
        case ..<15:  return .footnote
        case ..<16:  return .subheadline
        case ..<17:  return .callout
        case ..<20:  return .body
        case ..<22:  return .title3
        case ..<28:  return .title2
        case ..<34:  return .title
        default:     return .largeTitle
        }
    }
}
