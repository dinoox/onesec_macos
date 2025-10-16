//
//  AudioSinkNodeRecorder.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AVFoundation
import Foundation

enum RecordState {
    case idle
    case recording
    case processing
    case stopping
}

class AudioSinkNodeRecorder {
    private var audioEngine = AVAudioEngine()
    private var sinkNode: AVAudioSinkNode!
    private var converter: AVAudioConverter!
    
    private var recordState: RecordState = .idle
    private var bufferCount = 0
    private var firstBufferTime: Date?
    private var pendingAudioBuffers: [Data] = []
    
    // 录音统计数据
    private var totalPacketsSent = 0
    private var totalBytesSent = 0
    private var recordingStartTime: Date?
    
    // 音频文件调试
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    
    // 识别结果存储
    private var recognitionResults: [String] = []
    private var currentRecognitionText: String = ""
    
    // 目标格式
    private let targetFormat: AVAudioFormat = .init(settings: [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false
    ])!
    
    init() {
        setupSinkNodeAudioEngine()
    }
    
    private func setupSinkNodeAudioEngine() {
        log.info("🚀 设置 AVAudioSinkNode 低延迟录音器...")
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        log.debug("输入格式: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)声道")
        log.debug("目标格式: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount)声道")
        
        guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            log.error("无法创建音频格式转换器")
            return
        }
        audioConverter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        converter = audioConverter
        
        // SinkNode Handle
        sinkNode = AVAudioSinkNode { [weak self] timestamp, frameCount, audioBufferList in
            guard let self, recordState == .recording else { return OSStatus(noErr) }
            processSinkNodeBuffer(audioBufferList, frameCount: frameCount, timestamp: timestamp)
            return OSStatus(noErr)
        }
        
        // 连接音频图
        audioEngine.attach(sinkNode)
        audioEngine.connect(inputNode, to: sinkNode, format: inputFormat)
        
