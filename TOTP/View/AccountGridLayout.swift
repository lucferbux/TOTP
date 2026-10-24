//
//  AccountGridLayout.swift
//  TOTP
//
//  Columns for the regular-width account grid (iPad, iPhone Duo open, Mac), aware of the fold.
//

import SwiftUI

/// Where a fold can divide a view: iPhone Duo's inner display folds down the middle.
struct FoldGeometry: Equatable {
    var width: CGFloat = 0
    /// The view sits on a display that can fold, even if it's fully open right now.
    var isFoldable = false
    /// Horizontal span to keep clear while a fold divides the view side by side (partially open,
    /// like a book), in the view's own coordinates, margins included.
    var keepClear: ClosedRange<CGFloat>?

    init() {}

    init(_ proxy: GeometryProxy) {
        width = proxy.size.width
        #if os(iOS)
        if #available(iOS 27.1, *) {
            isFoldable = !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
            if let fold = proxy.reservedRegions(kind: .division)
                .first(where: { $0.isActive && $0.frame.height > $0.frame.width }) {
                let leading = max(fold.margins.leading, AccountGridLayout.spacing / 2)
                let trailing = max(fold.margins.trailing, AccountGridLayout.spacing / 2)
                keepClear = (fold.frame.minX - leading)...(fold.frame.maxX + trailing)
            }
        }
        #endif
    }

    /// The same fold, seen from a view inset by `inset` on each side.
    func inset(by inset: CGFloat) -> FoldGeometry {
        var copy = self
        copy.width = max(0, width - 2 * inset)
        copy.keepClear = keepClear.map { ($0.lowerBound - inset)...($0.upperBound - inset) }
        return copy
    }
}

/// Columns for the regular-width grid.
///
/// On a display that can fold the count is always even once there's room for more than one, so the
/// fold falls between columns rather than across a card. While a fold divides the grid, each side
/// gets its own columns and the gap between the two sides covers the fold.
enum AccountGridLayout {
    static let minimumCardWidth: CGFloat = 300
    static let maximumCardWidth: CGFloat = 480
    static let spacing: CGFloat = 16

    static func columns(for fold: FoldGeometry) -> [GridItem] {
        let width = fold.width
        if let clear = fold.keepClear, clear.lowerBound > 0, clear.upperBound < width {
            let leading = clear.lowerBound
            let trailing = width - clear.upperBound
            let perSide = min(count(fitting: leading), count(fitting: trailing))
            let gap = clear.upperBound - clear.lowerBound
            return side(spanning: leading, columns: perSide, then: gap)
                + side(spanning: trailing, columns: perSide, then: spacing)
        }
        var count = count(fitting: width)
        if fold.isFoldable, count > 1, !count.isMultiple(of: 2) {
            count -= 1
        }
        return Array(repeating: GridItem(.flexible(minimum: minimumCardWidth, maximum: maximumCardWidth),
                                         spacing: spacing),
                     count: count)
    }

    /// How many cards of at least the minimum width fit in `span` (at least one).
    private static func count(fitting span: CGFloat) -> Int {
        max(1, Int(((span + spacing) / (minimumCardWidth + spacing)).rounded(.down)))
    }

    /// `columns` equal columns filling `span` exactly; the last is followed by `then`.
    private static func side(spanning span: CGFloat, columns: Int, then trailingSpacing: CGFloat) -> [GridItem] {
        let width = max(0, (span - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        return (0..<columns).map { index in
            GridItem(.fixed(width), spacing: index == columns - 1 ? trailingSpacing : spacing)
        }
    }
}
