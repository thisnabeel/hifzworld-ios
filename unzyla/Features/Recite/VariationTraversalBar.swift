import SwiftUI

struct VariationTraversalBar: View {
    let items: [TraversalItem]
    let index: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        if items.isEmpty { EmptyView() }
        else {
            let item = items[index]
            HStack(spacing: 12) {
                Button(action: onPrevious) {
                    Text("‹")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .disabled(index == 0)

                VStack(spacing: 4) {
                    Text(item.narratorTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.85, green: 0.85, blue: 0.86))
                    Text(item.variationText)
                        .font(.custom(MushafTypography.FontName.aswaatOne, size: 24))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(red: 0.29, green: 0.30, blue: 0.36))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: onNext) {
                    Text("›")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .disabled(index >= items.count - 1)
            }
            .padding(.horizontal, 10)
        }
    }
}
