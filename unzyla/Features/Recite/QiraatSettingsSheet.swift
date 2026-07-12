import SwiftUI

struct QiraatSettingsSheet: View {
    let mushafID: Int
    @Binding var isDarkMode: Bool
    let onMushafChange: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMushafID: Int

    init(mushafID: Int, isDarkMode: Binding<Bool>, onMushafChange: @escaping (Int) -> Void) {
        self.mushafID = mushafID
        self._isDarkMode = isDarkMode
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
