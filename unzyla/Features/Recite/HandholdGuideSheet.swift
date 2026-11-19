import SwiftUI

/// Explains handhold (ayah prompt) mode: what the cover, cue counts and taps do, and why.
struct HandholdGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 14) {
                        Image("HoldingHands")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(AppTheme.accent)
                        Text("Build a mental picture of the page, with a hand to hold while you do.")
                            .font(.title3.weight(.semibold))
                    }

                    section("How it works") {
                        point("rectangle.fill", "The page is covered, but every verse circle stays visible, so you can see where each verse ends and the next one begins.")
                        point("textformat.123", "The numbers choose how many words show after each circle as a cue: **2**, **1**, or **0** for circles only. **-1** uncovers the whole page.")
                        point("hand.tap", "Stuck? Tap a covered word to peek at it, and tap again to hide it.")
                        point("mic", "Record yourself reciting, then listen back in Journal.")
                    }

                    section("Why") {
                        Text("Huffaz often remember a page by its shape: which line a verse starts on, where it sits on that line, how the page opens and how it closes. Keeping the layout visible while the words are hidden trains that picture, so you recite from memory of the page rather than by reading it.")
                            .foregroundStyle(.secondary)
                    }

                    section("A path to try") {
                        step(-1, "Study the page with everything showing.")
                        step(2, "Recite with two-word cues after each circle.")
                        step(1, "Drop to one word as it sticks.")
                        step(0, "Only the circles. When you can recite the page here, the picture is yours.")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Handhold mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func point(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ count: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.1)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    Text("Mushaf").sheet(isPresented: .constant(true)) { HandholdGuideSheet() }
}
