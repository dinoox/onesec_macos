//
//  AudioUnitRecorder.swift
//  OnesecCore
//
//  Created by 王晓雨 Wang on 2025/12/11.
//

import AudioToolbox
import AVFoundation
import Collections
import Combine
import Foundation
import Opus

/// 基于 Audio Unit 的录音器
/// 避免 AVAudioEngine 的聚合设备问题
class AudioUnitRecorder: @unchecked Sendable {
    @Published var recordState: RecordState = .idle

    // Audio Unit 组件

    private var audioUnit: AudioUnit?
    private var converter: AudioConverterRef?
    private var opusEncoder: OpusEncoder!
    private var oggPacketizer: OpusOggStreamPacketizer!

    // 音频格式

    private let targetFormat = AudioStreamBasicDescription(
        mSampleRate: 16000.0, // 采样率 16kHz
        mFormatID: kAudioFormatLinearPCM, // 音频格式ID
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, // 格式标志
        mBytesPerPacket: 2, // 每数据包的字节数
        mFramesPerPacket: 1, // 每数据包的帧数
        mBytesPerFrame: 2, // 每帧的字节数
        mChannelsPerFrame: 1, // 每帧的字节数
        mBitsPerChannel: 16, // 每个声道的位数
        mReserved: 0 // 保留字段
    )

    private var inputFormat = AudioStreamBasicDescription()

    // MARK: - 录音配置

    private let opusFrameSamples = 160 // 10ms @ 16kHz
    private var opusFramesPerPacket = 20 // 默认聚合 200ms

    private var audioQueue: Deque<Data> = .init()
    private var recordedAudioData = Data()
    private var cancellables = Set<AnyCancellable>()
    private var queueStartTime: Date?
    private var isRecordingStarted = false
    private var recordMode: RecordMode = .normal

    // MARK: - 录音统计数据

    private var totalPacketsSent = 0
    private var totalBytesSent = 0
    private var totalRawBytesSent = 0
    private var recordingStartTime: Date?

    // MARK: - 录音时长限制

    private let maxRecordingDuration: TimeInterval = 180
    private let warningBeforeTimeout: TimeInterval = 15
    private var recordingLimitTimer: Timer?

    // MARK: - 线程安全

    private let lock = NSLock()

    // MARK: - 初始化

    init() {
        setupOpusEncoderAndPacketizer()
        setupAudioEventListener()
    }

    deinit {
        cleanup()
    }

    // MARK: - Setup Methods

    private func setupOpusEncoderAndPacketizer() {
        let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000.0,
            channels: 1,
            interleaved: true
        )!

        opusEncoder = OpusEncoder(
            format: avFormat,
            application: .voip,
            frameSize: AVAudioFrameCount(opusFrameSamples)
        )

        oggPacketizer = OpusOggStreamPacketizer(
            sampleRate: Int(targetFormat.mSampleRate),
            channelCount: Int(targetFormat.mChannelsPerFrame),
            opusFrameSamples: opusFrameSamples,
            framesPerPacket: opusFramesPerPacket
        )

