//
//  LayoutTests.swift
//  TOTPTests
//
//  Regular-width grid columns, including iPhone Duo's fold.
//

import Testing
import SwiftUI
@testable import TOTP

@Suite("Account grid columns")
struct AccountGridLayoutTests {
    private func fold(width: CGFloat, foldable: Bool = false, keepClear: ClosedRange<CGFloat>? = nil) -> FoldGeometry {
        var fold = FoldGeometry()
        fold.width = width
        fold.isFoldable = foldable
        fold.keepClear = keepClear
        return fold
    }

    private func fixedWidths(_ columns: [GridItem]) -> [CGFloat] {
        columns.compactMap { column in
            if case let .fixed(width) = column.size { return width }
            return nil
        }
    }

    @Test("A display that can't fold keeps every column that fits (iPad, Mac)")
    func unfoldableKeepsOddCounts() {
        #expect(AccountGridLayout.columns(for: fold(width: 1_000)).count == 3)
        #expect(AccountGridLayout.columns(for: fold(width: 250)).count == 1)
    }

    @Test("A display that can fold uses an even count, so the fold falls between columns")
    func foldableUsesEvenCounts() {
        #expect(AccountGridLayout.columns(for: fold(width: 1_000, foldable: true)).count == 2)
        #expect(AccountGridLayout.columns(for: fold(width: 1_300, foldable: true)).count == 4)
        // Too narrow for two: one column is still one column
        #expect(AccountGridLayout.columns(for: fold(width: 400, foldable: true)).count == 1)
    }

    @Test("While folded like a book, each side gets its own columns and no card crosses the fold")
    func partiallyFoldedSplitsAroundTheFold() {
        let clear: ClosedRange<CGFloat> = 330...370
        let columns = AccountGridLayout.columns(for: fold(width: 700, foldable: true, keepClear: clear))
        let widths = fixedWidths(columns)
        #expect(widths.count == 2)

        // Lay the columns out as LazyVGrid does: width, then that column's trailing spacing
        var x: CGFloat = 0
        var frames: [ClosedRange<CGFloat>] = []
        for (width, column) in zip(widths, columns) {
            frames.append(x...(x + width))
            x += width + (column.spacing ?? 0)
        }
        #expect(frames.allSatisfy { !$0.overlaps(clear) || $0.upperBound == clear.lowerBound || $0.lowerBound == clear.upperBound })
        #expect(frames[0].upperBound == clear.lowerBound)
        #expect(frames[1].lowerBound == clear.upperBound)
        #expect(frames[1].upperBound == 700)
    }

    @Test("A fold outside the grid is ignored")
    func foldOutsideGridIsIgnored() {
        let columns = AccountGridLayout.columns(for: fold(width: 700, foldable: true, keepClear: 720...760))
        #expect(columns.count == 2)
        #expect(fixedWidths(columns).isEmpty)
    }

    @Test("Insetting moves the fold into the inset view's coordinates")
    func insetMovesTheFold() {
        let inset = fold(width: 732, foldable: true, keepClear: 346...386).inset(by: 16)
        #expect(inset.width == 700)
        #expect(inset.keepClear == 330...370)
    }
}
