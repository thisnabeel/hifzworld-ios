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
    let pageContent: (Int) -> AnyView

    init(
        currentPage: Binding<Int>,
        mushafID: Int,
        mushafReloadToken: UUID,
        totalPages: Int,
        allowedPages: [Int]? = nil,
        isDarkMode: Bool,
        contentStamp: Int,
        pageContent: @escaping (Int) -> AnyView
    ) {
        _currentPage = currentPage
        self.mushafID = mushafID
        self.mushafReloadToken = mushafReloadToken
        self.totalPages = totalPages
        self.allowedPages = allowedPages
        self.isDarkMode = isDarkMode
        self.contentStamp = contentStamp
        self.pageContent = pageContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.semanticContentAttribute = .forceRightToLeft
        if let initial = context.coordinator.controller(for: currentPage) {
            controller.setViewControllers([initial], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ pageController: UIPageViewController, context: Context) {
        context.coordinator.parent = self

        let allowedPagesChanged = context.coordinator.lastAllowedPagesFingerprint != Self.allowedPagesFingerprint(allowedPages)
        if allowedPagesChanged {
            context.coordinator.lastAllowedPagesFingerprint = Self.allowedPagesFingerprint(allowedPages)
        }

        let mushafChanged = context.coordinator.lastMushafReloadToken != mushafReloadToken
        if mushafChanged {
            context.coordinator.lastMushafReloadToken = mushafReloadToken
            context.coordinator.lastRenderedPage = -1
        }

        var didSetViewControllers = false

        if mushafChanged || allowedPagesChanged || context.coordinator.lastRenderedPage != currentPage,
           let vc = context.coordinator.controller(for: currentPage) {
            pageController.dataSource = nil
            pageController.setViewControllers([vc], direction: .forward, animated: false)
            pageController.dataSource = context.coordinator
            context.coordinator.lastRenderedPage = currentPage
            didSetViewControllers = true
        }

        let contentChanged = context.coordinator.lastContentStamp != contentStamp
        if contentChanged && !didSetViewControllers {
            context.coordinator.lastContentStamp = contentStamp
            context.coordinator.refreshVisiblePage(in: pageController)
        } else if contentChanged {
            context.coordinator.lastContentStamp = contentStamp
        }
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

        init(_ parent: RTLMushafPager) {
            self.parent = parent
            self.lastRenderedPage = parent.currentPage
            self.lastMushafReloadToken = parent.mushafReloadToken
            self.lastContentStamp = parent.contentStamp
            self.lastAllowedPagesFingerprint = RTLMushafPager.allowedPagesFingerprint(parent.allowedPages)
        }

        func pageRootView(for page: Int) -> AnyView {
            AnyView(
                parent.pageContent(page)
                    .id("\(parent.mushafReloadToken.uuidString)-\(parent.mushafID)-\(page)-\(parent.contentStamp)")
            )
        }

        func controller(for page: Int) -> UIViewController? {
            guard page >= 1, page <= parent.totalPages else { return nil }
            let host = UIHostingController(rootView: pageRootView(for: page))
            host.view.backgroundColor = UIColor(parent.isDarkMode ? AppTheme.mushafDarkBackground : AppTheme.mushafBackground)
            host.view.tag = page
            return host
        }

        func refreshVisiblePage(in pageController: UIPageViewController) {
            guard let host = pageController.viewControllers?.first as? UIHostingController<AnyView> else { return }
            let page = host.view.tag
            guard page >= 1, page <= parent.totalPages else { return }
            host.rootView = pageRootView(for: page)
        }

        func adjacentPage(from page: Int, forward: Bool) -> Int? {
            if let allowed = parent.allowedPages {
                guard let index = allowed.firstIndex(of: page) else { return nil }
                let nextIndex = forward ? index + 1 : index - 1
                guard allowed.indices.contains(nextIndex) else { return nil }
                return allowed[nextIndex]
            }
            let next = forward ? page + 1 : page - 1
            guard next >= 1, next <= parent.totalPages else { return nil }
            return next
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