        guard opusEncoder != nil else {
            log.error("Unexpected OpusEncoder Init")
            return
        }
    }

    private func setupAudioUnit() throws {
        lock.lock()
        defer { lock.unlock() }

        // 1. 获取 HAL Output Audio Unit 组件描述
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw NSError(domain: "AudioUnit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to find audio component"])
        }

        // 2. 创建 Audio Unit 实例
        var audioUnitInstance: AudioUnit?
        var status = AudioComponentInstanceNew(component, &audioUnitInstance)
        guard status == noErr, let unit = audioUnitInstance else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create audio unit: \(status)"])
        }

        audioUnit = unit

        // 3. 启用输入，禁用输出
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // 输入总线
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to enable input: \(status)"])
        }

        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // 输出总线
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to disable output: \(status)"])
        }

        // 4. 设置输入设备
        let targetDeviceID = AudioDeviceManager.shared.selectedDeviceID ?? AudioDeviceManager.shared.defaultInputDeviceID
        var deviceID = targetDeviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set device: \(status)"])
        }

        log.info("✅ 已设置输入设备: \(deviceID)")

        // 5. 获取输入设备的格式
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &inputFormat,
            &propertySize
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to get input format: \(status)"])
        }

        log.debug("输入格式: \(inputFormat.mSampleRate)Hz \(inputFormat.mChannelsPerFrame)声道")

        // 6. 设置输出侧格式（AudioUnit 输出 = 我们的输入数据）
        var outputFormat = inputFormat // 先使用输入格式
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1, // 输入总线的输出侧
            &outputFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set output format: \(status)"])
        }

        // 7. 设置输入回调
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set callback: \(status)"])
        }

        // 8. 创建格式转换器
        try setupAudioConverter()

        // 9. 初始化 Audio Unit
        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize audio unit: \(status)"])
        }

        log.info("✅ Audio Unit 初始化完成")
    }

    private func setupAudioConverter() throws {
        guard inputFormat.mSampleRate > 0 else {
            throw NSError(domain: "AudioUnit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid input format"])
        }

        var inputFormatCopy = inputFormat
        var targetFormatCopy = targetFormat

        let status = AudioConverterNew(&inputFormatCopy, &targetFormatCopy, &converter)
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter: \(status)"])
        }

        // 设置转换质量
        var quality = kAudioConverterQuality_High
        AudioConverterSetProperty(
            converter!,
            kAudioConverterSampleRateConverterQuality,
            UInt32(MemoryLayout<UInt32>.size),
            &quality
        )

        log.debug("✅ 音频转换器已创建: \(inputFormat.mSampleRate)Hz -> \(targetFormat.mSampleRate)Hz")
    }

    // MARK: - Audio Callback

    private let audioInputCallback: AURenderCallback = {
        inRefCon,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            _
            -> OSStatus in
        let recorder = Unmanaged<AudioUnitRecorder>.fromOpaque(inRefCon).takeUnretainedValue()

        guard recorder.recordState == .recording else {
            return noErr
        }

        // 准备输入缓冲区列表
        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = UInt32(recorder.inputFormat.mChannelsPerFrame)
        bufferList.mBuffers.mDataByteSize = inNumberFrames * UInt32(recorder.inputFormat.mBytesPerFrame)
        bufferList.mBuffers.mData = nil // AudioUnitRender 会分配

        // 获取音频数据
        let status = AudioUnitRender(
            recorder.audioUnit!,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            &bufferList
        )

        guard status == noErr else {
            log.error("AudioUnitRender failed: \(status)")
            return status
        }

        // 处理音频数据
        recorder.processAudioBuffer(&bufferList, frameCount: inNumberFrames)

        return noErr
    }

    private func processAudioBuffer(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
        guard let buffer = bufferList.pointee.mBuffers.mData else { return }

        // 转换格式
        let convertedData = convertAudioFormat(buffer, frameCount: frameCount)
        guard !convertedData.isEmpty else { return }

        // 计算音量
        let volume = calculateVolume(from: convertedData)
        EventBus.shared.publish(.volumeChanged(volume: volume))

        // 编码并发送
        encodeAndQueue(convertedData)
    }

    private func convertAudioFormat(_ inputData: UnsafeMutableRawPointer, frameCount: UInt32) -> Data {
        guard let conv = converter else { return Data() }

        // 计算输出帧数
        let conversionRatio = targetFormat.mSampleRate / inputFormat.mSampleRate
        let outputFrameCount = UInt32(Double(frameCount) * conversionRatio)
        let outputDataSize = outputFrameCount * UInt32(targetFormat.mBytesPerFrame)

        var outputData = Data(count: Int(outputDataSize))

        var outputBufferList = AudioBufferList()
        outputBufferList.mNumberBuffers = 1

        outputData.withUnsafeMutableBytes { rawBufferPointer in
            outputBufferList.mBuffers.mNumberChannels = UInt32(targetFormat.mChannelsPerFrame)
            outputBufferList.mBuffers.mDataByteSize = outputDataSize
            outputBufferList.mBuffers.mData = rawBufferPointer.baseAddress

            var ioOutputDataPacketSize = outputFrameCount

            // 输入数据提供回调
            let inputDataProc: AudioConverterComplexInputDataProc = {
                _,
                    ioNumberDataPackets,
                    ioData,
                    _,
                    inUserData
                    -> OSStatus in
                guard let userData = inUserData else { return -1 }

                let context = userData.assumingMemoryBound(to: AudioConverterContext.self).pointee

                ioData.pointee.mNumberBuffers = 1
                ioData.pointee.mBuffers.mNumberChannels = UInt32(context.inputFormat.mChannelsPerFrame)
                ioData.pointee.mBuffers.mDataByteSize = context.frameCount * UInt32(context.inputFormat.mBytesPerFrame)
                ioData.pointee.mBuffers.mData = context.inputData

                ioNumberDataPackets.pointee = context.frameCount

                return noErr
            }

            var context = AudioConverterContext(
                inputData: inputData,
                frameCount: frameCount,
                inputFormat: inputFormat
            )

            let status = AudioConverterFillComplexBuffer(
                conv,
                inputDataProc,
                &context,
                &ioOutputDataPacketSize,
                &outputBufferList,
                nil
            )

            if status != noErr {
                log.error("AudioConverterFillComplexBuffer failed: \(status)")
            }
        }

        // 调整实际大小
        let actualSize = Int(outputBufferList.mBuffers.mDataByteSize)
        if actualSize < outputData.count {
            outputData.removeLast(outputData.count - actualSize)
        }

        totalRawBytesSent += outputData.count

        return outputData
    }

    private func encodeAndQueue(_ pcmData: Data) {
        // 转换为 AVAudioPCMBuffer 供 Opus 编码器使用
        let frameCount = pcmData.count / Int(targetFormat.mBytesPerFrame)
        let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(targetFormat.mSampleRate),
            channels: AVAudioChannelCount(targetFormat.mChannelsPerFrame),
            interleaved: true
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            let dest = buffer.audioBufferList.pointee.mBuffers.mData!
            memcpy(dest, baseAddress, pcmData.count)
        }

        // Opus 编码
        for opusFrame in opusEncoder.encodeBuffer(buffer) {
            for packet in oggPacketizer.append(frame: opusFrame) {
                audioQueue.append(packet)
            }
        }

        handleQueuedAudio()
    }

    private func calculateVolume(from data: Data) -> Float {
        guard data.count >= 2 else { return 0.0 }

        let samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
        var sum: Float = 0.0

        for sample in samples {
            let normalized = Float(sample) / Float(Int16.max)
            sum += normalized * normalized
        }

        let rms = sqrt(sum / Float(samples.count))
        return min(1.0, rms * 10.0)
    }

    // MARK: - 录音控制

    @MainActor
    func startRecording(mode: RecordMode = .normal) {
        guard recordState == .idle else {
            log.warning("Cant Start recording, now state: \(recordState)")
            return
        }

        resetState()
        recordState = .recording
        recordMode = mode

        do {
            try setupAudioUnit()

            guard let unit = audioUnit else {
                throw NSError(domain: "AudioUnit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio unit not initialized"])
            }

            let status = AudioOutputUnitStart(unit)
            guard status == noErr else {
                throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to start audio unit: \(status)"])
            }

            startRecordingTimers()
            log.info("🎙️ Start Recording (Audio Unit)")

        } catch {
            log.error("🙅 Failed to start recording: \(error.localizedDescription)")
            recordState = .idle
        }
    }

    @MainActor
    func stopRecording(
        stopState: RecordState = .processing,
        shouldSetResponseTimer: Bool = true
    ) {
        guard recordState == .recording else {
            return
        }

        recordState = .stopping

        // 停止 Audio Unit
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
        }

        // 刷新编码器缓冲区
        if let encoder = opusEncoder, let finalData = encoder.flush() {
            for packet in oggPacketizer.append(frame: finalData) {
                audioQueue.append(packet)
            }
            log.info("📦 Opus encoder flushed final frame: \(finalData.count) bytes")
        }

        flushPendingOggPackets(final: true)
        while let audioData = audioQueue.popFirst() {
            sendAudioData(audioData)
        }

        recordState = isRecordingStarted ? stopState : .idle
        printRecordingStatistics()

        EventBus.shared.publish(
            .recordingStopped(
                shouldSetResponseTimer: isRecordingStarted ? shouldSetResponseTimer : false,
                wssState: ConnectionCenter.shared.wssState
            )
        )
        log.info("✅ Recording Stopped")
    }

    @MainActor
    func resetState() {
        saveRecordingToLocalFile()
        recordState = .idle

        // 清理 Audio Unit
        cleanup()

        audioQueue.removeAll()
        totalPacketsSent = 0
        totalBytesSent = 0
        totalRawBytesSent = 0
        recordingStartTime = Date()
        isRecordingStarted = false
        queueStartTime = nil

        opusEncoder.reset()
        oggPacketizer.reset()
        stopRecordingTimers()
    }

    private func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }

        if let conv = converter {
            AudioConverterDispose(conv)
            converter = nil
        }
    }

    // MARK: - 设备切换

    @MainActor
    private func reconfigureAudioUnit() async {
        log.info("🔄 Reconfigure Audio Unit".yellow)

        let wasRecording = recordState == .recording

        if wasRecording {
            stopRecording(stopState: .idle, shouldSetResponseTimer: false)
        }

        cleanup()

        // 等待设备稳定
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        if wasRecording {
            startRecording(mode: recordMode)
        }

        log.info("🔄 Audio Unit reconfigured")
    }

    // MARK: - 辅助方法

    private func flushPendingOggPackets(final: Bool) {
        guard let packetizer = oggPacketizer else { return }
        for packet in packetizer.flush(final: final) {
            audioQueue.append(packet)
        }
    }

    private func sendAudioData(_ audioData: Data) {
        totalPacketsSent += 1
        totalBytesSent += audioData.count
        recordedAudioData.append(audioData)
        EventBus.shared.publish(.audioDataReceived(data: audioData))
    }

    func handleModeUpgrade() {
        if isRecordingStarted {
            EventBus.shared.publish(.modeUpgraded(from: .normal, to: .command))
        } else {
            recordMode = .command
        }
    }

    private func saveRecordingToLocalFile() {
        guard !recordedAudioData.isEmpty else { return }
        guard let dir = UserConfigService.shared.audiosDirectory else {
            recordedAudioData.removeAll()
            return
        }

        let filename = "recording-unit-\(Int(Date().timeIntervalSince1970)).ogg"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            try recordedAudioData.write(to: fileURL)
            log.info("💾 Saved recording to \(fileURL.lastPathComponent)")
        } catch {
            log.error("Failed to save recording: \(error)")
        }

        recordedAudioData.removeAll()
    }
}

