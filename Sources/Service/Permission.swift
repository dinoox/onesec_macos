//
//  Permission.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import Cocoa
import Combine
import Foundation

enum PermissionType {
    case accessibility
    case microphone
    // case screenRecording
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

final class PermissionService: ObservableObject, @unchecked Sendable {
    static let shared = PermissionService()

    @Published var microphonePermissionStatus: PermissionStatus = .notDetermined
    @Published var accessibilityPermissionStatus: PermissionStatus = .notDetermined
    @Published var permissionsState: [PermissionType: PermissionStatus] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    private init() {
        checkAllPermissions { [weak self] in
            self?.startMonitoring()
        }
    }

    func checkAllPermissions(completion: @escaping @Sendable () -> Void) {
        flushPermissionStatus()

        if microphonePermissionStatus == .notDetermined {
            log.info("Microphone permission not determined...")
            // requestMicrophone { _ in }
        }
        if accessibilityPermissionStatus == .denied {
            log.info("Accessibility permission denied...")
            // requestAccessibility { _ in }
        }

        completion()
    }

    func checkStatus(_ type: PermissionType) -> PermissionStatus {
        switch type {
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        case .microphone:
            microphoneStatus()
        }
    }

    func request(_ type: PermissionType, completion: @escaping @Sendable (Bool) -> Void) {
        switch type {
        case .accessibility:
            requestAccessibility(completion: completion)
        case .microphone:
            requestMicrophone(completion: completion)
        }
    }

    func requestAccessibility(completion: @escaping (Bool) -> Void) {
        let trusted: Bool

        if #available(macOS 11.0, *) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: false] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        if !trusted {
            showAccessibilityPermissionAlert()
        }

        completion(trusted)
    }

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private func requestMicrophone(completion: @escaping @Sendable (Bool) -> Void) {
        switch microphoneStatus() {
        case .granted:
            completion(true)
        case .denied:
            showMicrophonePermissionAlert()
            completion(false)
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    private func showMicrophonePermissionAlert() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要麦克风权限"
            alert.informativeText = "秒言需要访问您的麦克风来进行语音识别。请在系统偏好设置中允许麦克风权限。"
            alert.addButton(withTitle: "打开系统偏好设置")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openSystemPreferences(for: .microphone)
            }
        }
    }

    func showAccessibilityPermissionAlert() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "秒言需要辅助功能权限来获取输入上下文。请在系统偏好设置中允许辅助功能权限。"
            alert.addButton(withTitle: "打开系统偏好设置")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openSystemPreferences(for: .accessibility)
            }
        }
    }

    private func openSystemPreferences(for type: PermissionType) {
        let urlString = switch type {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 权限状态管理

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateAllPermissionStatus()
        }

        // 监听应用激活事件
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAllPermissionStatus()
        }
    }

    func updateAllPermissionStatus() {
        Task { @MainActor in
            flushPermissionStatus()
        }
    }

    private func flushPermissionStatus() {
        let newMicStatus = checkStatus(.microphone)
        let newAccessStatus = checkStatus(.accessibility)
        var hasChanges = false

        if microphonePermissionStatus != newMicStatus {
            microphonePermissionStatus = newMicStatus
            hasChanges = true
        }

        if accessibilityPermissionStatus != newAccessStatus {
            accessibilityPermissionStatus = newAccessStatus
            hasChanges = true
        }

        if hasChanges {
            permissionsState = [
                .microphone: newMicStatus,
                .accessibility: newAccessStatus,
            ]
        }
    }

    deinit {
        timer?.invalidate()
        cancellables.removeAll()
    }
}
