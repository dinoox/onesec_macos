import SwiftUI

enum NotificationType {
    case normal, warning, error

    var iconColor: Color {
        switch self {
        case .normal: return .blue
        case .warning: return yellowTextColor
        case .error: return errorTextColor
        }
    }
}

struct NotificationCard: View {
    let title: String
    let content: String
    let panelId: UUID
    let type: NotificationType
    let autoHide: Bool
    let showTimerTip: Bool
    let autoCloseDuration: Int
    let onTap: (() -> Void)?
    let onClose: (() -> Void)?

    private let cardWidth: CGFloat = 250

    @State private var isCardHovered = false
    @State private var progress: CGFloat = 1.0
    @State private var timerTask: Task<Void, Never>?

    init(
        title: String,
        content: String,
        panelId: UUID,
        type: NotificationType = .warning,
        autoHide: Bool = true,
        showTimerTip: Bool = false,
        autoCloseDuration: Int = 4,
        onTap: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.content = content
        self.panelId = panelId
        self.type = type
        self.autoHide = autoHide
        self.showTimerTip = showTimerTip
        self.autoCloseDuration = autoCloseDuration
        self.onTap = onTap
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 13) {
                    ZStack {
                        Image.systemSymbol("bell.fill")
                            .font(.system(size: 18))
                            .foregroundColor(type.iconColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13))
                            .foregroundColor(.overlayText)
                            .lineLimit(1)

                        Text(content)
                            .font(.system(size: 12.5))
                            .foregroundColor(.overlaySecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if showTimerTip {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.overlayPrimary.opacity(0.3))
                            .frame(height: 3)

                        Rectangle()
                            .fill(Color.overlayPrimary)
                            .frame(width: cardWidth * progress, height: 3)
                            .animation(.linear(duration: Double(autoCloseDuration)), value: progress)
                    }
                    .frame(height: 3)
                }
            }
            .frame(width: cardWidth)
            .background(Color.overlayBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.overlayBorder, lineWidth: 1.2)
            )
            .shadow(color: .overlayBackground.opacity(0.2), radius: 6, x: 0, y: 0)
            .onTapGesture {
                onTap?()
            }
            .onHover { hovering in
                isCardHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Button(action: {
                stopAutoCloseTimer()
                OverlayController.shared.hideOverlay(uuid: panelId)
                onClose?()
            }) {
                Image.systemSymbol("xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolAppearEffect(isActive: isCardHovered)
            }
            .buttonStyle(HoverIconButtonStyle(normalColor: .overlayPlaceholder, hoverColor: .overlayText))
            .padding(12)
            .animation(.easeInOut(duration: 0.2), value: isCardHovered)
            .contentShape(Rectangle())
        }
        .scaleEffect(isCardHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isCardHovered)
        .onAppear {
            if autoHide {
                if showTimerTip {
                    startAutoCloseTimer()
                } else {
                    Task { @MainActor in
                        try? await sleep(UInt64(autoCloseDuration) * 1000)
                        guard !Task.isCancelled else { return }
                        OverlayController.shared.hideOverlay(uuid: panelId)
                    }
                }
            }
        }
        .onDisappear {
            stopAutoCloseTimer()
        }
    }

    private func startAutoCloseTimer() {
        timerTask = Task { @MainActor in
            progress = 0
            try? await sleep(UInt64(autoCloseDuration) * 1000)
            guard !Task.isCancelled else { return }
            OverlayController.shared.hideOverlay(uuid: panelId)
        }
    }

    private func stopAutoCloseTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}
