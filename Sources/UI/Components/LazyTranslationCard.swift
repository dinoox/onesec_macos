import AppKit
import SwiftUI

enum ExpandDirection {
    case up
    case down
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
}

struct LazyTranslationCard: View {
    let panelID: UUID
    let title: String
    let content: String

    let onTap: (() -> Void)?
    let actionButtons: [ActionButton]?
    let cardWidth: CGFloat
    let expandDirection: ExpandDirection

    private let autoCloseDuration = 9
    private let compactSize: CGFloat = 25
    private let maxContentHeight: CGFloat = 200

    @State private var isContentCopied = false
    @State private var remainingSeconds = 9
    @State private var timerTask: Task<Void, Never>?
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var isLoading = false
    @State private var translationResult: TranslationResult? = nil
    @State private var errorMessage: String? = nil
    @State private var contentHeight: CGFloat = 0

    init(
        panelID: UUID,
        title: String,
        content: String = "",
        onTap: (() -> Void)? = nil,
        actionButtons: [ActionButton]? = nil,
        cardWidth: CGFloat = 300,
        isCompactMode: Bool = false,
        expandDirection: ExpandDirection = .up,
    ) {
        self.panelID = panelID
        self.title = title
        self.content = content
        self.onTap = onTap
        self.actionButtons = actionButtons
        self.cardWidth = cardWidth
        self.expandDirection = expandDirection
        _isExpanded = State(initialValue: !isCompactMode)
    }

    var body: some View {
        VStack {
            if !isExpanded {
                compactView
                    .transition(.scale(scale: 0.1, anchor: expandDirection == .up ? .bottom : .top).combined(with: .opacity))
            } else {
                cardContent
                    .transition(.scale(scale: 0.1, anchor: expandDirection == .up ? .bottom : .top).combined(with: .opacity))
                    .frame(width: cardWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: expandDirection == .down ? .top : .bottom)
        .animation(.springAnimation, value: isExpanded)
    }

    private var compactView: some View {
        Button(action: {
            withAnimation(.springAnimation) {
                isExpanded = true
            }
            fetchTranslation()
            onTap?()
        }) {
            ZStack {
                Circle()
                    .fill(Color.overlayBackground)
                    .frame(width: compactSize, height: compactSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.overlayBorder, lineWidth: 1.2)
                    )
                    .shadow(color: .overlayBackground.opacity(0.2), radius: 6, x: 0, y: 0)

                Text("译")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.overlayText)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear { startAutoCloseTimer() }
        .onDisappear { stopAutoCloseTimer() }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                // Title Bar
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
                    .buttonStyle(HoverIconButtonStyle(normalColor: .overlayPlaceholder, hoverColor: .overlayText))
                    .opacity(isHovering ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                }

                Rectangle()
                    .fill(Color.overlayBorder.opacity(0.5))
                    .frame(height: 1.4).padding(.horizontal, -13).padding(.bottom, 1)

                // Content
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        HStack {
                            Spinner(color: .overlaySecondaryText, size: 12)
                            Text("翻译中...")
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundColor(.overlaySecondaryText)
                        }
                    } else if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.red)
                            .lineSpacing(3.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    } else if let result = translationResult {
                        ScrollView(.vertical, showsIndicators: contentHeight > maxContentHeight) {
                            Text(result.translatedText)
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundColor(.overlaySecondaryText)
                                .lineSpacing(3.8)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                                    }
                                )
                        }
                        .frame(
                            minHeight: min(max(contentHeight, 1), maxContentHeight),
                            maxHeight: maxContentHeight,
                            alignment: .top
                        )
                        .tryScrollDisabled(contentHeight <= maxContentHeight)
                        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
                        .transition(.opacity)
                    } else {
                        Text(content)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(.overlaySecondaryText)
                            .lineSpacing(3.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .animation(.springAnimation, value: translationResult?.translatedText)

                HStack {
                    Spacer()

                    if let result = translationResult {
                        Button(action: { handleCopyTranslation(text: result.translatedText) }) {
                            HStack(spacing: 4) {
                                Image.systemSymbol(isContentCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .scaleEffect(isContentCopied ? 1.1 : 1.0)
                                    .animation(.quickSpringAnimation, value: isContentCopied).frame(height: 12)

                                Text("复制").font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(HoverIconButtonStyle(normalColor: .overlayPlaceholder, hoverColor: .overlayText))
                        .disabled(isContentCopied)
                        .opacity(isHovering ? (isContentCopied ? 0.5 : 1.0) : 0.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)

            // Bottom Timer Tip
            VStack(spacing: 0) {
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
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .onAppear {
            startAutoCloseTimer()
            fetchTranslation()
        }
        .onDisappear { stopAutoCloseTimer() }
    }

    private func closeCard() {
        stopAutoCloseTimer()
        OverlayController.shared.hideOverlay(uuid: panelID)
    }

    private func handleCopyContent() {
        guard !content.isEmpty else { return }

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

    private func fetchTranslation() {
        guard !isLoading, translationResult == nil else { return }

        guard !content.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let response = try await HTTPClient.shared.post(
                    path: "/translate/translate",
                    body: ["text": content]
                )

                guard response.success == true, let data = response.data else {
                    errorMessage = response.message
                    isLoading = false
                    return
                }

                translationResult = TranslationResult(
                    originalText: data["original_text"] as? String ?? "",
                    translatedText: data["translated_text"] as? String ?? "",
                    sourceLanguage: data["source_language"] as? String ?? "",
                    targetLanguage: data["target_language"] as? String ?? ""
                )
                isLoading = false
            } catch {
                errorMessage = "翻译失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func handleCopyTranslation(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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
}

extension LazyTranslationCard {
    static func showAboveSelection(title: String, content: String, onTap: (() -> Void)? = nil, actionButtons: [ActionButton]? = nil, cardWidth: CGFloat = 250, spacingX: CGFloat = 0, spacingY: CGFloat = 0, isCompactMode: Bool = false, expandDirection: ExpandDirection = .down) {
        OverlayController.shared.showOverlayAboveSelection(content: { panelID in
            LazyTranslationCard(panelID: panelID, title: title, content: content, onTap: onTap, actionButtons: actionButtons, cardWidth: cardWidth, isCompactMode: isCompactMode, expandDirection: expandDirection)
        }, spacingX: spacingX, spacingY: spacingY)
    }
}
