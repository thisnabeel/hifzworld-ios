import SwiftUI

struct RootTabView: View {
    @State private var reciteVM = ReciteViewModel()
    @State private var bundleStore = BundleStore.shared
    @State private var auth = AuthService.shared
    @State private var selectedTab = 0
    @State private var showCreateBundleFromMushaf = false
    @State private var newBundleTitle = ""
    @State private var newBundleDescription = ""
    @Bindable private var network = NetworkMonitor.shared

    var body: some View {
        Group {
            if let wall = reciteVM.iosUpdateWall, wall.blocked {
                UpdateRequiredView(
                    installed: wall.installed ?? "?",
                    required: wall.minVersion ?? "?"
                )
            } else {
                VStack(spacing: 0) {
                    OfflineBanner(isConnected: network.isConnected)
                    TabView(selection: $selectedTab) {
                        ReciteTabView(
                            viewModel: reciteVM,
                            bundleStore: bundleStore,
                            onCreateBundle: {
                                newBundleTitle = ""
                                newBundleDescription = ""
                                showCreateBundleFromMushaf = true
                            }
                        )
                        .tabItem {
                            Label("Mushaf", systemImage: "book.fill")
                        }
                        .tag(0)

                        BundlesTabView(
                            bundleStore: bundleStore,
                            auth: auth,
                            reciteVM: reciteVM,
                            onOpenInMushaf: openBundleInMushaf
                        )
                        .tabItem {
                            Label("Bundles", systemImage: "square.stack.3d.up")
                        }
                        .tag(1)

                        FeedbackTabView(auth: auth, onOpenBundle: openFeedbackMark)
                            .tabItem {
                                Label("Feedback", systemImage: "text.badge.checkmark")
                            }
                            .tag(2)
                    }
                    .background(TabBarBundlesHighlight(isActive: reciteVM.isBundleMushafMode, selectedTab: selectedTab, bundlesTabIndex: 1))
                }
            }
        }
        .task {
            await auth.bootstrap()
            await reciteVM.bootstrap()
            await syncBundlesIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await reciteVM.checkMinVersion() }
        }
        .sheet(isPresented: $showCreateBundleFromMushaf) {
            CreateBundleSheet(
                title: $newBundleTitle,
                description: $newBundleDescription,
                onCreate: {
                    let bundle = bundleStore.createBundle(
                        title: newBundleTitle,
                        description: newBundleDescription
                    )
                    bundleStore.addPage(reciteVM.currentPage, to: bundle.id)
                }
            )
        }
    }

    private func openBundleInMushaf(bundleID: UUID, page: Int) {
        guard let bundle = bundleStore.bundle(id: bundleID) else { return }
        reciteVM.enterBundleMushaf(bundle: bundle, startingPage: page)
        selectedTab = 0
    }

    private func openFeedbackMark(bundleServerID: UUID, page: Int, wordID: Int) {
        guard let bundle = bundleStore.bundle(serverID: bundleServerID) else { return }
        reciteVM.enterBundleMushaf(bundle: bundle, startingPage: page)
        reciteVM.activeWordID = wordID
        selectedTab = 0
    }

    private func syncBundlesIfNeeded() async {
        guard auth.isSignedIn else { return }
        let service = RemoteBundleService()
        do {
            try await service.uploadLocalBundles(from: bundleStore, mushafID: reciteVM.mushafID)
            try await service.sync(into: bundleStore, mushafID: reciteVM.mushafID)
        } catch {
            // Non-fatal during bootstrap
        }
    }
}
