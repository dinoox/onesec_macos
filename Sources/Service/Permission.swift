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
import Foundation

enum PermissionType {
    case accessibility
    case microphone
}

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

@MainActor
final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}
    
    func checkStatus(_ type: PermissionType) -> PermissionStatus {
        switch type {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .microphone:
            return microphoneStatus()
        }
    }
    
    func request(_ type: PermissionType, completion: @escaping (Bool) -> Void) {
        switch type {
        case .accessibility:
            requestAccessibility(completion: completion)
        case .microphone:
            requestMicrophone(completion: completion)
        }
    }
    
    /// 检查并请求所有权限（辅助功能和麦克风）
    func checkAllPermissions(completion: @escaping ([PermissionType: Bool]) -> Void) {
        let group = DispatchGroup()
        let types: [PermissionType] = [.accessibility, .microphone]
        
        var results: [PermissionType: Bool] = [:]
        
        for type in types {
            let status = checkStatus(type)
            log.info("\(type) 权限状态: \(status)")
            
            if status != .granted {
                group.enter()
                request(type) { granted in
                    log.info("\(type) 权限申请结果: \(granted)")
                    results[type] = granted
                    group.leave()
                }
            } else {
                results[type] = true
            }
        }
        
        group.notify(queue: .main) {
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
    
    private func requestMicrophone(completion: @escaping (Bool) -> Void) {
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
        let urlString: String
        switch type {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
