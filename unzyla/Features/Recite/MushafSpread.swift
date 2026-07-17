import Foundation

/// Facing-page Mushaf pair: odd page on the right, even partner on the left (RTL open book).
struct MushafSpread: Hashable {
    /// Odd page shown on the right; also the pager / review identity.
    let rightPage: Int
    /// Even partner on the left, when present and allowed.
    let leftPage: Int?

    var displayLabel: String {
        if let leftPage {
            return "\(rightPage)–\(leftPage)"
        }
        return "\(rightPage)"
    }

    var pages: [Int] {
        if let leftPage {
            return [rightPage, leftPage]
        }
        return [rightPage]
    }

    /// Natural mushaf pair for `page` (1|2, 3|4, …). Bundle pairing is applied separately.
    static func natural(containing page: Int, totalPages: Int) -> MushafSpread {
        let clamped = min(max(page, 1), max(totalPages, 1))
        let right = clamped.isMultiple(of: 2) ? clamped - 1 : clamped
        let leftCandidate = right + 1
        let left = leftCandidate <= totalPages ? leftCandidate : nil
        return MushafSpread(rightPage: max(right, 1), leftPage: left)
    }

    /// Spread for navigation identity. In landscape with a full mushaf, always natural pairs.
    /// In bundle mode, only pair when both consecutive pages are in `allowedPages`; otherwise single page.
    static func forDisplay(
        containing page: Int,
        totalPages: Int,
        allowedPages: [Int]?,
        showsSpread: Bool
    ) -> MushafSpread {
        guard showsSpread else {
            return MushafSpread(rightPage: page, leftPage: nil)
        }

        guard let allowed = allowedPages else {
            return natural(containing: page, totalPages: totalPages)
        }

        let natural = natural(containing: page, totalPages: totalPages)
        if let left = natural.leftPage,
           allowed.contains(natural.rightPage),
           allowed.contains(left) {
            return natural
        }

        // Focused page alone (missing partner in bundle).
        let focus = allowed.contains(page) ? page : (allowed.first ?? page)
        return MushafSpread(rightPage: focus, leftPage: nil)
    }

    /// Normalize a requested page to the spread identity used by the pager (`rightPage`).
    static func identityPage(
        for page: Int,
        totalPages: Int,
        allowedPages: [Int]?,
        showsSpread: Bool
    ) -> Int {
        forDisplay(
            containing: page,
            totalPages: totalPages,
            allowedPages: allowedPages,
            showsSpread: showsSpread
        ).rightPage
    }

    /// Next/previous spread identity for swipe. Full mushaf: ±2 on odd rights.
    /// Bundle: step through allowed pages, skipping entries that collapse to the same spread.
    static func adjacentIdentity(
        from identity: Int,
        forward: Bool,
        totalPages: Int,
        allowedPages: [Int]?,
        showsSpread: Bool
    ) -> Int? {
        if !showsSpread {
            if let allowed = allowedPages {
                guard let index = allowed.firstIndex(of: identity) else { return nil }
                let nextIndex = forward ? index + 1 : index - 1
                guard allowed.indices.contains(nextIndex) else { return nil }
                return allowed[nextIndex]
            }
            let next = forward ? identity + 1 : identity - 1
            guard next >= 1, next <= totalPages else { return nil }
            return next
        }

        if let allowed = allowedPages {
            guard let startIndex = allowed.firstIndex(of: identity)
                    ?? allowed.firstIndex(where: {
                        forDisplay(
                            containing: $0,
                            totalPages: totalPages,
                            allowedPages: allowed,
                            showsSpread: true
                        ).rightPage == identity
                    })
            else { return nil }

            var index = startIndex
            while true {
                index = forward ? index + 1 : index - 1
                guard allowed.indices.contains(index) else { return nil }
                let candidate = forDisplay(
                    containing: allowed[index],
                    totalPages: totalPages,
                    allowedPages: allowed,
                    showsSpread: true
                ).rightPage
                if candidate != identity {
                    return candidate
                }
            }
        }

        let step = forward ? 2 : -2
        let next = identity + step
        guard next >= 1, next <= totalPages else { return nil }
        return natural(containing: next, totalPages: totalPages).rightPage
    }
}
