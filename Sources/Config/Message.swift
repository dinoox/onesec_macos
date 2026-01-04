//
//  Message.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation

enum MessageType: String, CaseIterable {
    case startRecording = "start_recording"
    case recordingStarted = "recording_started"
    case stopRecording = "stop_recording"
    case cancelRecording = "cancel_recording"
    case recognitionSummary = "recognition_summary"
    case modeUpgrade = "mode_upgrade"
    case configUpdated = "config_updated"
    case authTokenFailed = "auth_token_failed"
    case contextUpdated = "context_update"
    case resourceRequested = "resource_requested"
    case terminalLinuxChoice = "terminal_linux_choice"
    case audioAck = "audio_ack"
    case error

    //
    case hotkeySettingResult = "hotkey_setting_result"
    case hotkeySettingEnd = "hotkey_setting_end"
    case hotkeySettingUpdate = "hotkey_setting_update"
    case hotkeySettingStart = "hotkey_setting_start"
    case userAudioSaved = "user_audio_saved"
    case recordingInterrupted = "recording_interrupted"
    //
    case hotkeyDetectStart = "hotkey_detect_start"
    case hotkeyDetectEnd = "hotkey_detect_end"
    case hotkeyDetectUpdate = "hotkey_detect_update"
    case personaUpdated = "persona_updated"
}

struct WebSocketMessage {
    let id: String
    let type: MessageType
    let timestamp: Int64
    let data: [String: Any]?

    static func create(id: String = UUID().uuidString, type: MessageType, data: [String: Any]? = nil) -> WebSocketMessage {
        WebSocketMessage(
            id: id,
            type: type,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            data: data
        )
    }
}

extension WebSocketMessage {
    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "type": type.rawValue,
            "timestamp": timestamp,
        ]

        if let data {
            json["data"] = data
        }

        return json
    }

    func toJSONString(prettyPrinted: Bool = true) -> String? {
        let options: JSONSerialization.WritingOptions = prettyPrinted ? .prettyPrinted : []

        guard let jsonData = try? JSONSerialization.data(withJSONObject: toJSON(), options: options),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return nil
        }

        return jsonString
    }
}

// MARK: - 通知消息类型

enum NotificationMessageType: Equatable {
    // 服务器响应结果 32s 超时
    case serverTimeout
    // 录音结束前 15s 发出警告
    case recordingTimeoutWarning
    // 用户 Token 失效
    case authTokenFailed
    // 确认录音开启后, 过程中网络中断
    case recordingInterruptedByNetwork

    // 服务不可用
    // 触发时机:
    // 1. 发送 startRecording后, 3s 未收到服务器确认 -> duringRecording = true
    // 2. wss 连接从 .connected 状态变为非已连接状态且当前未在录音过程中 -> duringRecording 值为录音器是否已启动
    case serverUnavailable(duringRecording: Bool)
    // 网络不可用
    // 触发时机:
    // 1. 将要录音时网络不是 available false
    // 2. 将要录音时 wss 连接不是 .connected 状态 -> duringRecording = false
    // 3. 手动断开 wss 连接后, 录音开始后 2s 未连接上服务器 -> duringRecording = false
    // 4. networkState 连接从 .available 变为未连接且当前未在录音过程中 -> duringRecording 值为录音器是否已启动
    case networkUnavailable(duringRecording: Bool)
    // 服务端返回错误  (已在录音过程中则忽略所有错误)
    case error(title: String, content: String, errorCode: String)
    // 网络已恢复
    case wssRestored
    case networkRestored