// MARK: - 辅助结构

private struct AudioConverterContext {
    let inputData: UnsafeMutableRawPointer
    let frameCount: UInt32
    let inputFormat: AudioStreamBasicDescription
}

// MARK: - 响应式音频流处理

extension AudioUnitRecorder {
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
                     .terminalLinuxChoice:
                    Task { @MainActor in
                        if self?.recordState == .processing {
                            self?.resetState()
                        }
                    }
                case .notificationReceived(.serverTimeout),
                     .notificationReceived(.networkUnavailable),
                     .notificationReceived(.error):
                    Task { @MainActor in
                        self?.resetState()
                    }
                case .notificationReceived(.serverUnavailable(duringRecording: true)):
                    log.error("Server unavailable, stop recording")
                    Task { @MainActor in
                        if self?.recordState == .processing {
                            self?.resetState()
                        } else {
                            self?.stopRecording(stopState: .idle, shouldSetResponseTimer: false)
                        }
                    }
                case .audioDeviceChanged:
                    Task { @MainActor in
                        await self?.reconfigureAudioUnit()
                    }
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

        processAudioQueue()
    }

    private func handleConnectionStateChange() {
        guard recordState == .recording, ConnectionCenter.shared.canRecord() else {
            return
        }

        queueStartTime = nil
        processAudioQueue()
    }

    private func processAudioQueue() {
        startRecordingIfNeeded()
        flushAudioQueue()
    }

    private func flushAudioQueue() {
        while let audioData = audioQueue.popFirst() {
            sendAudioData(audioData)
        }
    }

    private func startRecordingIfNeeded() {
        guard !isRecordingStarted else { return }

        isRecordingStarted = true
        EventBus.shared.publish(.recordingStarted(mode: recordMode))
    }

    private func checkAndHandleTimeout() {
        guard !isRecordingStarted else { return }

        if queueStartTime == nil {
            queueStartTime = Date()
            log.warning("Set queue start time")
            EventBus.shared.publish(.recordingCacheStarted(mode: recordMode))
        } else if let startTime = queueStartTime, Date().timeIntervalSince(startTime) >= 2.0 {
            log.error("Audio queue timeout: failed to establish connection within 2 seconds.")
            Task { @MainActor in
                self.stopRecording()
                EventBus.shared.publish(.recordingCacheTimeout)
                EventBus.shared.publish(.notificationReceived(.networkUnavailable))
            }
        }
    }
}

