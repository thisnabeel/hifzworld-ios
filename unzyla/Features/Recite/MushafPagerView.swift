import SwiftUI
import UIKit

struct RTLMushafPager: UIViewControllerRepresentable {
    @Binding var currentPage: Int
    let mushafID: Int
    let mushafReloadToken: UUID
    let totalPages: Int
    let allowedPages: [Int]?
    let isDarkMode: Bool
    let contentStamp: Int
    let isPagingEnabled: Bool
    let showsSpread: Bool
    let pageContent: (Int) -> AnyView

    init(
        currentPage: Binding<Int>,
        mushafID: Int,
        mushafReloadToken: UUID,
        totalPages: Int,
        allowedPages: [Int]? = nil,
        isDarkMode: Bool,
        contentStamp: Int,
        isPagingEnabled: Bool = true,
        showsSpread: Bool = false,
        pageContent: @escaping (Int) -> AnyView
    ) {
        _currentPage = currentPage
        self.mushafID = mushafID
        self.mushafReloadToken = mushafReloadToken
        self.totalPages = totalPages
        self.allowedPages = allowedPages
        self.isDarkMode = isDarkMode
        self.contentStamp = contentStamp
        self.isPagingEnabled = isPagingEnabled
        self.showsSpread = showsSpread
        self.pageContent = pageContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.dataSource = isPagingEnabled ? context.coordinator : nil
        controller.delegate = context.coordinator
        controller.view.semanticContentAttribute = .forceRightToLeft
        let identity = normalizedIdentity(currentPage)
        if let initial = context.coordinator.controller(for: identity) {
            controller.setViewControllers([initial], direction: .forward, animated: false)
            context.coordinator.lastRenderedPage = identity
        }
        return controller
    }

    func updateUIViewController(_ pageController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        pageController.dataSource = isPagingEnabled ? context.coordinator : nil

        let allowedPagesChanged = context.coordinator.lastAllowedPagesFingerprint != Self.allowedPagesFingerprint(allowedPages)
        if allowedPagesChanged {
            context.coordinator.lastAllowedPagesFingerprint = Self.allowedPagesFingerprint(allowedPages)
        }

        let mushafChanged = context.coordinator.lastMushafReloadToken != mushafReloadToken
        if mushafChanged {
            context.coordinator.lastMushafReloadToken = mushafReloadToken
            context.coordinator.lastRenderedPage = -1
        }

        let spreadModeChanged = context.coordinator.lastShowsSpread != showsSpread
        if spreadModeChanged {
            context.coordinator.lastShowsSpread = showsSpread
            context.coordinator.lastRenderedPage = -1
        }

        let identity = normalizedIdentity(currentPage)
        var didSetViewControllers = false

        if mushafChanged || allowedPagesChanged || spreadModeChanged || context.coordinator.lastRenderedPage != identity,
           let vc = context.coordinator.controller(for: identity) {
            pageController.dataSource = nil
            pageController.setViewControllers([vc], direction: .forward, animated: false)
            pageController.dataSource = isPagingEnabled ? context.coordinator : nil
            context.coordinator.lastRenderedPage = identity
            didSetViewControllers = true
            if currentPage != identity {
                currentPage = identity
            }
        }

        let contentChanged = context.coordinator.lastContentStamp != contentStamp
        if contentChanged && !didSetViewControllers {
            context.coordinator.lastContentStamp = contentStamp
            context.coordinator.refreshVisiblePage(in: pageController)
        } else if contentChanged {
            context.coordinator.lastContentStamp = contentStamp
        }
    }

    private func normalizedIdentity(_ page: Int) -> Int {
        MushafSpread.identityPage(
            for: page,
            totalPages: totalPages,
            allowedPages: allowedPages,
            showsSpread: showsSpread
        )
    }

    private static func allowedPagesFingerprint(_ pages: [Int]?) -> String {
        guard let pages else { return "nil" }
        return pages.map(String.init).joined(separator: ",")
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: RTLMushafPager
        var lastRenderedPage: Int
        var lastMushafReloadToken: UUID
        var lastContentStamp: Int
        var lastAllowedPagesFingerprint: String
        var lastShowsSpread: Bool

        init(_ parent: RTLMushafPager) {
            self.parent = parent
            self.lastRenderedPage = parent.currentPage
            self.lastMushafReloadToken = parent.mushafReloadToken
            self.lastContentStamp = parent.contentStamp
            self.lastAllowedPagesFingerprint = RTLMushafPager.allowedPagesFingerprint(parent.allowedPages)
            self.lastShowsSpread = parent.showsSpread
        }

        func pageRootView(for page: Int) -> AnyView {
            AnyView(
                parent.pageContent(page)
                    .id("\(parent.mushafReloadToken.uuidString)-\(parent.mushafID)-\(page)-\(parent.showsSpread)-\(parent.contentStamp)")
            )
        }

        func controller(for page: Int) -> UIViewController? {
            let identity = MushafSpread.identityPage(
                for: page,
                totalPages: parent.totalPages,
                allowedPages: parent.allowedPages,
                showsSpread: parent.showsSpread
            )
            guard identity >= 1, identity <= parent.totalPages else { return nil }
            let host = UIHostingController(rootView: pageRootView(for: identity))
            host.view.backgroundColor = UIColor(parent.isDarkMode ? AppTheme.mushafDarkBackground : AppTheme.mushafBackground)
            host.view.tag = identity
            return host
        }

        func refreshVisiblePage(in pageController: UIPageViewController) {
            guard let host = pageController.viewControllers?.first as? UIHostingController<AnyView> else { return }
            let page = host.view.tag
            guard page >= 1, page <= parent.totalPages else { return }
            host.rootView = pageRootView(for: page)
        }

        func adjacentPage(from page: Int, forward: Bool) -> Int? {
            MushafSpread.adjacentIdentity(
                from: page,
                forward: forward,
                totalPages: parent.totalPages,
                allowedPages: parent.allowedPages,
                showsSpread: parent.showsSpread
            )
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            let page = viewController.view.tag
            guard let next = adjacentPage(from: page, forward: true) else { return nil }
            return controller(for: next)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            let page = viewController.view.tag
            guard let previous = adjacentPage(from: page, forward: false) else { return nil }
            return controller(for: previous)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let current = pageViewController.viewControllers?.first else {
                if let visible = pageViewController.viewControllers?.first {
                    lastRenderedPage = visible.view.tag
                }
                return
            }
            let page = current.view.tag
            lastRenderedPage = page
            if parent.currentPage != page {
                parent.currentPage = page
            }
        }
    }
}
