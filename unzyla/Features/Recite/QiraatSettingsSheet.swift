import SwiftUI

struct QiraatSettingsSheet: View {
    let mushafID: Int
    @Binding var isDarkMode: Bool
    @Binding var translationLanguage: TranslationLanguage
    @Binding var isTajweedMarkingEnabled: Bool
    var onMarkAppearanceChanged: (() -> Void)?
    let onMushafChange: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMushafID: Int

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
        self._selectedMushafID = State(initialValue: mushafID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mushaf") {
                    Picker("Layout", selection: $selectedMushafID) {
                        Text("13 Liner IndoPak").tag(MushafID.indoPak.rawValue)
                        Text("15 Liner Uthmani").tag(MushafID.uthmani.rawValue)
                    }
                    .onChange(of: selectedMushafID) { _, newValue in
                        onMushafChange(newValue)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: mushafID) { _, newValue in
                selectedMushafID = newValue
            }
        }
    }
}
