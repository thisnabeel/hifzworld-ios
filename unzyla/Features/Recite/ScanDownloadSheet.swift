import SwiftUI

/// Offers a whole scanned mushaf for download, then shows its progress. Reading carries on while
/// it runs; pages not yet downloaded still load on demand.
struct ScanDownloadSheet: View {
    @Bindable var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @State private var isLowOnSpace = false

    var body: some View {
        VStack(spacing: 20) {
            icon
                .font(.system(size: 44, weight: .regular))
                .frame(height: 56)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            if store.isDownloadingAll {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                    Text("\(store.downloadedPageCount) of \(pageCount) pages")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .presentationDetents([.medium])
        .alert("Not Enough Space", isPresented: $isLowOnSpace) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free up about \(remainingSize) on your device to download the whole mushaf. Pages will keep downloading as you read.")
        }
    }

    private var pageCount: Int { store.edition.pageCount }
    private var name: String { store.edition.shortName }

    private var progress: Double {
        Double(store.downloadedPageCount) / Double(max(pageCount, 1))
    }

    private var remainingSize: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(store.remainingPageCount) * store.edition.approximateBytesPerPage,
            countStyle: .file
        )
    }

    private var hasFailures: Bool {
        !store.isDownloadingAll && !store.isFullyDownloaded && store.fullDownloadFailedCount > 0
    }

    @ViewBuilder
    private var icon: some View {
        if store.isFullyDownloaded {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if hasFailures {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
        } else {
            Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
        }
    }

    private var title: String {
        if store.isFullyDownloaded { return "\(name) Mushaf Downloaded" }
        if store.isDownloadingAll { return "Downloading \(name) Mushaf" }
        if hasFailures { return "Download Paused" }
        return "Download the \(name) Mushaf?"
    }

    private var message: String {
        if store.isFullyDownloaded {
            return "All \(pageCount) scanned pages are on this device. Page turns are instant, even offline."
        }
        if store.isDownloadingAll {
            return "You can close this and keep reading. The download carries on in the background."
        }
        if hasFailures {
            return "\(store.fullDownloadFailedCount) pages couldn’t be downloaded. Check your connection and try again."
        }
        return "Download all \(pageCount) scanned pages (about \(remainingSize)) so every page opens instantly, even offline. Otherwise pages download as you read."
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if store.isFullyDownloaded {
                primaryButton("Done") { dismiss() }
            } else if store.isDownloadingAll {
                primaryButton("Continue in Background") { dismiss() }
                Button("Stop Download", role: .destructive) { store.cancelDownloadAll() }
            } else {
                primaryButton(hasFailures ? "Try Again" : "Download") { startDownload() }
                Button("Not Now") {
                    store.cancelDownloadAll()
                    dismiss()
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
    }

    private func startDownload() {
        guard store.hasRoomForFullDownload() else {
            isLowOnSpace = true
            return
        }
        store.downloadAll()
    }
}
