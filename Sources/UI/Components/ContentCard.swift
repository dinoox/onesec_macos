import AppKit
import SwiftUI

struct ActionButton {
    let title: String
    let action: () -> Void
    let clickToClose: Bool = true
}

struct ContentCard<CustomContent: View>: View {
    let panelID: UUID
    let title: String
    let content: String
    let onTap: (() -> Void)?
    let actionButtons: [ActionButton]?
    let customContent: (() -> CustomContent)?
    let cardWidth: CGFloat

    private let autoCloseDuration = 12
    private let maxContentHeight: CGFloat = 350

    @State private var isContentCopied = false
    @State private var showBottomSection = true
    @State private var contentHeight: CGFloat = 0
    @State private var remainingSeconds = 12
    @State private var timerTask: Task<Void, Never>?
    @State private var isHovering = false

    init(
        panelID: UUID,
        title: String,
        content: String = "",
        onTap: (() -> Void)? = nil,
        actionButtons: [ActionButton]? = nil,
        cardWidth: CGFloat = 280,
        @ViewBuilder customContent: @escaping () -> CustomContent
    ) {
        self.panelID = panelID
        self.title = title
        self.content = content
        self.onTap = onTap
        self.actionButtons = actionButtons
        self.cardWidth = cardWidth
        self.customContent = customContent
    }

    var body: some View {
        VStack {
            Spacer()
            cardContent
        }
        .frame(width: cardWidth)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Title Bar
            VStack(alignment: .leading, spacing: 8.5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.overlayText)
                        .lineLimit(1)

                    Spacer()

                    Button(action: closeCard) {
                        Image.systemSymbol("xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(HoverButtonStyle(normalColor: .overlayPlaceholder, hoverColor: .overlayText))
                    .opacity(isHovering ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                }

                if let customContent = customContent {
                    customContent()
                } else {
                    ScrollView(.vertical, showsIndicators: contentHeight > maxContentHeight) {
                        Text(content)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.overlaySecondaryText)
                            .lineSpacing(3.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.onAppear {
                                        contentHeight = geometry.size.height
                                    }
                                }
                            )
                    }
                    .frame(maxHeight: maxContentHeight)
                }

                HStack {
                    Spacer()
                    Button(action: handleCopyContent) {
                        HStack(spacing: 4) {
                            Image.systemSymbol(isContentCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .scaleEffect(isContentCopied ? 1.1 : 1.0)
                                .animation(.quickSpringAnimation, value: isContentCopied).frame(height: 12)

                            Text("复制").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(HoverButtonStyle(normalColor: .overlayPlaceholder, hoverColor: .overlayText))
                    .disabled(isContentCopied)
                    .opacity(isHovering ? (isContentCopied ? 0.5 : 1.0) : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)

            // Bottom Timer Tip
            if showBottomSection {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.overlayPrimary.opacity(0.3))
                        .frame(height: 3.5)

                    Rectangle()
                        .fill(Color.overlayPrimary)
                        .frame(width: cardWidth * CGFloat(remainingSeconds) / CGFloat(autoCloseDuration), height: 3)
                        .animation(.linear(duration: 1.0), value: remainingSeconds)
                }
                .frame(height: 3.5)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.overlayBorder, lineWidth: 1.2)
        )
        .shadow(color: .overlayBackground.opacity(0.2), radius: 6, x: 0, y: 0)
        .onTapGesture { onTap?() }
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear { startAutoCloseTimer() }
        .onDisappear { stopAutoCloseTimer() }
    }

    private func closeCard() {
        stopAutoCloseTimer()
        OverlayController.shared.hideOverlay(uuid: panelID)
    }

    private func closeTipsSection() {
        stopAutoCloseTimer()
        withAnimation(.springAnimation) {
            showBottomSection = false
        }
    }

    private func handleCopyContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        withAnimation {
            isContentCopied = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                isContentCopied = false
            }
        }
    }

    private func startAutoCloseTimer() {
        timerTask = Task { @MainActor in
            var currentSeconds = autoCloseDuration
            while currentSeconds >= 0 {
                guard !Task.isCancelled else { return }

                if !isHovering {
                    remainingSeconds = currentSeconds
                    if currentSeconds == 0 {
                        closeCard()
                        return
                    }
                    currentSeconds -= 1
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopAutoCloseTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}

extension ContentCard where CustomContent == EmptyView {
    init(
        panelID: UUID,
        title: String,
        content: String,
        onTap: (() -> Void)? = nil,
        actionButtons: [ActionButton]? = nil,
        cardWidth: CGFloat = 250
    ) {
        self.panelID = panelID
        self.title = title
        self.content = content
        self.onTap = onTap
        self.actionButtons = actionButtons
        self.cardWidth = cardWidth
        customContent = nil
    }
}

extension ContentCard {
    static func show(title: String, content: String, onTap: (() -> Void)? = nil, actionButtons: [ActionButton]? = nil, cardWidth: CGFloat = 250, spacingX: CGFloat = 0, spacingY: CGFloat = 0, panelType: PanelType? = nil) {
        OverlayController.shared.showOverlay(content: { panelID in
            ContentCard<EmptyView>(panelID: panelID, title: title, content: content, onTap: onTap, actionButtons: actionButtons, cardWidth: cardWidth)
        }, spacingX: spacingX, spacingY: spacingY, panelType: panelType)
    }

    static func showAboveSelection(title: String, content: String, onTap: (() -> Void)? = nil, actionButtons: [ActionButton]? = nil, cardWidth: CGFloat = 250, spacingX: CGFloat = 0, spacingY: CGFloat = 0, panelType: PanelType? = nil) {
        OverlayController.shared.showOverlayAboveSelection(content: { panelID in
            ContentCard<EmptyView>(panelID: panelID, title: title, content: content, onTap: onTap, actionButtons: actionButtons, cardWidth: cardWidth)
        }, spacingX: spacingX, spacingY: spacingY, panelType: panelType)
    }
}
