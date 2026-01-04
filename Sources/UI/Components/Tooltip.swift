import SwiftUI

enum TooltipType {
    case primary
    case error
    case plain
}

struct Tooltip: View {
    let content: String
    let customContent: AnyView?
    let panelID: UUID
    let type: TooltipType
    let showBell: Bool
    let customIcon: NSImage?
    let onTap: (() -> Void)?

    init(panelID: UUID, content: String = "", customContent: AnyView? = nil, type: TooltipType = .primary, showBell: Bool = true, customIcon: NSImage? = nil, onTap: (() -> Void)? = nil) {
        self.panelID = panelID
        self.content = content
        self.customContent = customContent
        self.type = type
        self.showBell = showBell
        self.customIcon = customIcon
        self.onTap = onTap
    }

    private var backgroundColor: Color {
        switch type {
        case .primary:
            return Color.overlayBackground
        case .error:
            return Color.overlaySecondaryBackground
        case .plain:
            return Color.overlayBackground
        }
    }

    private var textColor: Color {
        switch type {
        case .primary:
            return .overlaySecondaryPrimary
        case .error:
            return .black
        case .plain:
            return Color.overlayText
        }
    }

    private var borderColor: Color {
        switch type {
        case .primary:
            return Color.overlayBorder.opacity(0.5)
        case .error:
            return Color.overlayBorder.opacity(0.8)
        case .plain:
            return Color.overlayBorder.opacity(0.8)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let nsImage = customIcon {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(textColor)
                    .frame(width: 12, height: 12)
            } else if showBell {
                Image.systemSymbol("bell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textColor)
            }
            if let custom = customContent {
                custom
            } else {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.overlaySecondaryBackground.opacity(0.2), radius: 6, x: 0, y: 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                OverlayController.shared.hideOverlay(uuid: panelID)
            }
        }
    }
}

extension Tooltip {
    static func show(content: String = "", customContent: AnyView? = nil, type: TooltipType = .primary, showBell: Bool = true, customIcon: NSImage? = nil, onTap: (() -> Void)? = nil) {
        OverlayController.shared.showOverlay { panelID in
            Tooltip(panelID: panelID, content: content, customContent: customContent, type: type, showBell: showBell, customIcon: customIcon, onTap: onTap)
        }
    }
}