    var title: String {
        switch self {
        case .serverTimeout:
            "出现了一点问题"
        case .recordingTimeoutWarning:
            "录音即将自动结束"
        case .recordingInterruptedByNetwork:
            "出现了一点问题"
        case .authTokenFailed:
            JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) ? "身份验证失败" : "未登录"
        case .serverUnavailable:
            "服务不可用"
        case .networkUnavailable:
            "网络不可用"
        case .networkRestored:
            "网络已恢复"
        case .wssRestored:
            "连接已恢复"
        case let .error(title, _, _):
            title
        }
    }

    var content: String {
        switch self {
        case .serverTimeout:
            "本次录音未成功转录。你可在历史记录中重新转录"
        case .recordingTimeoutWarning:
            "录音将在15秒后自动停止"
        case .recordingInterruptedByNetwork:
            "本次录音未成功转录。你可在历史记录中重新转录"
        case .authTokenFailed:
            JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) ? "登录状态已失效，请重新登录" : "当前未登录，请登录后使用"
        case .serverUnavailable:
            "服务不可用，请检查网络连接"
        case .networkUnavailable:
            "网络不可用，请检查网络连接"
        case .networkRestored:
            "网络连接已恢复"
        case .wssRestored:
            "连接已恢复"
        case let .error(_, content, _):
            content
        }
    }

    var type: NotificationType {
        switch self {
        case .error,
             .authTokenFailed, .serverUnavailable,
             .networkUnavailable:
            return .error
        case .recordingTimeoutWarning, .recordingInterruptedByNetwork, .serverTimeout:
            return .warning
        case .networkRestored, .wssRestored:
            return .warning
        }
    }

    var shouldAutoHide: Bool {
        switch self {
        case .error, .authTokenFailed, .recordingInterruptedByNetwork, .serverTimeout:
            return false
        case .networkUnavailable,
             .recordingTimeoutWarning, .serverUnavailable, .networkRestored, .wssRestored:
            return true
        }
    }

    var shouldPlaySound: Bool {
        switch self {
        case let .serverUnavailable(duringRecording):
            return duringRecording

        case let .networkUnavailable(duringRecording):
            return !duringRecording

        case .networkRestored, .wssRestored:
            return false

        default:
            return true
        }
    }
}

enum UserDataUpdateType {
    case auth
    case config
    case environment
}

// MARK: - 记录当前激活应用的基本信息

struct AppInfo {
    let appName: String
    let bundleID: String
    let shortVersion: String

    static let empty = AppInfo(
        appName: "",
        bundleID: "",
        shortVersion: ""
    )

    func toJSON() -> [String: Any] {
        [
            "app_name": appName,
            "bundle_id": bundleID,
            "short_version": shortVersion,
        ]
    }
}

// MARK: - 记录当前用户主机信息

struct HostInfo {
    let hostname: String
    let osVersion: String

    static let empty = HostInfo(
        hostname: "",
        osVersion: ""
    )

    func toJSON() -> [String: Any] {
        [
            "hostname": hostname,
            "os_version": osVersion,
        ]
    }
}

// MARK: - 记录当前输入框的上下文信息

struct FocusContext {
    let inputContent: String
    let selectedText: String
    let historyContent: String

    static let empty = FocusContext(
        inputContent: "",
        selectedText: "",
        historyContent: ""
    )

    func toJSON() -> [String: Any] {
        [
            "input_content": inputContent,
            "selected_text": selectedText,
            "history_content": historyContent,
        ]
    }
}

// MARK: - 记录当前焦点元素的详细信息

struct FocusElementInfo {
    let windowTitle: String
    let axRole: String
    let axRoleDescription: String
    let axPlaceholderValue: String
    let axDescription: String

    static let empty = FocusElementInfo(
        windowTitle: "",
        axRole: "",
        axRoleDescription: "",
        axPlaceholderValue: "",
        axDescription: ""
    )

    func toJSON() -> [String: Any] {
        [
            "window_title": windowTitle,
            "ax_role": axRole,
            "ax_role_description": axRoleDescription,
            "ax_placeholder_value": axPlaceholderValue,
            "ax_description": axDescription,
        ]
    }
}

// MARK: - 记录当前录音的应用上下文

struct AppContext {
    let sessionID: String
    let appInfo: AppInfo
    let hostInfo: HostInfo
    let focusContext: FocusContext
    let focusElementInfo: FocusElementInfo

    static let empty = AppContext(
        sessionID: "",
        appInfo: AppInfo.empty,
        hostInfo: HostInfo.empty,
        focusContext: FocusContext.empty,
        focusElementInfo: FocusElementInfo.empty
    )

    func toJSON() -> [String: Any] {
        [
            "session_id": sessionID,
            "app_info": appInfo.toJSON(),
            "host_info": hostInfo.toJSON(),
            "focus_context": focusContext.toJSON(),
            "focus_element_info": focusElementInfo.toJSON(),
        ]
    }
}

//
struct LinuxCommand: Codable {
    let distro: String
    let command: String
    let displayName: String
}
