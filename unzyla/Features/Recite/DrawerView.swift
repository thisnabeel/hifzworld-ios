import SwiftUI

struct DrawerView: View {
    let user: HifzworldUser?
    var unreadMailCount: Int = 0
    let onSettings: () -> Void
    let onGuide: () -> Void
    let onInbox: () -> Void
    let onSendFeedback: () -> Void
    let onEditHandle: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void
    let onClose: () -> Void

    private static let guideOrange = Color(red: 0.95, green: 0.45, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 14) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Text("Hifzworld")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Read the Mushaf, save pages in Decks, and review with a listener who can mark feedback while you recite.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)

            tipCard
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            guideButton
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            VStack(spacing: 4) {
                if user != nil {
                    drawerRow(
                        title: "Inbox",
                        systemImage: "envelope.fill",
                        badge: unreadMailCount > 0 ? unreadMailCount : nil,
                        action: onInbox
                    )
                }
                drawerRow(
                    title: "Send Feedback",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    action: onSendFeedback
                )
                if user != nil {
                    drawerRow(
                        title: "Edit Handle",
                        systemImage: "at",
                        action: onEditHandle
                    )
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 16)

            if let user {
                userFooter(user)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.drawerBackground)
    }

    private var guideButton: some View {
        Button(action: onGuide) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28)
                Text("New Here? Guide...")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(Self.guideOrange)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Here Guide")
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.35))
                .padding(.top, 1)

            (Text("Tip: ").fontWeight(.semibold) +
             Text("Turn the screen sideways to see both pages of the Mushaf."))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1.0, green: 0.84, blue: 0.35).opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.84, blue: 0.35).opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func userFooter(_ user: HifzworldUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1 / UIScreen.main.scale)

            HStack(spacing: 12) {
                Text(initials(for: user))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let handle = user.handle, !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    } else if let email = user.email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onSignOut) {
                    Text("Sign out")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: onDeleteAccount) {
                Text("Delete Account")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete Account")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 4)
    }

    private func initials(for user: HifzworldUser) -> String {
        let parts = user.displayName
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        if !letters.isEmpty {
            return letters.joined().uppercased()
        }
        if let email = user.email, let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private func drawerRow(
        title: String,
        systemImage: String,
        badge: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                if let badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
