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
    /// scales the way text of about that size does. The cut-offs sit
    /// halfway between the default sizes (11, 12, 13, 15, 16, 17, 20, 22,
    /// 28, 34 pt).
    static func nearest(to size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14:   return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18.5: return .body
        case ..<21:   return .title3
        case ..<25:   return .title2
        case ..<31:   return .title
        default:      return .largeTitle
        }
    }
}
