//
//  AudioSinkNodeRecorder.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AVFoundation
import Collections
import Combine
import Foundation
import Opus

enum RecordState {
    case idle
    case recording
    case processing
    case stopping
}

class AudioSinkNodeRecorder: @unchecked Sendable {
    private var audioEngine = AVAudioEngine()
    private var sinkNode: AVAudioSinkNode!
    private var converter: AVAudioConverter!
    private var opusEncoder: OpusEncoder?
    private var oggPacketizer: OpusOggStreamPacketizer?

    private let opusFrameSamples = 160 // 10ms @ 16kHz
    private var opusFramesPerPacket = 20 // 默认聚合 200ms

    private var audioQueue: Deque<Data> = .init()
    private var recordState: RecordState = .idle

    // 响应式流处理
    private var cancellables = Set<AnyCancellable>()
    private var queueStartTime: Date?
    private var isRecordingStarted = false
    private var recordingInfo:
        (
            appInfo: AppInfo?, focusContext: FocusContext?, focusElementInfo: FocusElementInfo?,
            recordMode: RecordMode
        )?

    // 录音统计数据
    private var totalPacketsSent = 0
    private var totalBytesSent = 0 // Opus 压缩后的数据
    private var totalRawBytesSent = 0 // 原始 PCM 数据
    private var recordingStartTime: Date?

    // 目标音频格式
    private let targetFormat: AVAudioFormat = .init(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: true)!

    private var frameDurationMilliseconds: Double {
        (Double(opusFrameSamples) / targetFormat.sampleRate) * 1000.0
    }

    init() {
        setupAudioEngine()
        setupAudioEventListener()
        setupOpusEncoder()
    }

    private func setupOpusEncoder() {
        opusEncoder = OpusEncoder(
            format: targetFormat,
            application: .voip,
            frameSize: AVAudioFrameCount(opusFrameSamples))
        rebuildOggPacketizer()
    }

    private func rebuildOggPacketizer() {
        oggPacketizer = OpusOggStreamPacketizer(
            sampleRate: Int(targetFormat.sampleRate),
            channelCount: Int(targetFormat.channelCount),
            opusFrameSamples: opusFrameSamples,
            framesPerPacket: opusFramesPerPacket)
    }

    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        log.debug("输入格式: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)声道")
        log.debug("目标格式: \(targetFormat.sampleRate)Hz \(targetFormat.channelCount)声道")

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            log.error("Create AVAudioConverter err")
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

