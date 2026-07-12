import SwiftUI
import UIKit

struct TabBarBundlesHighlight: UIViewControllerRepresentable {
    let isActive: Bool
    let selectedTab: Int
    let bundlesTabIndex: Int

    init(isActive: Bool, selectedTab: Int = 0, bundlesTabIndex: Int = 1) {
        self.isActive = isActive
        self.selectedTab = selectedTab
        self.bundlesTabIndex = bundlesTabIndex
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let tabBar = uiViewController.tabBarController?.tabBar,
                  let items = tabBar.items,
                  bundlesTabIndex < items.count
            else { return }

            let item = items[bundlesTabIndex]
            let highlightColor = UIColor.systemOrange
            let normalColor = UIColor.label
            let selectedColor = UIColor.tintColor

            if isActive {
                item.setTitleTextAttributes([.foregroundColor: highlightColor], for: .normal)
                item.setTitleTextAttributes([.foregroundColor: highlightColor], for: .selected)
                tintTabBarButton(at: bundlesTabIndex, in: tabBar, color: highlightColor)
            } else {
                item.setTitleTextAttributes([.foregroundColor: normalColor], for: .normal)
                item.setTitleTextAttributes([.foregroundColor: selectedColor], for: .selected)
                tintTabBarButton(at: bundlesTabIndex, in: tabBar, color: nil)
            }
        }
    }

    private func tintTabBarButton(at index: Int, in tabBar: UITabBar, color: UIColor?) {
        let buttons = tabBar.subviews
            .filter { String(describing: type(of: $0)).contains("UITabBarButton") }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard index < buttons.count else { return }
        applyTint(color, to: buttons[index])
    }

    private func applyTint(_ color: UIColor?, to view: UIView) {
        if let imageView = view as? UIImageView {
            imageView.tintColor = color
        }
        for subview in view.subviews {
            applyTint(color, to: subview)
        }
    }
}