        log.info("✅ AVAudioSinkNode 音频引擎设置完成")
    }
    
    /// 处理SinkNode接收到的音频缓冲区
    private func processSinkNodeBuffer(_ audioBufferList: UnsafePointer<AudioBufferList>,
                                       frameCount: AVAudioFrameCount,
                                       timestamp: UnsafePointer<AudioTimeStamp>)
    {
        // 记录第一个缓冲区时间
        if firstBufferTime == nil {
            firstBufferTime = Date()
        }
        
        bufferCount += 1
        
        // 获取输入格式
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        
        // 创建输入缓冲区
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return
        }
        inputBuffer.frameLength = frameCount
        
        // 复制音频数据 - 从UnsafePointer读取
        let audioBuffer = audioBufferList.pointee.mBuffers
        let bytesToCopy = Int(audioBuffer.mDataByteSize)
        
        // 确保输入缓冲区有有效的数据指针
        guard let inputData = inputBuffer.audioBufferList.pointee.mBuffers.mData,
              let sourceData = audioBuffer.mData
        else {
            log.warning("音频缓冲区数据指针为空")
            return
        }
        
        memcpy(inputData, sourceData, bytesToCopy)
        convertAndSendBuffer(inputBuffer)
    }
    
    /// 转换并发送音频缓冲区
    private func convertAndSendBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        // 计算输出帧数
        let sampleRateRatio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let expectedOutputFrames = AVAudioFrameCount(Double(inputBuffer.frameLength) * sampleRateRatio)
        
        // 创建输出缓冲区 - 只分配需要的容量，避免浪费
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: expectedOutputFrames) else {
            return
        }
        
        // 执行格式转换
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if status == .error {
            log.error("音频格式转换失败: \(error?.localizedDescription ?? "未知错误")")
            return
        }
        
        // 确保输出缓冲区的 frameLength 正确设置
        if outputBuffer.frameLength == 0, expectedOutputFrames > 0 {
            outputBuffer.frameLength = expectedOutputFrames
        }
        
        // 计算音量并发送到UDS
        if recordState == .recording {
            let volume = calculateVolume(from: outputBuffer)
            EventBus.shared.publish(.volumeChange(volume: volume))
        }
        
        // 转换为数据并发送
        let audioData = convertBufferToData(outputBuffer)
        if !audioData.isEmpty {
            if recordState == .recording {
                sendAudioData(audioData)
            } else if recordState == .stopping {
                pendingAudioBuffers.append(audioData)
            }
        }
    }
    
    /// 将音频缓冲区转换为Data
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard buffer.frameLength > 0,
              let audioBuffer = buffer.audioBufferList.pointee.mBuffers.mData
        else {
            return Data()
        }
        
        // 使用实际帧长度计算数据大小，而不是缓冲区总容量
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let actualDataSize = Int(buffer.frameLength) * bytesPerFrame
        
        return Data(bytes: audioBuffer, count: actualDataSize)
    }
    
    /// 发送音频数据
    private func sendAudioData(_ audioData: Data) {
        // 更新统计数据
        totalPacketsSent += 1
        totalBytesSent += audioData.count
        
        EventBus.shared.publish(.onAudioData(data: audioData))
    }
    
    // MARK: -

    func startRecording(appInfo: AppInfo? = nil, focusContext: FocusContext? = nil, focusElementInfo: FocusElementInfo? = nil, recordMode: RecordMode = .normal) {
        guard recordState != .recording else {
            log.warning("录音已在进行中")
            return
        }
        
        log.info("🎙️ 开始SinkNode录音...")
        
        // 重置状态
        bufferCount = 0
        firstBufferTime = nil
        pendingAudioBuffers.removeAll()
        
        // 重置统计数据
        totalPacketsSent = 0
        totalBytesSent = 0
        recordingStartTime = Date()
        
        // 创建调试音频文件（仅在调试模式下）
        if Config.DEBUG_MODE {
            createAudioFile()
        }
        
        // 确保WebSocket连接
//        ConnectionCenter.shared.ensureWebSocketConnection()
        
        recordState = .recording
        EventBus.shared.publish(.startRecording(
            appInfo: appInfo,
            focusContext: focusContext,
            focusElementInfo: focusElementInfo,
            recordMode: recordMode
        ))
        
        do {
            try audioEngine.start()
            log.info("✅ SinkNode录音启动成功")
        } catch {
            log.error("SinkNode录音启动失败: \(error.localizedDescription)")
        }
    }
    
    /// 停止录音
    func stopRecording() {
        guard recordState == .recording else {
            log.warning("录音未在进行中")
            return
        }
        
        log.info("🛑 停止SinkNode录音...")
        recordState = .stopping
        
        // 停止音频引擎
        audioEngine.stop()
        
        // 处理待发送的音频数据
        for audioData in pendingAudioBuffers {
            sendAudioData(audioData)
        }
        pendingAudioBuffers.removeAll()
        EventBus.shared.publish(.stopRecording)
        
        // 计算录音统计信息
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            let avgPacketSize = totalPacketsSent > 0 ? Double(totalBytesSent) / Double(totalPacketsSent) : 0
            let packetsPerSecond = duration > 0 ? Double(totalPacketsSent) / duration : 0
            let bytesPerSecond = duration > 0 ? Double(totalBytesSent) / duration : 0
            
            log.info("📊 录音统计报告:")
            log.info("   📦 总包数: \(totalPacketsSent) 个")
            log.info("   📁 总数据量: \(String(format: "%.2f", Double(totalBytesSent) / 1024.0)) KB (\(totalBytesSent) 字节)")
            log.info("   ⏱️ 录音时长: \(String(format: "%.2f", duration)) 秒")
            log.info("   📊 平均包大小: \(String(format: "%.1f", avgPacketSize)) 字节")
            log.info("   📈 发送频率: \(String(format: "%.1f", packetsPerSecond)) 包/秒")
            log.info("   📈 数据速率: \(String(format: "%.1f", bytesPerSecond / 1024.0)) KB/秒")
            
            // 计算理论数据量对比
            let theoreticalBytes = Int(duration * 16000 * 2) // 16kHz * 2字节/样本
            let efficiency = Double(totalBytesSent) / Double(theoreticalBytes) * 100.0
            log.info("   🎯 数据完整性: \(String(format: "%.1f", efficiency))% (理论: \(String(format: "%.2f", Double(theoreticalBytes) / 1024.0)) KB)")
        }
        
        // 重置状态
        recordState = .idle
        bufferCount = 0
        firstBufferTime = nil
        totalPacketsSent = 0
        totalBytesSent = 0
        recordingStartTime = nil
        
        log.info("✅ SinkNode录音已停止")
    }
    
    /// 获取当前识别结果
    func getCurrentRecognitionText() -> String {
        currentRecognitionText
    }
    
    /// 获取所有识别结果
    func getAllRecognitionResults() -> [String] {
        recognitionResults
    }
    
    // MARK: - 私有辅助方法
    
    /// 创建音频文件
    private func createAudioFile() {
        // 先关闭之前的文件
        audioFile = nil
        
        // 生成文件名（包含毫秒，确保唯一性）
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let fileName = "SinkNode_录音_\(formatter.string(from: Date())).wav"
        
        // 获取用户主目录
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        recordingURL = homeDirectory.appendingPathComponent(fileName)
        
        guard let url = recordingURL else {
            log.error("无法创建录音文件 URL")
            return
        }
        
        // 删除已存在的文件（确保从空白开始）
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        
        // 使用 PCM 格式保存，便于查看位深度信息
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), // PCM 未压缩格式
            AVSampleRateKey: targetFormat.sampleRate, // 16000Hz
            AVNumberOfChannelsKey: targetFormat.channelCount, // 1声道
            AVLinearPCMBitDepthKey: 16, // 16位深度
            AVLinearPCMIsBigEndianKey: false, // 小端序
            AVLinearPCMIsFloatKey: false, // 整数格式
            AVLinearPCMIsNonInterleaved: false // 交错格式
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
            log.debug("录音文件创建成功: \(url.path)")
        } catch {
            log.error("录音文件创建失败: \(error.localizedDescription)")
        }
    }
    
    /// 计算音频缓冲区的音量
    private func calculateVolume(from buffer: AVAudioPCMBuffer) -> Float {
        guard let audioBuffer = buffer.audioBufferList.pointee.mBuffers.mData else {
            return 0.0
        }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let bytesPerSample = Int(buffer.format.streamDescription.pointee.mBytesPerFrame) / channelCount
        
        var sum: Float = 0.0
        
        if bytesPerSample == 2 { // 16-bit
            let samples = audioBuffer.assumingMemoryBound(to: Int16.self)
            for i in 0..<frameCount {
                let sample = Float(samples[i]) / Float(Int16.max)
                sum += sample * sample
            }
        } else if bytesPerSample == 4 { // 32-bit float
            let samples = audioBuffer.assumingMemoryBound(to: Float.self)
            for i in 0..<frameCount {
                sum += samples[i] * samples[i]
            }
        }
        
        let rms = sqrt(sum / Float(frameCount))
        return min(1.0, rms * 10.0) // 放大音量并限制在 0-1 范围内
    }
    
    // MARK: - WebSocketRecognitionDelegate
    
//    func didReceiveMessage(_ summary: String, serverTime: Int?) {
//        log.info("收到识别汇总: \(summary)")
//
//        // 记录服务端耗时
//        if let serverTime {
//            log.info("服务端耗时: \(serverTime)ms")
//        }
//
//        // 将汇总结果也添加到识别结果中
//        if !summary.isEmpty, summary != "未获取到识别结果" {
//            recognitionResults.append(summary)
//            currentRecognitionText = summary
//            log.info("识别汇总已添加到结果列表")
//
//            performTextInputWithResult(summary, serverTime: serverTime)
//
//        } else {
//            log.warning("识别汇总为空或无效")
//            // 即使没有有效结果，也要发送通知到UDS
//            performTextInputWithResult("未获取到识别结果", serverTime: serverTime)
//        }
//    }

}
