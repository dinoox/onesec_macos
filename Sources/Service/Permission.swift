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
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

final class PermissionManager: ObservableObject, @unchecked Sendable {
    static let shared = PermissionManager()
    
    @Published var microphonePermissionStatus: PermissionStatus = .notDetermined
    @Published var accessibilityPermissionStatus: PermissionStatus = .notDetermined
    @Published var permissionStatusList: [PermissionType: PermissionStatus] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    
    private init() {
        checkAllPermissions { [weak self] results in
            log.info("Permission status: \(results)")
            self?.startMonitoring()
        }
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
    
    /// 启动时检查并申请所有权限
    func checkAllPermissions(completion: @escaping ([PermissionType: PermissionStatus]) -> Void) {
        // 首先更新所有权限的初始状态
        updateAllPermissionStatus()
        
        var results: [PermissionType: PermissionStatus] = [:]
        let group = DispatchGroup()
        
        // 麦克风
        group.enter()
        request(.microphone) { [weak self] granted in
            guard let self else {
                group.leave()
                return
            }
            let status = granted ? PermissionStatus.granted : checkStatus(.microphone)
            DispatchQueue.main.async {
                self.microphonePermissionStatus = status
                results[.microphone] = status
                group.leave()
            }
        }
        
        // 辅助功能
        group.enter()
        request(.accessibility) { [weak self] granted in
            guard let self else {
                group.leave()
                return
            }
            let status = granted ? PermissionStatus.granted : checkStatus(.accessibility)
            DispatchQueue.main.async {
                self.accessibilityPermissionStatus = status
                results[.accessibility] = status
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.permissionStatusList = results
            completion(results)
        }
    }
    
    func requestAccessibility(completion: @escaping (Bool) -> Void) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !trusted {
            openSystemPreferences(for: .accessibility)
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
        DispatchQueue.main.async {
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
        
        // 监听应用激活事件，当应用重新激活时检查权限
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAllPermissionStatus()
        }
    }
    
    /// 更新所有权限状态
    func updateAllPermissionStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let newMicStatus = checkStatus(.microphone)
            let newAccessStatus = checkStatus(.accessibility)
            
            if microphonePermissionStatus != newMicStatus {
                microphonePermissionStatus = newMicStatus
            }
            
            if accessibilityPermissionStatus != newAccessStatus {
                accessibilityPermissionStatus = newAccessStatus
            }
            
            permissionStatusList = [
                .microphone: newMicStatus,
                .accessibility: newAccessStatus
            ]
        }
    }
    
    deinit {
        timer?.invalidate()
        cancellables.removeAll()
    }
}
