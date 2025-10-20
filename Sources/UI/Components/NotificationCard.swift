import SwiftUI

struct NotificationCard: View {
    let title: String
    let content: String
    let iconColor: Color
    let showCloseButton: Bool
    let onClose: (() -> Void)?
    
    init(
        title: String,
        content: String,
        iconColor: Color,
        showCloseButton: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.content = content
        self.iconColor = iconColor
        self.showCloseButton = showCloseButton
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Image.systemSymbol("bell.fill")
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // 标题
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // 内容
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
                
                // 为关闭按钮预留空间
                if showCloseButton {
                    Color.clear
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 0)
            
            // 关闭按钮
            if showCloseButton {
                Button(action: {
                    onClose?()
                }) {
                    Image.systemSymbol("xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
        }
    }
}