// MARK: - 定时器

extension AudioUnitRecorder {
    private func startRecordingTimers() {
        let warningTime = maxRecordingDuration - warningBeforeTimeout

        Task { @MainActor [weak self] in
            guard let self else { return }
            recordingLimitTimer = Timer.scheduledTimer(withTimeInterval: warningTime, repeats: false) { [weak self] _ in
                guard let self, recordState == .recording else { return }
                EventBus.shared.publish(.notificationReceived(.recordingTimeoutWarning))

                recordingLimitTimer = Timer.scheduledTimer(withTimeInterval: warningBeforeTimeout, repeats: false) { [weak self] _ in
                    guard let self, recordState == .recording else { return }
                    log.warning("Recording timeout: exceeded \(maxRecordingDuration) seconds")
                    Task { @MainActor in
                        self.stopRecording()
                    }
                }
            }
        }
    }

    private func stopRecordingTimers() {
        recordingLimitTimer?.invalidate()
        recordingLimitTimer = nil
    }
}

// MARK: - 统计

extension AudioUnitRecorder {
    private func printRecordingStatistics() {
        guard let startTime = recordingStartTime, isRecordingStarted else { return }

        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return }

        let avgPacketSize = totalPacketsSent > 0 ? Double(totalBytesSent) / Double(totalPacketsSent) : 0
        let packetsPerSecond = Double(totalPacketsSent) / duration
        let bytesPerSecond = Double(totalBytesSent) / duration

        let theoreticalBytes = Int(duration * 16000 * 2)

        let compressionRatio = totalRawBytesSent > 0 ? Double(totalRawBytesSent) / Double(totalBytesSent) : 1.0
        let compressionPercentage = totalRawBytesSent > 0 ? (1.0 - Double(totalBytesSent) / Double(totalRawBytesSent)) * 100.0 : 0.0
        let bandwidthSaved = totalRawBytesSent - totalBytesSent

        log.info(
            """
            📊 录音统计报告 (Audio Unit):
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
