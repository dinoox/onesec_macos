//
//  Command.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import ArgumentParser

struct CommandParser: ParsableCommand {
    @Option(name: .shortAndLong, help: "")
    var udsChannel: String = "/tmp/com.ripplestars.miaoyan.uds.test"

    @Option(name: .shortAndLong, help: "服务器主机地址")
    var server = "114.55.98.75:8000" // 114.55.98.75:8000 staging-api.miaoyan.cn

    @Option(name: .shortAndLong, help: "设置鉴权 Token")
    var authToken: String

    @Option(name: .shortAndLong, help: "设置 Debug 模式")
    var debugMode: Bool = true

    mutating func run() throws {
        Config.UDS_CHANNEL = udsChannel
        Config.SERVER = server
        Config.AUTH_TOKEN = authToken
        Config.DEBUG_MODE = debugMode
    }
}
