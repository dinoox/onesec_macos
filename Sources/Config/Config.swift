//
//  Config.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import AppKit
import Combine
import Foundation

class Config: ObservableObject {
    static let shared = Config()

    @Published var UDS_CHANNEL: String = ""
    @Published var SERVER: String = ""

    @Published var TEXT_PROCESS_MODE: TextProcessMode = .auto
    @Published var USER_CONFIG = UserConfigService.shared.loadUserConfig() {
        didSet {
            log.info("Theme changed: \(oldValue.theme) -> \(USER_CONFIG.theme)")
            if oldValue.theme != USER_CONFIG.theme {
                applyTheme()
            }
        }
    }

    private init() {
        applyTheme()
    }

    private func applyTheme() {
        Task { @MainActor in
            switch self.USER_CONFIG.theme {
            case "dark":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            case "light":
                NSApp.appearance = NSAppearance(named: .aqua)
            default:
                NSApp.appearance = nil // 跟随系统
            }
        }
    }

    func saveHotkeySetting(mode: RecordMode, hotkeyCombination: [String]) {
        let modeString = mode == .normal ? "normal" : "command"

        if let index = USER_CONFIG.hotkeyConfigs.firstIndex(where: { $0.mode == modeString }) {
            USER_CONFIG.hotkeyConfigs[index] = UserConfig.HotkeyConfig(mode: modeString, hotkeyCombination: hotkeyCombination)
        } else {
            USER_CONFIG.hotkeyConfigs.append(UserConfig.HotkeyConfig(mode: modeString, hotkeyCombination: hotkeyCombination))
        }
        UserConfigService.shared.saveUserConfig(USER_CONFIG)
        log.info("Hotkey updated for mode: \(mode), combination: \(hotkeyCombination)")
    }

    func setLastSyncFocusJudgmentSheetTime(_ date: Date) {
        USER_CONFIG.lastSyncFocusJudgmentSheetTime = date.timeIntervalSince1970
        UserConfigService.shared.saveUserConfig(USER_CONFIG)
    }

    func isReleaseMode() -> Bool {
        return SERVER.contains { $0.isLetter }
    }
}

enum TextProcessMode: String, CaseIterable {
    case auto = "AUTO"
    case translate = "TRANSLATE"
    case format = "FORMAT"
    case terminal = "TERMINAL"

    var displayName: String {
        switch self {
        case .auto:
            "自动风格"
        case .translate:
            "翻译风格"
        case .format:
            "整理风格"
        case .terminal:
            "终端风格"
        }
    }

    var description: String {
        switch self {
        case .auto:
            "智能判断, 一键省心"
        case .translate:
            "翻译文本, 一键省心"
        case .format:
            "结构重组, 深度优化"
        case .terminal:
            "终端风格, 一键省心"
        }
    }
}

struct UserConfig: Codable {
    var theme: String
    let environment: Environment
    var lastSyncFocusJudgmentSheetTime: Double
    let setting: Setting
    var authToken: String
    let user: User
    var hotkeyConfigs: [HotkeyConfig]

    var lastSyncTime: Date? {
        return lastSyncFocusJudgmentSheetTime > 0 ? Date(timeIntervalSince1970: lastSyncFocusJudgmentSheetTime) : nil
    }

    init() {
        theme = "light"
        environment = Environment()
        lastSyncFocusJudgmentSheetTime = 0
        setting = Setting()
        authToken = ""
        user = User()
        hotkeyConfigs = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "light"
        environment = try container.decodeIfPresent(Environment.self, forKey: .environment) ?? Environment()
        lastSyncFocusJudgmentSheetTime = try container.decodeIfPresent(Double.self, forKey: .lastSyncFocusJudgmentSheetTime) ?? 0
        setting = try container.decodeIfPresent(Setting.self, forKey: .setting) ?? Setting()
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        user = try container.decodeIfPresent(User.self, forKey: .user) ?? User()
        hotkeyConfigs = try container.decodeIfPresent([HotkeyConfig].self, forKey: .hotkeyConfigs) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case theme
        case environment
        case lastSyncFocusJudgmentSheetTime
        case setting
        case authToken = "auth_token"
        case user
        case hotkeyConfigs = "hotkey_configs"
    }

    var normalKeyCodes: [Int64] {
        for config in hotkeyConfigs {
            if config.mode == "normal" {
                let keyString = config.hotkeyCombination.joined(separator: "+")
                return KeyMapper.parseKeyString(keyString) ?? [63]
            }
        }
        return [63]
    }

    var commandKeyCodes: [Int64] {
        for config in hotkeyConfigs {
            if config.mode == "command" {
                let keyString = config.hotkeyCombination.joined(separator: "+")
                return KeyMapper.parseKeyString(keyString) ?? [63, 55]
            }
        }
        return [63, 55]
    }

    struct Environment: Codable {
        let preferredSystem: String
        let hostSystems: [String: String]

        init() {
            preferredSystem = "debian"
            hostSystems = [:]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            preferredSystem = try container.decodeIfPresent(String.self, forKey: .preferredSystem) ?? "debian"
            hostSystems = try container.decodeIfPresent([String: String].self, forKey: .hostSystems) ?? [:]
        }

        enum CodingKeys: String, CodingKey {
            case preferredSystem = "preferred_system"
            case hostSystems = "host_systems"
        }
    }

    struct Setting: Codable {
        let showComparison: Bool
        let hideFloatingPanel: Bool

        init() {
            showComparison = false
            hideFloatingPanel = false
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            showComparison = try container.decodeIfPresent(Bool.self, forKey: .showComparison) ?? false
            hideFloatingPanel = try container.decodeIfPresent(Bool.self, forKey: .hideFloatingPanel) ?? false
        }

        enum CodingKeys: String, CodingKey {
            case showComparison = "show_comparison"
            case hideFloatingPanel = "hide_floating_panel"
        }
    }

    struct User: Codable {
        let phone: String
        let preferredLinuxDistro: String
        let createdAt: Int
        let userId: Int
        let userName: String
        let invitationCodeUsed: String
        let isActive: Bool

        init() {
            phone = ""
            preferredLinuxDistro = "debian"
            createdAt = 0
            userId = 0
            userName = ""
            invitationCodeUsed = ""
            isActive = true
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
            preferredLinuxDistro = try container.decodeIfPresent(String.self, forKey: .preferredLinuxDistro) ?? "debian"
            createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt) ?? 0
            userId = try container.decodeIfPresent(Int.self, forKey: .userId) ?? 0
            userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? ""
            invitationCodeUsed = try container.decodeIfPresent(String.self, forKey: .invitationCodeUsed) ?? ""
            isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        }

        enum CodingKeys: String, CodingKey {
            case phone
            case preferredLinuxDistro = "preferred_linux_distro"
            case createdAt = "created_at"
            case userId = "user_id"
            case userName = "user_name"
            case invitationCodeUsed = "invitation_code_used"
            case isActive = "is_active"
        }
    }

    struct HotkeyConfig: Codable {
        let mode: String
        let hotkeyCombination: [String]

        init() {
            mode = ""
            hotkeyCombination = []
        }

        init(mode: String, hotkeyCombination: [String]) {
            self.mode = mode
            self.hotkeyCombination = hotkeyCombination
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
            hotkeyCombination = try container.decodeIfPresent([String].self, forKey: .hotkeyCombination) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case mode
            case hotkeyCombination = "hotkey_combination"
        }
    }
}
