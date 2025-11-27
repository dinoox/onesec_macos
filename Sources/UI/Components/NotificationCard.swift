import SwiftUI

struct NotificationCard: View {
    let title: String
    let content: String
    let panelId: UUID
    let autoHide: Bool
    let showTimerTip: Bool
    let autoCloseDuration: Int
    let onTap: (() -> Void)?
    let onClose: (() -> Void)?

    private let cardWidth: CGFloat = 240

    @State private var isCloseHovered = false
    @State private var isCardHovered = false
    @State private var progress: CGFloat = 1.0
    @State private var timerTask: Task<Void, Never>?

    init(
        title: String,
        content: String,
        panelId: UUID,
        autoHide: Bool = true,
        showTimerTip: Bool = false,
        autoCloseDuration: Int = 3,
        onTap: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.content = content
        self.panelId = panelId
        self.autoHide = autoHide
        self.showTimerTip = showTimerTip
        self.autoCloseDuration = autoCloseDuration
        self.onTap = onTap
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Image.systemSymbol("bell.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.overlayPrimary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.overlayText)
                            .lineLimit(1)

                        Text(content)
                            .font(.system(size: 12))
                            .foregroundColor(.overlaySecondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

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
                    .foregroundColor(isCloseHovered ? .overlayText : .overlaySecondaryText)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                isCloseHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .padding(12)
            .animation(.easeInOut(duration: 0.2), value: isCloseHovered)
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
