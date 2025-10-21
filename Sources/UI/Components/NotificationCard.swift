import SwiftUI

struct NotificationState {
    var isVisible: Bool = false
    var opacity: Double = 0
    var title: String = ""
    var content: String = ""
}

struct NotificationCard: View {
    let title: String
    let content: String
    let modeColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Image.systemSymbol("bell.fill")
                    .font(.system(size: 18))
                    .foregroundColor(modeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // 内容
                Text(content)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1),
                ),
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 0)
    }
}
