import AppKit
import SwiftUI

struct LinuxCommandCard: View {
    let panelID: UUID
    let commands: [LinuxCommand]

    private var isChoiceMode: Bool {
        commands.count > 1
    }

    var body: some View {
        VStack {
            Spacer()
            ContentCard(
                panelID: panelID,
                title: isChoiceMode ? "选择命令" : "命令处理",
                showActionBar: false
            ) {
                VStack(spacing: 13) {
                    ForEach(commands.indices, id: \.self) { index in
                        CommandItem(
                            panelID: panelID,
                            command: commands[index],
                            isChoiceMode: isChoiceMode
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
    let isChoiceMode: Bool

    @State private var isCopied = false
    @State private var editableCommand: String

    init(panelID: UUID, command: LinuxCommand, isChoiceMode: Bool) {
        self.panelID = panelID
        self.command = command
        self.isChoiceMode = isChoiceMode
        _editableCommand = State(initialValue: command.command)
    }

    private var shouldShowEditor: Bool {
        command.command.newlineCount >= 1
    }

    @State private var text: String =
        """
        struct Member {
            let id = UUID().uuidString
            var name: String
            var team: Team
        }

        enum Team {
            case home, away

            var color: Color {
                switch self {
                case .home: return .red
                case .away: return .blue
                }
            }
        }
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if isChoiceMode {
                HStack {
                    Text(command.displayName + " 系")
                        .font(.system(size: 13.5))
                        .foregroundColor(.overlayText)
                    Spacer()
                }
            }

            VStack(alignment: .trailing, spacing: 10) {
                if shouldShowEditor {
                    CodeEditor(text: $text, theme: .default)
                        .frame(minHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    // CodeEditor(
                    //     text: $editableCommand,
                    //     backgroundColor: NSColor(Color.overlayCodeBackground),
                    //     textColor: NSColor(Color.overlayText),
                    //     fontSize: 14
                    // )
                    // .frame(minHeight: 110)
                    // .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(command.command)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.overlaySecondaryText)
                        .lineSpacing(3.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color.overlayCodeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button(action: handleSelect) {
                    Text(isCopied ? "已插入" : "插入")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.overlayBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(HoverButtonStyle(normalColor: .overlaySecondaryText, hoverColor: .overlayText))
                .disabled(isCopied)
                .opacity(isCopied ? 0.5 : 1.0)
            }
        }
    }

    private func handleSelect() {
        withAnimation {
            isCopied = true
        }

        let panel = OverlayController.shared.getPanel(uuid: panelID)
        guard let panel else { return }
        panel.resignKey()
        OverlayController.shared.hideOverlay(uuid: panelID)

        Task { @MainActor in
            NSApp.deactivate()

            var response: HTTPResponse!
            do {
                if isChoiceMode {
                    let linuxDistro = command.distro
                    response = try await HTTPClient.shared.post(
                        path: "/user/update",
                        body: ["preferred_linux_distro": linuxDistro]
                    )

                    if response.success == true {
                        Tooltip.show(content: "系统偏好已更新")
                    }
                }

                await AXPasteboardController.pasteTextToActiveApp(editableCommand)

            } catch {
                Tooltip.show(content: response.message, type: .error)
            }
        }
    }
}

extension LinuxCommandCard {
    static func show(commands: [LinuxCommand]) {
        let hasMultilineCommand = commands.contains { $0.command.newlineCount >= 1 }

        if hasMultilineCommand {
            showOverlayOnCenter(commands: commands)
        } else {
            OverlayController.shared.showOverlay(content: { panelID in
                LinuxCommandCard(panelID: panelID, commands: commands)
            })
        }
    }

    static func showOverlayOnCenter(commands: [LinuxCommand]) {
        OverlayController.shared.showOverlayOnCenter(content: { panelID in
            LinuxCommandCard(panelID: panelID, commands: commands)
        }, panelType: .editable)
    }
}