        log.info("✅ SinkNode 音频引擎设置完成")
    }

    /// 处理 SinkNode 接收到的音频缓冲区
    private func processSinkNodeBuffer(
        _ audioBufferList: UnsafePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount,
        timestamp _: UnsafePointer<AudioTimeStamp>,
    ) {
        // 创建输入缓冲区
        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount)
        else {
            return
        }

        inputBuffer.frameLength = frameCount

        // 复制音频流数据
        let audioBuffer = audioBufferList.pointee.mBuffers
        let bytesToCopy = Int(audioBuffer.mDataByteSize)

        // 确保数据流有效
        guard let inputData = inputBuffer.audioBufferList.pointee.mBuffers.mData,
              let sourceData = audioBuffer.mData
        else {
            log.error("null input buffer pointer")
            return
        }

        memcpy(inputData, sourceData, bytesToCopy)
        convertAndSendBuffer(inputBuffer)
    }

    /// 转换并发送音频缓冲区
    private func convertAndSendBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        // 计算输出的帧数
        let conversionRatio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let expectedOutputFrames = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * conversionRatio)

        // 创建输出缓冲区
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: expectedOutputFrames)
        else {
            return
        }

        outputBuffer.frameLength = expectedOutputFrames

        // 音频流格式转换
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if status == .error {
            log.error("音频格式转换失败: \(error!.localizedDescription)")
            return
        }

        // 计算音量
        let volume = calculateVolume(from: outputBuffer)
        EventBus.shared.publish(.volumeChanged(volume: volume))

        // 使用 Opus 编码
        if let encoder = opusEncoder {
            let encodedFrames = encoder.encodeBuffer(outputBuffer)
            totalRawBytesSent +=
                Int(outputBuffer.frameLength)
                * Int(outputBuffer.format.streamDescription.pointee.mBytesPerFrame)

            guard !encodedFrames.isEmpty else {
                handleQueuedAudio()
                return
            }

            for opusFrame in encodedFrames {
                enqueueEncodedFrame(opusFrame)
            }
        } else {
            // 降级使用原始 PCM
            log.warning("Opus encoder 初始化失败,使用原始 PCM")
            let pcmData = convertBufferToData(outputBuffer)
            audioQueue.append(pcmData)
            totalRawBytesSent += pcmData.count
        }

        handleQueuedAudio()
    }

    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard buffer.frameLength > 0,
              let audioBuffer = buffer.audioBufferList.pointee.mBuffers.mData
        else {
            return Data()
        }

        // 使用实际帧长度计算数据大小，而不是缓冲区总容量
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let realDataCount = Int(buffer.frameLength) * bytesPerFrame

        return Data(bytes: audioBuffer, count: realDataCount)
    }

    private func enqueueEncodedFrame(_ opusFrame: Data) {
        guard let packetizer = oggPacketizer else {
            audioQueue.append(opusFrame)
            return
        }

        for packet in packetizer.append(frame: opusFrame) {
            audioQueue.append(packet)
        }
    }

    private func flushPendingOggPackets(final: Bool) {
        guard let packetizer = oggPacketizer else { return }
        for packet in packetizer.flush(final: final) {
            audioQueue.append(packet)
        }
    }

    private func sendAudioData(_ audioData: Data) {
        totalPacketsSent += 1
        totalBytesSent += audioData.count

        EventBus.shared.publish(.audioDataReceived(data: audioData))
    }

    // MARK: - 录音处理

    func configureOpusFramesPerPacket(_ count: Int) {
        guard count > 0 else {
            log.error("framesPerPacket must be positive")
            return
        }

        if recordState == .recording {
            log.warning("Updating frames per packet while recording; pending Ogg buffers will reset.")
        }

        opusFramesPerPacket = count
        rebuildOggPacketizer()
    }

    func configureOpusPacketDuration(milliseconds: Int) {
        guard milliseconds > 0 else {
            log.error("packet duration must be positive")
            return
        }

        let frames = max(1, Int(ceil(Double(milliseconds) / frameDurationMilliseconds)))
        configureOpusFramesPerPacket(frames)
    }

    func startRecording(
        appInfo: AppInfo? = nil, focusContext: FocusContext? = nil,
        focusElementInfo: FocusElementInfo? = nil, recordMode: RecordMode = .normal,
    ) {
        guard recordState == .idle else {
            log.warning("Cant Start recording, now state: \(recordState)")
            return
        }

        resetState()

        // 保存录音信息，等待可以录音时再发送
        recordingInfo = (appInfo, focusContext, focusElementInfo, recordMode)
        recordState = .recording

        do {
            try audioEngine.start()
        } catch {
            log.error("🙅 AudioEngine error: \(error.localizedDescription)")
        }

        log.info("🎙️ Start Recording")
    }

    func stopRecording() {
        guard recordState == .recording else {
            return
        }

        recordState = .stopping
        audioEngine.stop()

        // 刷新 Opus 编码器缓冲区, 发送所有剩余数据
        if let encoder = opusEncoder, let finalData = encoder.flush() {
            enqueueEncodedFrame(finalData)
            log.info("📦 Opus encoder flushed final frame: \(finalData.count) bytes")
        }

        flushPendingOggPackets(final: true)

        while let audioData = audioQueue.popFirst() {
            sendAudioData(audioData)
        }

        if isRecordingStarted {
            EventBus.shared.publish(.recordingStopped)
        }

        // 计算录音统计信息
        if recordingStartTime != nil {
            printRecordingStatistics()
        }

        recordState = .processing
        log.info("✅ Stop Recording")
    }

    func resetState() {
        // 重置状态
        recordState = .idle
        audioQueue.removeAll()

        // 重置统计数据
        totalPacketsSent = 0
        totalBytesSent = 0
        totalRawBytesSent = 0
        recordingStartTime = Date()

        // 重置响应式流状态
        isRecordingStarted = false
        recordingInfo = nil
        queueStartTime = nil

        // 重置 Opus 编码器缓冲区
        opusEncoder?.reset()
        rebuildOggPacketizer()
    }

    /// 计算音频缓冲区的音量 限制在 0-1 范围内
    private func calculateVolume(from buffer: AVAudioPCMBuffer) -> Float {
        guard let audioBuffer = buffer.audioBufferList.pointee.mBuffers.mData else {
            return 0.0
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let bytesPerSample =
            Int(buffer.format.streamDescription.pointee.mBytesPerFrame) / channelCount

        var sum: Float = 0.0

        if bytesPerSample == 2 { // 16-bit
            let samples = audioBuffer.assumingMemoryBound(to: Int16.self)
            for i in 0..<frameCount {
                let sample = Float(samples[i]) / Float(Int16.max)
                sum += sample * sample
            }
        } else if bytesPerSample == 4 { // 32-bit
            let samples = audioBuffer.assumingMemoryBound(to: Float.self)
            for i in 0..<frameCount {
                sum += samples[i] * samples[i]
            }
        }

        let rms = sqrt(sum / Float(frameCount))
        return min(1.0, rms * 10.0)
    }
}

