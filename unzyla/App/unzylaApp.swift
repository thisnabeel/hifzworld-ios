import SwiftUI

@main
struct unzylaApp: App {
    init() {
        FontRegistration.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onOpenURL { url in
                    DeckInviteHandler.shared.handle(url: url)
                }
        }
    }
}
