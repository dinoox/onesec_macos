//
//  SyncScheduler.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/11/20.
//

import Combine
import Foundation

/**
 * 同步调度器
 * 当前负责同步焦点判断表的白名单和黑名单
 */
class SyncScheduler {
    static let shared = SyncScheduler()

    private var scheduler: NSBackgroundActivityScheduler?
    private let syncInterval: TimeInterval = 24 * 60 * 60 // 24 小时
    private var cancellables = Set<AnyCancellable>()

    private init() {
        EventBus.shared.events
            .sink { [weak self] event in
                if case .userDataUpdated(.auth) = event {
                    self?.performSync()
                    self?.scheduleNextSync()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        loadLocalConfigs()

        guard let lastSyncTime: Date = Config.shared.USER_CONFIG.lastSyncTime else {
            log.info("First launch, no last sync time found, immediately execute sync task")
            performSync()
            scheduleNextSync()
            return
        }

        let nextSyncTime = lastSyncTime.addingTimeInterval(syncInterval)
        let now = Date()

        if now >= nextSyncTime {
            performSync()
            scheduleNextSync()
        } else {
            let timeUntilNextSync = nextSyncTime.timeIntervalSince(now)
            log.info("Next sync time: \(nextSyncTime)")
            scheduleNextSync(after: timeUntilNextSync)
        }
    }

    private func scheduleNextSync(after interval: TimeInterval? = nil) {
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.ripplestar.miaoyan.sync")

        let delayInterval = interval ?? syncInterval
        scheduler.interval = delayInterval
        scheduler.tolerance = 60 * 5 // 容差 5 分钟
        scheduler.repeats = false

        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }

            log.info("Execute scheduled sync task")
            self.performSync()
            self.scheduleNextSync()
            completion(.finished)
        }

        self.scheduler = scheduler
        log.info("Scheduled next sync task, interval: \(delayInterval.rounded()) seconds")
    }

    private func loadLocalConfigs() {
        if let whitelistData = UserConfigService.shared.loadData(filename: "zero_width_char_whitelisted_apps.json"),

           let apps = whitelistData["apps"] as? [[String: Any]]
        {
            let bundleIds = apps.compactMap { $0["bundle_id"] as? String }
            appShouldTestWithZeroWidthChar = Set(bundleIds)
            log.info("Loaded zero width char whitelist: \(bundleIds.count) apps")
        }

        if let blacklistData = UserConfigService.shared.loadData(filename: "ax_blacklisted_apps.json"),
           let apps = blacklistData["apps"] as? [[String: Any]]
        {
            let bundleIds = apps.compactMap { $0["bundle_id"] as? String }
            appsWithoutAXSupport = Set(bundleIds)
            log.info("Loaded AX blacklist: \(bundleIds.count) apps")
        }
    }

    private func performSync() {
        Task {
            guard JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) else {
                return
            }
            await syncAppLists()
        }
    }

    private func syncAppLists() async {
        do {
            // 同步 零宽字符 白名单
            let whitelistResponse = try await HTTPClient.shared.post(
                path: "/context/whitelisted-apps",
                body: [:]
            )

            if let data = whitelistResponse.dataDict {
                UserConfigService.shared.saveData(data, filename: "zero_width_char_whitelisted_apps.json")

                if let apps = data["apps"] as? [[String: Any]] {
                    let bundleIds = apps.compactMap { $0["bundle_id"] as? String }
                    appShouldTestWithZeroWidthChar = Set(bundleIds)
                }
            }

            // 同步 AX 黑名单
            let blacklistResponse = try await HTTPClient.shared.post(
                path: "/context/blacklisted-apps",
                body: [:]
            )

            if let data = blacklistResponse.dataDict {
                UserConfigService.shared.saveData(data, filename: "ax_blacklisted_apps.json")

                if let apps = data["apps"] as? [[String: Any]] {
                    let bundleIds = apps.compactMap { $0["bundle_id"] as? String }
                    appsWithoutAXSupport = Set(bundleIds)
                }
            }

            Config.shared.setLastSyncFocusJudgmentSheetTime(Date())
            log.info("Sync completed, updated last sync time")

        } catch {
            log.error("Sync failed: \(error)")
        }
    }
}
