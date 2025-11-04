import AppKit
import SwiftUI

struct ContentCard: View {
    let panelId: UUID
    let title: String
    let content: String
    let onTap: (() -> Void)? = nil

    private let cardWidth: CGFloat = 240
    private let autoCloseDuration = 12
    private let maxContentHeight: CGFloat = 600

    // Hover 状态
    @State private var isCloseHovered = false
    @State private var isCopyButtonHovered = false
    @State private var isStopButtonHovered = false
    @State private var isCollapseHovered = false

    // 内容状态
    @State private var isContentCopied = false
    @State private var isContentCollapsed = false
    @State private var showBottomSection = true
    @State private var contentHeight: CGFloat = 0

    // 定时器状态
    @State private var remainingSeconds = 12
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            cardContent
        }
        .frame(width: cardWidth)
        .animation(.spring(response: 0.4, dampingFraction: 0.825), value: showBottomSection)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题栏
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.overlayText)
                        .lineLimit(1)

                    Spacer()

                    Button(action: toggleContentCollapse) {
                        Image.systemSymbol("chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isCollapseHovered ? .overlayText : .overlaySecondaryText)
                            .rotationEffect(.degrees(isContentCollapsed ? 180 : 0))
                            .animation(.spring, value: isContentCollapsed)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCollapseHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isCollapseHovered = hovering
                    }

                    Button(action: closeCard) {
                        Image.systemSymbol("xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.trailing, 2)
                            .foregroundColor(isCloseHovered ? .overlayText : .overlaySecondaryText)
                            .animation(.easeInOut(duration: 0.3), value: isCloseHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isCloseHovered = hovering
                    }
                }

                if !isContentCollapsed {
                    ScrollView(.vertical, showsIndicators: contentHeight > maxContentHeight) {
                        Text(content)
                            .font(.system(size: 12.5, weight: .regular))
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
                    .disabled(contentHeight <= maxContentHeight)

                    HStack {
                        Spacer()
                        Button(action: handleCopyContent) {
                            Image.systemSymbol(isContentCopied ? "checkmark" : "document.on.document")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isContentCopied ? .overlayDisabled : (isCopyButtonHovered ? .overlayText : .overlaySecondaryText))
                                .scaleEffect(isContentCopied ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isContentCopied)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopyButtonHovered)
                        }
                        .frame(width: 16, height: 16)
                        .buttonStyle(.plain)
                        .disabled(isContentCopied)
                        .onHover { hovering in
                            isCopyButtonHovered = hovering
                        }
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)

            // 底部提示条
            if showBottomSection {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("这条消息将在 ")
                            .font(.system(size: 10))
                            .foregroundColor(Color.overlaySecondaryText)

                        Text("\(remainingSeconds)")
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(Color.overlaySecondaryText)

                        Text(" 秒后自动关闭，")
                            .font(.system(size: 10))
                            .foregroundColor(Color.overlaySecondaryText)

                        Button(action: closeTipsSection) {
                            Text("点击停止")
                                .font(.system(size: 10))
                                .foregroundColor(Color.overlayText)
                                .underline(isStopButtonHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isStopButtonHovered = hovering
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 13)
                    .background(Color.overlaySecondaryBackground)

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
        }
        .background(Color.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.overlayBorder, lineWidth: 1.2)
        )
        .shadow(color: .overlayBackground.opacity(0.3), radius: 6, x: 0, y: 0)
        .onTapGesture { onTap?() }
        .onAppear { startAutoCloseTimer() }
        .onDisappear { stopAutoCloseTimer() }
    }

    private func closeCard() {
        stopAutoCloseTimer()
        OverlayController.shared.hideOverlay(uuid: panelId)
    }

    private func closeTipsSection() {
        stopAutoCloseTimer()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            showBottomSection = false
        }
    }

    private func toggleContentCollapse() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.825)) {
            isContentCollapsed.toggle()
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
            for second in (0 ... autoCloseDuration).reversed() {
                guard !Task.isCancelled else { return }
                remainingSeconds = second
                if second == 0 {
                    closeCard()
                    return
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
