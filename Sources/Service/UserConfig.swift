//
//  UserConfig.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/11/20.
//

import Combine
import Foundation

class UserConfigService {
    static let shared = UserConfigService()

    var appBundleId: String = "com.ripplestar.miaoyan"
    var appConfigFileName: String = "config.json"

    private let fileManager = FileManager.default
    private var configDirectory: URL?

    private init() {
        setupConfigDirectory()
    }

    private func setupConfigDirectory() {
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return
        }

        configDirectory = appSupport.appendingPathComponent(appBundleId)

        if let dir = configDirectory, !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private var configFileURL: URL? {
        configDirectory?.appendingPathComponent(appConfigFileName)
    }

    func saveUserConfig(_ config: UserConfig) {
        guard let fileURL = configFileURL else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL)
            log.info("UserConfig saved \(config)")
        }
    }

    func loadUserConfig() -> UserConfig {
        guard let fileURL = configFileURL,
              let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(UserConfig.self, from: data)
        else { return UserConfig() }

        return config
    }

    func saveData(_ data: Any, filename: String) {
        guard let dir = configDirectory else { return }

        let fileURL = dir.appendingPathComponent(filename)

        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? jsonData.write(to: fileURL)
            log.info("Saved \(filename)")
        }
    }
}
