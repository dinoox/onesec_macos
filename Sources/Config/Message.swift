//
//  Message.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation

enum MessageType: String, CaseIterable {
    case startRecording = "start_recording"
    case stopRecording = "stop_recording"
    case recognitionSummary = "recognition_summary"
    case recognitionResult = "recognition_result"
    case serverResult = "server_result" // 新增：服务器返回结果消息
    case hotkeySetting = "hotkey_setting" // 新增：快捷键设置消息（接收）
    case hotkeySettingUpdate = "hotkey_setting_update" // 新增：快捷键设置更新消息（发送）
    case hotkeySettingResult = "hotkey_setting_result" // 新增：快捷键设置结果消息（发送）
    case hotkeySettingEnd = "hotkey_setting_end" // 新增：快捷键设置结束消息（接收）
    case configUpdated = "config_updated" // 新增：初始化配置消息（接收）
    case authTokenFailed = "auth_token_failed" // 新增：认证token失败消息（发送）
    case recordingTimeout = "recording_timeout" // 新增：录音超时消息（发送）
    case connectionSuccess = "connection_success" // 新增：连接成功消息（发送）
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
            "timestamp": timestamp
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
    case custom(title: String, content: String)

    var title: String {
        switch self {
        case .serverTimeout:
            "服务超时"
        case .recordingTimeout:
            "录音超时"
        case .authTokenFailed:
            "鉴权失败"
        case .custom(let title, _):
            title
        }
    }

    var content: String {
        switch self {
        case .serverTimeout:
            "服务器响应超时，请稍后重试"
        case .recordingTimeout:
            "服务器未连接或缺失权限"
        case .authTokenFailed:
            "用户鉴权失败，请返回客户端重新登陆"
        case .custom(_, let content):
            content
        }
    }
}

// MARK: - 记录当前激活应用的基本信息

struct AppInfo {
    let appName: String
    let bundleID: String
    let shortVersion: String

    func toJSON() -> [String: Any] {
        [
            "app_name": appName,
            "bundle_id": bundleID,
            "short_version": shortVersion
        ]
    }
}

// MARK: - 记录当前输入框的上下文信息

struct FocusContext {
    let inputContent: String
    let selectedText: String

    func toJSON() -> [String: Any] {
        [
            "input_content": inputContent,
            "selected_text": selectedText
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

    func toJSON() -> [String: Any] {
        [
            "window_title": windowTitle,
            "ax_role": axRole,
            "ax_role_description": axRoleDescription,
            "ax_placeholder_value": axPlaceholderValue,
            "ax_description": axDescription
        ]
    }
}
