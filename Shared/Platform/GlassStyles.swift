//
//  GlassStyles.swift
//  Shared (app, widget, AutoFill)
//
//  Liquid Glass with a fallback: `glassEffect` and `.glassProminent` don't exist on visionOS,
//  which renders its own materials. Use these helpers instead of the raw modifiers so every
//  supported platform compiles.
//

import SwiftUI

extension View {
    /// Liquid Glass for floating, transient chrome (toasts, overlays) — never for cards or rows.
    @ViewBuilder
    func floatingGlass(in shape: some Shape) -> some View {
        #if os(visionOS)
        background(.regularMaterial, in: shape)
        #else
        glassEffect(.regular, in: shape)
        #endif
    }

    /// Prominent call-to-action button style.
    @ViewBuilder
    func prominentActionStyle() -> some View {
        #if os(visionOS)
        buttonStyle(.borderedProminent)
        #else
        buttonStyle(.glassProminent)
        #endif
    }
}
