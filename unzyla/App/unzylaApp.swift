import SwiftUI

@main
struct unzylaApp: App {
    init() {
        FontRegistration.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
