import SwiftUI

struct BundlesTabView: View {
    @Bindable var bundleStore: BundleStore
    @Bindable var auth: AuthService
    @Bindable var reciteVM: ReciteViewModel
    let onOpenInMushaf: (UUID, Int) -> Void

    @State private var showCreateSheet = false
    @State private var showEditSheet = false
    @State private var showSignIn = false
    @State private var newTitle = ""
    @State private var newDescription = ""
    @State private var editingBundleID: UUID?
    @State private var pendingShares: [BundleShareDTO] = []
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isSignedIn {
                    SignInView(auth: auth)
                } else if bundleStore.bundles.isEmpty && pendingShares.isEmpty {
                    ContentUnavailableView(
                        "No Bundles Yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Create a bundle, then add pages from the Mushaf tab.")
                    )
                } else {
                    List {
                        if !pendingShares.isEmpty {
                            Section("Incoming Shares") {
                                ForEach(pendingShares) { share in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(share.bundle?.title ?? "Shared bundle")
                                            .font(.headline)
                                        Text("From \(share.sharedBy?.displayName ?? "Someone")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button("Accept") {
                                            Task { await acceptShare(share) }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Section("My Bundles") {
                            ForEach(bundleStore.bundles) { bundle in
                                bundleRow(bundle)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            startEditing(bundle)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)

                                        Button(role: .destructive) {
                                            bundleStore.deleteBundle(id: bundle.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Bundles")
            .navigationDestination(for: UUID.self) { bundleID in
                BundleDetailView(
                    bundleID: bundleID,
                    bundleStore: bundleStore,
                    auth: auth,
                    reciteVM: reciteVM,
                    onOpenInMushaf: onOpenInMushaf
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newTitle = ""
                        newDescription = ""
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!auth.isSignedIn)
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sync") { Task { await syncBundles() } }
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateBundleSheet(
                    title: $newTitle,
                    description: $newDescription,
                    onCreate: {
                        _ = bundleStore.createBundle(title: newTitle, description: newDescription)
                        Task { await syncBundles() }
                    }
                )
            }
            .sheet(isPresented: $showEditSheet) {
                EditBundleSheet(
                    title: $newTitle,
                    description: $newDescription,
                    onSave: {
                        guard let editingBundleID else { return }
                        bundleStore.updateBundle(
                            id: editingBundleID,
                            title: newTitle,
                            description: newDescription
                        )
                    }
                )
            }
            .task(id: auth.isSignedIn) {
                guard auth.isSignedIn else { return }
                await refreshShares()
            }
            .alert("Sync Error", isPresented: Binding(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("OK") { syncError = nil }
            } message: {
                Text(syncError ?? "")
            }
        }
    }

    @ViewBuilder
    private func bundleRow(_ bundle: MushafBundle) -> some View {
        ZStack(alignment: .leading) {
            NavigationLink(value: bundle.id) {
                EmptyView()
            }
            .opacity(0)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bundle.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if bundle.isShared {
                        Text("Shared")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if !bundle.description.isEmpty {
                    Text(bundle.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(bundle.pageNumbers.count) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private func startEditing(_ bundle: MushafBundle) {
        editingBundleID = bundle.id
        newTitle = bundle.title
        newDescription = bundle.description
        showEditSheet = true
    }

    private func syncBundles() async {
        let service = RemoteBundleService()
        do {
            try await service.uploadLocalBundles(from: bundleStore, mushafID: reciteVM.mushafID)
            try await service.sync(into: bundleStore, mushafID: reciteVM.mushafID)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func refreshShares() async {
        do {
            pendingShares = try await RemoteBundleService().pendingShares()
        } catch {
            pendingShares = []
        }
    }

    private func acceptShare(_ share: BundleShareDTO) async {
        do {
            let accepted = try await RemoteBundleService().acceptShare(id: share.id)
            if let remote = accepted.bundle {
                bundleStore.upsertAcceptedShare(remote)
            }
            await refreshShares()
            await syncBundles()
        } catch {
            syncError = error.localizedDescription
        }
    }
}