// MARK: - 响应式音频流处理

// 使用 Deque 双向队列
// 处理连接不稳定或无连接情况

extension AudioSinkNodeRecorder {
    private func setupAudioEventListener() {
        ConnectionCenter.shared.$wssState
            .combineLatest(ConnectionCenter.shared.$permissionsState)
            .sink { [weak self] _, _ in
                self?.handleConnectionStateChange()
            }
            .store(in: &cancellables)

        EventBus.shared.events
            .sink { [weak self] event in
                switch event {
                case .serverResultReceived,
                     .notificationReceived(.serverTimeout),
                     .notificationReceived(.recordingTimeout): self?.recordState = .idle

                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func handleQueuedAudio() {
        guard recordState == .recording else { return }
        guard ConnectionCenter.shared.canRecord() else {
            checkAndHandleTimeout()
            return
        }

        // 连接可用
        processAudioQueue()
    }

    // TODO: 优化线程安全
    private func handleConnectionStateChange() {
        guard recordState == .recording, ConnectionCenter.shared.canRecord() else {
            return
        }

        queueStartTime = nil
        processAudioQueue()
    }

    private func processAudioQueue() {
        // 首次启动发送录音开始事件
        startRecordingIfNeeded()

        // 发送积压音频数据
        flushAudioQueue()
    }

    private func flushAudioQueue() {
        while let audioData = audioQueue.popFirst() {
            sendAudioData(audioData)
        }
    }

    private func startRecordingIfNeeded() {
        guard !isRecordingStarted, let info = recordingInfo else { return }

        isRecordingStarted = true
        EventBus.shared.publish(
            .recordingStarted(
                appInfo: info.appInfo,
                focusContext: info.focusContext,
                focusElementInfo: info.focusElementInfo,
                recordMode: info.recordMode))
    }

    private func checkAndHandleTimeout() {
        if queueStartTime == nil {
            queueStartTime = Date()
        } else if let startTime = queueStartTime, Date().timeIntervalSince(startTime) >= 2.0 {
            log.error("Audio queue timeout: failed to establish connection within 2 seconds.")
            stopRecording()
            EventBus.shared.publish(.notificationReceived(.recordingTimeout))
        }
    }
}

extension AudioSinkNodeRecorder {
    private func printRecordingStatistics() {
        guard let startTime = recordingStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return }

        let avgPacketSize =
            totalPacketsSent > 0 ? Double(totalBytesSent) / Double(totalPacketsSent) : 0
        let packetsPerSecond = Double(totalPacketsSent) / duration
        let bytesPerSecond = Double(totalBytesSent) / duration

        let theoreticalBytes = Int(duration * 16000 * 2) // 16kHz * 2字节/样本

        // 计算压缩相关统计
        let compressionRatio =
            totalRawBytesSent > 0 ? Double(totalRawBytesSent) / Double(totalBytesSent) : 1.0
        let compressionPercentage =
            totalRawBytesSent > 0
                ? (1.0 - Double(totalBytesSent) / Double(totalRawBytesSent)) * 100.0 : 0.0
        let bandwidthSaved = totalRawBytesSent - totalBytesSent

        log.info(
            """
            📊 录音统计报告:
               📦 总包数目: \(totalPacketsSent) 个
               🤡 录音时长: \(String(format: "%.2f", duration)) 秒

               💾 原始数据: \(formatBytes(totalRawBytesSent))
               📦 压缩数据: \(formatBytes(totalBytesSent))
               🤡 压缩比例: \(String(format: "%.1f", compressionRatio)):1
               💰 压缩率: \(String(format: "%.1f", compressionPercentage))%
               🤡 节省带宽: \(formatBytes(bandwidthSaved))

               📊 平均包大小: \(String(format: "%.1f", avgPacketSize)) 字节
               📈 发送频率: \(String(format: "%.1f", packetsPerSecond)) 包/秒
               📈 数据速率: \(String(format: "%.1f", bytesPerSecond / 1024.0)) KB/秒
               🎯 理论数据: \(formatBytes(theoreticalBytes)) (\(String(format: "%.1f", Double(totalRawBytesSent) / Double(theoreticalBytes) * 100.0))%)
            """)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        return String(format: "%.2f KB (%d 字节)", kb, bytes)
    }
}
