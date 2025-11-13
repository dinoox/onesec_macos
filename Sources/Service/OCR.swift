//
//  OCR.swift
//  OnesecCore
//
//  Created by AI Assistant on 2025/10/27.
//

import Cocoa
import CoreGraphics
@preconcurrency import Vision

// MARK: - 识别结果

struct RecognizedText {
    let text: String
    let boundingBox: CGRect // 归一化坐标 (0.0-1.0)
}

// MARK: - OCR服务

class OCRService {
    /// 截取前台窗口并识别文字
    static func captureFrontWindowAndRecognize() async -> [RecognizedText] {
        guard let windowImage = captureFrontWindow() else {
            log.error("无法截取前台窗口")
            return []
        }

        return await recognizeText(from: windowImage)
    }

    /// 获取前台窗口的纯文本内容
    static func captureFrontWindowText() async -> String {
        let results = await captureFrontWindowAndRecognize()
        return results.map(\.text).joined(separator: "\n")
    }

    /// 获取前台窗口的截图
    static func captureFrontWindow() -> CGImage? {
        let permissionService = PermissionService.shared
        let screenStatus = permissionService.checkStatus(.screenRecording)
        if screenStatus != .granted {
            Task { @MainActor in
                OverlayController.shared.showOverlay { panelId in
                    NotificationCard(
                        title: "未获得屏幕录制权限",
                        content: "请在系统偏好设置中允许屏幕录制权限",
                        panelId: panelId,
                        modeColor: starlightYellow,
                        autoHide: true,
                        onTap: {
                            PermissionService.shared.request(.screenRecording) { _ in }
                        },
                        onClose: nil
                    )
                }
            }
            EventBus.shared.publish(.serverResultReceived(summary: "", interactionID: "", processMode: .auto, polishedText: ""))
            return nil
        }

        guard let winList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let frontApp = NSWorkspace.shared.frontmostApplication
        else {
            return nil
        }

        let frontPID = frontApp.processIdentifier
        let frontAppName = frontApp.localizedName ?? "Unknown"

        // 查找前台应用的主窗口（Layer = 0）
        for window in winList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  pid == frontPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 100, height > 100
            else {
                continue
            }

            let rect = CGRect(x: x, y: y, width: width, height: height)

            guard let image = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else {
                continue
            }

            log.info("📸 Screen capture: \(frontAppName) (\(Int(width))×\(Int(height)))")
            saveImageToFile(image, appName: frontAppName)
            return image
        }

        // 回退到全屏截图
        guard let fullScreenImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            log.error("Screen capture failed, please check the screen recording permission")
            return nil
        }

        saveImageToFile(fullScreenImage, appName: "FullScreen")
        return fullScreenImage
    }

    /// 保存图片到本地
    private static func saveImageToFile(_ cgImage: CGImage, appName: String) {
        // 创建保存目录
        let documentsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let screenshotsFolder = documentsPath.appendingPathComponent("OnesecScreenshots")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: screenshotsFolder, withIntermediateDirectories: true)

        // 生成文件名（使用时间戳和应用名）
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedAppName = appName.replacingOccurrences(of: " ", with: "_")
        let fileName = "screenshot_\(sanitizedAppName)_\(timestamp).png"
        let fileURL = screenshotsFolder.appendingPathComponent(fileName)

        // 将 CGImage 转换为 NSBitmapImageRep 并保存为 PNG
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            log.error("无法将图片转换为PNG格式")
            return
        }

        do {
            try pngData.write(to: fileURL)
            log.info("✅ 截图已保存到: \(fileURL.path)")
        } catch {
            log.error("保存截图失败: \(error.localizedDescription)")
        }
    }

    /// 从图像识别文字
    private static func recognizeText(from image: CGImage) async -> [RecognizedText] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    log.error("RecognizeText failed: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results = observations.compactMap { observation -> RecognizedText? in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    return RecognizedText(text: candidate.string, boundingBox: observation.boundingBox)
                }

                log.info("Recognize \(results.count) texts")
                continuation.resume(returning: results)
            }

            // 配置识别参数
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            // 执行识别
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    log.error("OCR请求执行失败: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

private extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}
