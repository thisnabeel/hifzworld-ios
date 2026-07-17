import SwiftUI

struct SendAppFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var category: AppFeedbackCategory = .other
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $category) {
                        ForEach(AppFeedbackCategory.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("What is this about?")
                }

                Section {
                    TextField("Tell us what’s working, broken, or missing…", text: $message, axis: .vertical)
                        .lineLimit(5...12)
                } header: {
                    Text("Your feedback")
                } footer: {
                    Text("Signed-in users only. We use this to improve Hifzworld.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Thanks!", isPresented: $didSucceed) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your feedback was sent.")
            }
        }
    }

    private var canSubmit: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private func submit() async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await AppFeedbackService().submit(message: trimmed, category: category)
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AppFeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case idea
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return "Bug"
        case .idea: return "Idea"
        case .other: return "Other"
        }
    }
}
