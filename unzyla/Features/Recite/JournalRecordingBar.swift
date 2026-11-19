import SwiftUI

/// Replaces the tab bar while a journal recording is live: elapsed time, a live
/// waveform from the mic level, and a stop button.
struct JournalRecordingBar: View {
    @Bindable var recorder: DeckAudioRecorder
    let isDarkMode: Bool
    let onStop: () -> Void

    @State private var isPulsing = false

    private var foreground: Color { isDarkMode ? .white : .black }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(isPulsing ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                Text(formattedElapsed)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(foreground)
                    .contentTransition(.numericText())
            }

            RecordingWaveform(levels: recorder.levels, color: .red)
                .frame(maxWidth: .infinity)
                .frame(height: 32)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(foreground.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onAppear { isPulsing = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording, \(formattedElapsed)")
    }

    private var formattedElapsed: String {
        let total = max(0, Int(recorder.elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Right-aligned bars: newest sample on the right, scrolling left as audio arrives.
private struct RecordingWaveform: View {
    let levels: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = DeckAudioRecorder.levelHistoryCount
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let minHeight: CGFloat = 3
            let padded = Array(repeating: Float(0), count: max(0, count - levels.count)) + levels.suffix(count)
            for (index, level) in padded.enumerated() {
                let height = max(minHeight, CGFloat(level) * size.height)
                let x = CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                // Older samples fade toward the left edge.
                let age = Double(index) / Double(max(1, count - 1))
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(color.opacity(0.35 + 0.65 * age))
                )
            }
        }
        .accessibilityHidden(true)
    }
}
