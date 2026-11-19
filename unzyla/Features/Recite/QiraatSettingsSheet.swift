import SwiftUI

struct QiraatSettingsSheet: View {
    let mushafID: Int
    @Binding var isDarkMode: Bool
    @Binding var translationLanguage: TranslationLanguage
    @Binding var isTajweedMarkingEnabled: Bool
    var onMarkAppearanceChanged: (() -> Void)?
    let onMushafChange: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var layout: MushafLayout
    @State private var isLayoutChooserOpen = false
    @State private var offersDownloadAfterChooser = false
    @State private var isScanDownloadOpen = false

    init(
        mushafID: Int,
        isDarkMode: Binding<Bool>,
        translationLanguage: Binding<TranslationLanguage>,
        isTajweedMarkingEnabled: Binding<Bool>,
        onMarkAppearanceChanged: (() -> Void)? = nil,
        onMushafChange: @escaping (Int) -> Void
    ) {
        self.mushafID = mushafID
        self._isDarkMode = isDarkMode
        self._translationLanguage = translationLanguage
        self._isTajweedMarkingEnabled = isTajweedMarkingEnabled
        self.onMarkAppearanceChanged = onMarkAppearanceChanged
        self.onMushafChange = onMushafChange
        self._layout = State(initialValue: MushafLayout.current(mushafID: mushafID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mushaf") {
                    Button {
                        isLayoutChooserOpen = true
                    } label: {
                        LabeledContent("Layout") {
                            HStack(spacing: 6) {
                                Text(layout.title)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .tint(.primary)
                    if let scan = layout.scan, scan.edition.baseURL != nil {
                        scanDownloadRow(scan)
                    }
                }
                Section("Appearance") {
                    Toggle("Dark mode", isOn: $isDarkMode)
                }
                Section("Translation") {
                    Picker("Language", selection: $translationLanguage) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Tajweed marks", isOn: $isTajweedMarkingEnabled)
                    NavigationLink("Mark colors & order") {
                        MarkTypeSettingsSheet(onChanged: onMarkAppearanceChanged, isEmbedded: true)
                    }
                } header: {
                    Text("Marking")
                } footer: {
                    Text("When Tajweed is on, you can switch between Mistake and Tajweed while marking. When off, marking uses Mistake only.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $isLayoutChooserOpen, onDismiss: {
                // offer the whole mushaf up front so big page jumps never wait on a download
                if offersDownloadAfterChooser { isScanDownloadOpen = true }
                offersDownloadAfterChooser = false
            }) {
                MushafOnboardingView(initial: layout, isFirstLaunch: false) { chosen in
                    layout = chosen
                    chosen.applyScans()
                    onMushafChange(chosen.mushaf.rawValue)
                    offersDownloadAfterChooser = chosen.needsFullDownload
                    isLayoutChooserOpen = false
                }
            }
            .sheet(isPresented: $isScanDownloadOpen) {
                if let scan = layout.scan {
                    ScanDownloadSheet(store: scan)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: mushafID) { _, newValue in
                layout = MushafLayout.current(mushafID: newValue)
            }
        }
    }

    @ViewBuilder
    private func scanDownloadRow(_ scan: ScanStore) -> some View {
        if scan.isFullyDownloaded {
            Label("Downloaded for offline reading", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            Button {
                isScanDownloadOpen = true
            } label: {
                if scan.isDownloadingAll {
                    LabeledContent("Downloading pages") {
                        Text("\(scan.downloadedPageCount) / \(scan.edition.pageCount)")
                            .monospacedDigit()
                    }
                } else {
                    Label("Download whole mushaf", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
