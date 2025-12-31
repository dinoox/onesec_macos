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

    var isFirstLaunch: Bool {
        guard let dir = configDirectory else { return true }
        let launchedFile = dir.appendingPathComponent(".launched")
        return !fileManager.fileExists(atPath: launchedFile.path)
    }

    func saveUserConfig(_ config: UserConfig) {
        guard let fileURL = configFileURL else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL)
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

    var audiosDirectory: URL? {
        guard let dir = configDirectory else { return nil }
        let audiosDir = dir.appendingPathComponent("audios")
        if !fileManager.fileExists(atPath: audiosDir.path) {
            try? fileManager.createDirectory(at: audiosDir, withIntermediateDirectories: true)
        }
        return audiosDir
    }

    var databaseDirectory: URL? {
        guard let dir = configDirectory else { return nil }
        let dbDir = dir.appendingPathComponent("db.sqlite3")
        return dbDir
    }

    func loadData(filename: String) -> [String: Any]? {
        guard let dir = configDirectory else { return nil }
        let fileURL = dir.appendingPathComponent(filename)
        
        guard let jsonData = try? Data(contentsOf: fileURL),
              let data = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        return data
    }
}
