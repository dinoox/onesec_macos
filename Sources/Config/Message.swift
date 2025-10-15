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
    case realtimeResult = "realtime_result"
    case finalSentence = "final_sentence"
    case recognitionSummary = "recognition_summary"
    case connection
    case volumeData = "volume_data"
    case recognitionResult = "recognition_result"
    case permissionStatus = "permission_status" // 新增：权限状态消息
    case modeUpgrade = "mode_upgrade" // 新增：模式升级消息
    case ping // 新增：ping 消息
    case pong // 新增：pong 消息
    case serverResult = "server_result" // 新增：服务器返回结果消息
    case hotkeySetting = "hotkey_setting" // 新增：快捷键设置消息（接收）
    case hotkeySettingUpdate = "hotkey_setting_update" // 新增：快捷键设置更新消息（发送）
    case hotkeySettingResult = "hotkey_setting_result" // 新增：快捷键设置结果消息（发送）
    case hotkeySettingEnd = "hotkey_setting_end" // 新增：快捷键设置结束消息（接收）
    case initConfig = "init_config" // 新增：初始化配置消息（接收）
    case screenChange = "screen_change" // 新增：屏幕切换消息（发送）
    case authTokenFailed = "auth_token_failed" // 新增：认证token失败消息（发送）
    case recordingTimeout = "recording_timeout" // 新增：录音超时消息（发送）
    case connectionSuccess = "connection_success" // 新增：连接成功消息（发送）
}

struct WebSocketMessage {
    let type: MessageType
    let timestamp: Int64
    let data: [String: Any]?

    static func create(type: MessageType, data: [String: Any]? = nil) -> WebSocketMessage {
        return WebSocketMessage(
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

        if let data = data {
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

// MARK: - 记录当前激活应用的基本信息

struct AppInfo {
    let appName: String
    let bundleID: String
    let shortVersion: String

    func toJSON() -> [String: Any] {
        return [
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
        return [
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
        return [
            "window_title": windowTitle,
            "ax_role": axRole,
            "ax_role_description": axRoleDescription,
            "ax_placeholder_value": axPlaceholderValue,
            "ax_description": axDescription
        ]
    }
}
