import SwiftUI

struct DrawerView: View {
    let parents: [ParentNarrator]
    @Binding var expandedParents: Set<Int>
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void
    let onSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Qiraat")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(parents) { parent in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                if expandedParents.contains(parent.id) {
                                    expandedParents.remove(parent.id)
                                } else {
                                    expandedParents.insert(parent.id)
                                }
                            } label: {
                                HStack {
                                    Text(parent.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: expandedParents.contains(parent.id) ? "chevron.down" : "chevron.right")
                                        .foregroundStyle(.gray)
                                }
                            }
                            if expandedParents.contains(parent.id) {
                                ForEach(parent.children) { child in
                                    let selected = selectedIDs.contains(child.id)
                                    Button {
                                        onToggle(child.id)
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(Color(hex: child.highlightColor) ?? AppTheme.accent)
                                                .frame(width: 10, height: 10)
                                            Text(child.title)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if selected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(AppTheme.accent)
                                            }
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .background(selected ? Color.white.opacity(0.08) : .clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .disabled(child.isHafs)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.drawerBackground)
    }
}
