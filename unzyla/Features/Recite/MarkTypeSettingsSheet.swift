import SwiftUI

struct MarkTypeSettingsSheet: View {
    var onChanged: (() -> Void)?
    var isEmbedded = false

    @Environment(\.dismiss) private var dismiss
    @State private var orderedTypes: [MistakeMarkType] = MarkTypeAppearance.orderedTypes()
    @State private var colors: [MistakeMarkType: Color] = [:]

    var body: some View {
        if isEmbedded {
            settingsList
        } else {
            NavigationStack {
                settingsList
            }
        }
    }

    private var settingsList: some View {
        List {
            Section {
                ForEach(orderedTypes) { type in
                    markTypeRow(type)
                }
                .onMove(perform: move)
            } header: {
                Text("Mark Types")
            } footer: {
                Text("Drag to reorder. Colors apply to chips and word highlights on your Mushaf.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Mark Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") { resetDefaults() }
            }
            if !isEmbedded {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { loadFromPrefs() }
    }

    private func markTypeRow(_ type: MistakeMarkType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(colors[type] ?? MarkTypeAppearance.color(for: type))
                    .frame(width: 14, height: 14)
                Text(type.title)
                    .font(.body.weight(.semibold))
                Spacer()
                ColorPicker(
                    "Color",
                    selection: binding(for: type),
                    supportsOpacity: false
                )
                .labelsHidden()
            }

            HStack(spacing: 8) {
                ForEach(MarkTypeAppearance.presetHexes, id: \.self) { hex in
                    Button {
                        applyHex(hex, to: type)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preset \(hex)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func binding(for type: MistakeMarkType) -> Binding<Color> {
        Binding(
            get: { colors[type] ?? MarkTypeAppearance.color(for: type) },
            set: { newValue in
                colors[type] = newValue
                MarkTypeAppearance.setColor(newValue, for: type)
                onChanged?()
            }
        )
    }

    private func applyHex(_ hex: String, to type: MistakeMarkType) {
        MarkTypeAppearance.setHex(hex, for: type)
        colors[type] = Color(hex: hex) ?? MarkTypeAppearance.color(for: type)
        onChanged?()
    }

    private func move(from source: IndexSet, to destination: Int) {
        orderedTypes.move(fromOffsets: source, toOffset: destination)
        MarkTypeAppearance.setOrder(orderedTypes)
        onChanged?()
    }

    private func loadFromPrefs() {
        orderedTypes = MarkTypeAppearance.orderedTypes()
        colors = Dictionary(
            uniqueKeysWithValues: MistakeMarkType.allCases.map { ($0, MarkTypeAppearance.color(for: $0)) }
        )
    }

    private func resetDefaults() {
        MarkTypeAppearance.resetDefaults()
        loadFromPrefs()
        onChanged?()
    }
}
