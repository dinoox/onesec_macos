//
//  Command.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import ArgumentParser

struct CommandParser: ParsableCommand {
    @Option(name: .shortAndLong, help: "UDS服务器地址")
    var udsChannel: String = "/tmp/com.ripplestars.miaoyan.uds.test"

    @Option(name: .shortAndLong, help: "服务器主机地址")
    var server = "114.55.98.75:443" // 114.55.98.75:8000 staging-api.miaoyan.cn 192.168.50.171:8000

    @Option(name: .shortAndLong, help: "设置鉴权 Token")
    var authToken: String

    @Option(name: .shortAndLong, help: "设置 Debug 模式")
    var debugMode: Bool = true

    @Option(name: .shortAndLong, help: "普通模式按键组合 (如: Fn)")
    var normalKeys: String = "Fn+LOpt"

    @Option(name: .shortAndLong, help: "命令模式按键组合 (如: Fn+Space, Fn+LCmd)")
    var commandKeys: String = "Fn+LCmd"

    mutating func run() throws {
        guard ServerValidator.isValid(server) else {
            throw ValidationError("Invalid Server: \(server)")
        }

        Config.shared.UDS_CHANNEL = udsChannel
        Config.shared.SERVER = server
        Config.shared.AUTH_TOKEN = authToken
        Config.shared.DEBUG_MODE = debugMode
        Config.shared.NORMAL_KEY_CODES = try parseKeys(normalKeys, name: "普通模式按键")
        Config.shared.COMMAND_KEY_CODES = try parseKeys(commandKeys, name: "命令模式按键")

        log.info("Hotkey inited with normal: \(normalKeys), command: \(commandKeys)")
    }

    private func parseKeys(_ keyString: String, name: String) throws -> [Int64] {
        guard let codes = KeyMapper.parseKeyString(keyString) else {
            throw ValidationError("Invalid \(name) Config: \(keyString)")
        }
        return codes
    }
}
