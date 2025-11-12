import AppKit
import SwiftUI

struct LinuxCommandChoiceCard: View {
    let panelID: UUID
    let commands: [LinuxCommand]
    let bundleID: String
    let appName: String
    let endpointIdentifier: String

    var body: some View {
        VStack {
            Spacer()
            ContentCard(
                panelID: panelID,
                title: "选择命令"
            ) {
                VStack(spacing: 13) {
                    ForEach(commands.indices, id: \.self) { index in
                        CommandItem(
                            command: commands[index],
                            panelID: panelID,
                            bundleID: bundleID,
                            appName: appName,
                            endpointIdentifier: endpointIdentifier
                        )
                    }
                }
            }
        }
        .frame(width: 300)
    }
}

struct CommandItem: View {
    let command: LinuxCommand
    let panelID: UUID
    let bundleID: String
    let appName: String
    let endpointIdentifier: String

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(command.displayName + " 系")
                    .font(.system(size: 12))
                    .foregroundColor(.overlayText)
                Spacer()
            }

            Text(command.command)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.overlaySecondaryText)
                .lineSpacing(3.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color.overlayCodeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Button(action: handleSelect) {
                Text(isCopied ? "已选择" : "选择")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.overlayBorder, lineWidth: 1)
                    )
            }
            .padding(.top, 2)
            .buttonStyle(HoverButtonStyle(normalColor: .overlaySecondaryText, hoverColor: .overlayText))
            .disabled(isCopied)
            .opacity(isCopied ? 0.5 : 1.0)
        }
    }

    private func handleSelect() {
        //     let pasteboard = NSPasteboard.general
        //     pasteboard.clearContents()
        //     pasteboard.setString(command.command, forType: .string)

        withAnimation {
            isCopied = true
        }

        OverlayController.shared.hideOverlay(uuid: panelID)

        Task { @MainActor in
            var response: HTTPResponse!
            do {
                let linuxDistro = command.distro
                response = try await HTTPClient.shared.post(
                    path: "/user/update",
                    body: ["preferred_linux_distro": linuxDistro]
                )

                if response.success == true {
                    Tooltip.show(content: "系统偏好已更新")
                }

                await AXPasteboardController.pasteTextToActiveApp(command.command
                    .formattedCommand)

            } catch {
                Tooltip.show(content: response.message, type: .error)
            }
        }
    }
}

extension LinuxCommandChoiceCard {
    static func show(commands: [LinuxCommand], bundleID: String, appName: String, endpointIdentifier: String) {
        OverlayController.shared.showOverlay { panelID in
            LinuxCommandChoiceCard(panelID: panelID, commands: commands, bundleID: bundleID, appName: appName, endpointIdentifier: endpointIdentifier)
        }
    }
}
