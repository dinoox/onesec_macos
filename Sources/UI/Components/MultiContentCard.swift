import AppKit
import SwiftUI

struct ContentItem: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

struct MultiContentCard: View {
    let panelID: UUID
    let title: String
    let items: [ContentItem]
    let cardWidth: CGFloat

    var body: some View {
        VStack {
            Spacer()
            ContentCard(
                panelID: panelID,
                title: title,
                cardWidth: cardWidth,
                showActionBar: false,
                panelType: .translate(.bottom),
            ) {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ContentItemView(
                            panelID: panelID,
                            item: item,
                        )
                    }
                }
            }
        }
        .frame(width: cardWidth)
    }
}

private struct ContentItemView: View {
    let panelID: UUID
    let item: ContentItem

    @State private var isCopied = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(item.title)
                    .font(.system(size: 13.5))
                    .foregroundColor(.overlayText)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(item.content)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(.overlaySecondaryText)
                    .lineSpacing(3.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer()
                    Button(action: handleCopyContent) {
                        HStack(spacing: 4) {
                            Image.systemSymbol(isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .scaleEffect(isCopied ? 1.1 : 1.0)
                                .animation(.quickSpringAnimation, value: isCopied).frame(height: 12)

                            Text("复制").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(HoverIconButtonStyle(normalColor: .overlayPlaceholder, hoverColor: .overlayText))
                    .disabled(isCopied)
                    .opacity(isHovering ? (isCopied ? 0.5 : 1.0) : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                }
            }
        }
        .compatibleHover { hovering in
            isHovering = hovering
        }
    }

    private func handleCopyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content, forType: .string)
        
        withAnimation {
            isCopied = true
        }

        Task { @MainActor in
            try? await sleep(3000)
            withAnimation {
                isCopied = false
            }
        }
    }
}

extension MultiContentCard {
    static func show(title: String, items: [ContentItem], cardWidth: CGFloat = 260, spacingX: CGFloat = 0, spacingY: CGFloat = 0, panelType: PanelType? = nil) {
        OverlayController.shared.showOverlay(content: { panelID in
            MultiContentCard(panelID: panelID, title: title, items: items, cardWidth: cardWidth)
        }, spacingX: spacingX, spacingY: spacingY, panelType: panelType)
    }
}
