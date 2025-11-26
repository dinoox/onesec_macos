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
    case recognitionSummary = "recognition_summary"
    case modeUpgrade = "mode_upgrade"
    case configUpdated = "config_updated"
    case authTokenFailed = "auth_token_failed"
    case hotkeySettingResult = "hotkey_setting_result"
    case contextUpdated = "context_update"
    case resourceRequested = "resource_requested"
    case terminalLinuxChoice = "terminal_linux_choice"
}

struct WebSocketMessage {
    let type: MessageType
    let timestamp: Int64
    let data: [String: Any]?

    static func create(type: MessageType, data: [String: Any]? = nil) -> WebSocketMessage {
        WebSocketMessage(
            type: type,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            data: data
        )
    }
}

extension WebSocketMessage {
    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
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
    case serverTimeout
    case recordingTimeout
    case authTokenFailed
    case serverUnavailable
    case networkUnavailable
    case custom(title: String, content: String)

    var title: String {
        switch self {
        case .serverTimeout:
            "服务超时"
        case .recordingTimeout:
            "录音超时"
        case .authTokenFailed:
            JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) ? "鉴权失败" : "未登录"
        case .serverUnavailable:
            "服务不可用"
        case .networkUnavailable:
            "网络不可用"
        case let .custom(title, _):
            title
        }
    }

    var content: String {
        switch self {
        case .serverTimeout:
            "服务器响应超时，请稍后重试"
        case .recordingTimeout:
            "服务器录音响应超时"
        case .authTokenFailed:
            JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) ? "用户鉴权失败，请返回客户端重新登陆" : "用户未登录，请登陆后使用"
        case .serverUnavailable:
            "服务不可用，请检查网络连接"
        case .networkUnavailable:
            "网络不可用，请检查网络连接"
        case let .custom(_, content):
            content
        }
    }
}

enum UserDataUpdateType {
    case auth
    case config
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
    let appInfo: AppInfo
    let hostInfo: HostInfo
    let focusContext: FocusContext
    let focusElementInfo: FocusElementInfo

    static let empty = AppContext(
        appInfo: AppInfo.empty,
        hostInfo: HostInfo.empty,
        focusContext: FocusContext.empty,
        focusElementInfo: FocusElementInfo.empty
    )

    func toJSON() -> [String: Any] {
        [
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
