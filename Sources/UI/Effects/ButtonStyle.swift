import SwiftUI

struct HoverButtonStyle: ButtonStyle {
    let normalColor: Color
    let hoverColor: Color
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isHovered ? hoverColor : normalColor)
            .background(Color.overlayButtonBackground)
            .animation(.quickSpringAnimation, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct UnderlineButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 13.0, *) {
            configuration.label
                .underline(isHovered)
                .animation(.easeInOut, value: isHovered)
                .onHover { isHovered = $0 }
        } else {
            configuration.label
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .offset(y: 6)
                        .opacity(isHovered ? 1 : 0)
                        .animation(.quickSpringAnimation, value: isHovered),
                    alignment: .bottom
                )
                .onHover { isHovered = $0 }
        }
    }
}
