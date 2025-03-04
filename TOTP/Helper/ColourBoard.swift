import Foundation
import SwiftUI

public struct ColourBoard<S: Shape>: ViewModifier {
    public var base: S
    public var color: Color
    public var brightness: Double
    public var innerSize: Double
    public var middleSize: Double?
    public var outerSize: Double?
    public var innerBlur: Double?
    public var blur: Double
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                self.base
                    .stroke(self.color, lineWidth: CGFloat(self.innerSize))
                    .allowsHitTesting(false)
            )
            .overlay(
                self.base
                    .stroke(self.color, lineWidth: CGFloat(self.middleSize ?? self.innerSize))
                    .brightness(self.brightness)
                    .allowsHitTesting(false)
            )
    }
}
