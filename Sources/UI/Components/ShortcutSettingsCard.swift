import AppKit
import Combine
import SwiftUI

struct ShortcutSettingsState {
    var isVisible: Bool = false
    var opacity: Double = 0
}

struct KeyCapView: View {
    let keyName: String

    var body: some View {
        Text(KeyMapper.getDisplayText(for: keyName))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.keyText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.keyBackground)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

struct ShortcutInputField: View {
    let mode: RecordMode
    @Binding var keyCodes: [Int64]
    @Binding var currentEditingMode: RecordMode?
    @Binding var conflictError: String?
    @State private var cancellables = Set<AnyCancellable>()

    var isEditing: Bool {
        currentEditingMode == mode
    }

    var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }

    var sortedKeyCodes: [Int64] {
        KeyMapper.sortKeyCodes(keyCodes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if keyCodes.isEmpty {
                    Text("点击设置")
                        .font(.system(size: 11))
                        .foregroundColor(.overlayPlaceholder)
                } else {
                    ForEach(Array(sortedKeyCodes.enumerated()), id: \.offset) { index, keyCode in
                        KeyCapView(keyName: KeyMapper.keyCodeToString(keyCode))

                        if index < sortedKeyCodes.count - 1 {
                            Text("+")
                                .font(.system(size: 10))
                                .foregroundColor(.overlayPlaceholder)
                        }
                    }
                }

                Spacer()

                if isEditing {
                    Text("等待捷键")
                        .font(.system(size: 10))
                        .foregroundColor(modeColor.opacity(0.8))
                }
            }
            .frame(height: 24)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEditing ? modeColor.opacity(0.15) : Color.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isEditing ? modeColor.opacity(0.3) : Color.inputBorder,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && !isEditing {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                guard !isEditing else { return }
                conflictError = nil
                startEditing()
            }
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .onAppear {
                setupEventListeners()
            }

            if let error = conflictError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(destructiveRed)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
    }

    private func startEditing() {
        currentEditingMode = mode
        EventBus.shared.publish(.hotkeySettingStarted(mode: mode))
    }

    private func setupEventListeners() {
        EventBus.shared.events.receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case let .hotkeySettingUpdated(eventMode, combination):
                    guard eventMode == mode else { return }
                    let codes = combination.compactMap { KeyMapper.stringToKeyCodeMap[$0] }
                    keyCodes = codes

                case let .hotkeySettingResulted(eventMode, _, _):
                    guard eventMode == mode else { return }
                    currentEditingMode = nil

                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}

struct ShortcutSettingsCard: View {
    let onClose: () -> Void
    @State private var normalKeyCodes: [Int64] = []
    @State private var commandKeyCodes: [Int64] = []
    @State private var currentEditingMode: RecordMode? = nil
    @State private var normalConflictError: String? = nil
    @State private var commandConflictError: String? = nil
    @State private var cancellables = Set<AnyCancellable>()

    @State private var isCloseHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("快捷键设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.overlayText)

                Spacer()

                Button(action: onClose) {
                    Image.systemSymbol("xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isCloseHovered ? .overlayText : .overlaySecondaryText)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: isCloseHovered)
                .onHover { hovering in
                    isCloseHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("普通模式")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.overlaySecondaryText)

                    ShortcutInputField(
                        mode: .normal,
                        keyCodes: $normalKeyCodes,
                        currentEditingMode: $currentEditingMode,
                        conflictError: $normalConflictError
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("命令模式")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.overlaySecondaryText)

                    ShortcutInputField(
                        mode: .command,
                        keyCodes: $commandKeyCodes,
                        currentEditingMode: $currentEditingMode,
                        conflictError: $commandConflictError
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.overlayBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    currentEditingMode != nil
                        ? (currentEditingMode == .normal ? auroraGreen : starlightYellow).opacity(
                            0.3)
                        : Color.overlayBorder,
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 2)
        .offset(y: (normalConflictError != nil || commandConflictError != nil) ? -10 : 0)
        .animation(.easeInOut(duration: 0.2), value: currentEditingMode)
        .animation(.easeInOut(duration: 0.3), value: normalConflictError)
        .animation(.easeInOut(duration: 0.3), value: commandConflictError)
        .contentShape(Rectangle())
        .onTapGesture {
            cancelEditing()
        }
        .onAppear {
            normalKeyCodes = Config.shared.NORMAL_KEY_CODES
            commandKeyCodes = Config.shared.COMMAND_KEY_CODES

            EventBus.shared.events
                .receive(on: DispatchQueue.main)
                .sink { [self] event in
                    if case let .hotkeySettingResulted(mode, combination, isConflict) =
                        event
                    {
                        handleHotkeySettingResulted(
                            mode: mode, combination: combination, isConflict: isConflict
                        )
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func cancelEditing() {
        if let mode = currentEditingMode {
            let originalCodes = mode == .normal ? Config.shared.NORMAL_KEY_CODES : Config.shared.COMMAND_KEY_CODES
            let combination = originalCodes.map { KeyMapper.keyCodeToString($0) }
            EventBus.shared.publish(
                .hotkeySettingResulted(mode: mode, hotkeyCombination: combination))
            currentEditingMode = nil
        }
    }

    private func handleHotkeySettingResulted(
        mode: RecordMode, combination: [String], isConflict: Bool
    ) {
        let newKeyCodes = KeyMapper.sortKeyCodes(
            combination.compactMap { KeyMapper.stringToKeyCodeMap[$0] })

        if isConflict {
            let originalCodes = mode == .normal ? Config.shared.NORMAL_KEY_CODES : Config.shared.COMMAND_KEY_CODES

            if mode == .normal {
                normalKeyCodes = originalCodes
                normalConflictError = "与命令模式快捷键冲突"
            } else {
                commandKeyCodes = originalCodes
                commandConflictError = "与普通模式快捷键冲突"
            }

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if mode == .normal {
                    normalConflictError = nil
                } else {
                    commandConflictError = nil
                }
            }
        } else {
            if mode == .normal {
                normalKeyCodes = newKeyCodes
                normalConflictError = nil
            } else {
                commandKeyCodes = newKeyCodes
                commandConflictError = nil
            }
        }
    }
}
