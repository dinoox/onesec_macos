import SwiftUI

struct Tooltip: View {
    let text: String
    let panelID: UUID
    let onTap: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 6) {
            Image.systemSymbol("bell")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.overlayPrimary),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderGrey.opacity(0.8), lineWidth: 1),
        )
        .shadow(color: Color.overlaySecondaryBackground.opacity(0.2), radius: 6, x: 0, y: 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                OverlayController.shared.hideOverlay(uuid: panelID)
            }
        }
    }
}
