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

enum RecordState {
    case idle
    case recording
    case recordingTimeout
    case processing
    case stopping
}

/// 基于 Audio Unit 的录音器
/// 避免 AVAudioEngine 的聚合设备问题
class AudioUnitRecorder: @unchecked Sendable {
    @Published var recordState: RecordState = .idle

    // Audio Unit 组件

    private var audioUnit: AudioUnit?
    private var avAudioConverter: AVAudioConverter?
    private var opusEncoder: OpusEncoder!
    private var oggPacketizer: OpusOggStreamPacketizer!

    // 音频格式

    private let targetFormat = AudioStreamBasicDescription(
        mSampleRate: 16000.0,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
    )

    private var inputFormat = AudioStreamBasicDescription()
    private var inputAVFormat: AVAudioFormat?
    private let targetAVFormat: AVAudioFormat = .init(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000.0,
        channels: 1,
        interleaved: true
    )!

    // 录音配置

    private let opusFrameSamples = 160 // 10ms @ 16kHz
    private var opusFramesPerPacket = 20 // 默认聚合 200ms

    private var audioQueue: Deque<Data> = .init()
    private var recordedAudioData = Data()
    private var cancellables = Set<AnyCancellable>()
    private var queueStartTime: Date?
    private var isRecordingStarted = false
    private var recordMode: RecordMode = .normal

    // 录音统计数据

    private var totalPacketsSent = 0
    private var totalBytesSent = 0
    private var totalRawBytesSent = 0
    private var recordingStartTime: Date?
    private var recordingStopTime: Date?

    // 录音时长限制

    private let maxRecordingDuration: TimeInterval = 300
    private let warningBeforeTimeout: TimeInterval = 15
    private var recordingLimitTimer: Timer?

    // 线程安全

    private let lock = NSLock()

    init() {
        setupOpusEncoderAndPacketizer()
        setupAudioEventListener()
    }

    deinit {
        cleanup()
    }

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

        if let unit = audioUnit {
            // 尝试获取属性验证 Audio Unit 是否真正可用
            var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var testFormat = AudioStreamBasicDescription()
            let status = AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                1,
                &testFormat,
                &propertySize
            )

            if status == noErr {
                log.debug("Audio Unit 已初始化且有效,跳过重复初始化")
                return
            } else {
                // Audio Unit 无效,清空并重新创建
                log.warning("Audio Unit 指针存在但已失效 (status: \(status)),重新初始化")
                audioUnit = nil
                avAudioConverter = nil
                inputAVFormat = nil
            }
        }

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

        // 4. 设置输入设备（若用户设备已失效则回退到系统默认）
        let deviceManager = AudioDeviceManager.shared
        var deviceID = deviceManager.selectedDeviceID ?? 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            let systemDefaultID = deviceManager.selectedDeviceID ?? 0
            if systemDefaultID > 0, systemDefaultID != deviceID {
                log.warning("指定输入设备不可用(\(deviceID)), 回退到系统默认: \(systemDefaultID)")
                deviceID = systemDefaultID
                status = AudioUnitSetProperty(
                    unit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }
        }

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

        // 8. 设置最大帧数 (关键: 必须在初始化前设置)
        var maxFrames: UInt32 = 4096
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxFrames,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set max frames: \(status)"])
        }

        // 9. 创建格式转换器（保持与 AudioEngine 一致的高质量重采样）
        inputAVFormat = AVAudioFormat(streamDescription: &inputFormat)
        if let inputAVFormat {
            avAudioConverter = AVAudioConverter(from: inputAVFormat, to: targetAVFormat)
            avAudioConverter?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        }

        // 10. 初始化 Audio Unit
        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize audio unit: \(status)"])
        }

        log.info("✅ Audio Unit 初始化完成")
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

        guard let inputFormat = recorder.inputAVFormat,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: inputFormat,
                  frameCapacity: AVAudioFrameCount(inNumberFrames)
              )
        else {
            return noErr
        }

        buffer.frameLength = AVAudioFrameCount(inNumberFrames)

        // 获取音频数据（直接渲染进 AVAudioPCMBuffer）
        let status = AudioUnitRender(
            recorder.audioUnit!,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            buffer.mutableAudioBufferList
        )

        guard status == noErr else {
            log.error("AudioUnitRender failed: \(status)")
            return status
        }

        // 处理音频数据
        recorder.processAudioBuffer(buffer)

        return noErr
    }

    private func processAudioBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter = avAudioConverter else { return }

        // 以与 AudioEngine 相同的路径重采样
        let estimatedOutputFrames = AVAudioFrameCount(
            Double(inputBuffer.frameLength)
                * targetAVFormat.sampleRate
                / inputBuffer.format.sampleRate
        ) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetAVFormat,
            frameCapacity: max(estimatedOutputFrames, 1)
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error else {
            log.error("Audio convert failed: \(error?.localizedDescription ?? "unknown")")
            return
        }

        guard let pcmData = pcmBufferToData(outputBuffer), !pcmData.isEmpty else { return }
        recordedAudioData.append(pcmData)

        let volume = calculateVolume(from: pcmData)
        EventBus.shared.publish(.volumeChanged(volume: volume))

        totalRawBytesSent += pcmData.count
        encodeAndQueue(pcmData)
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

    func currentRecordingDuration() -> TimeInterval {
        guard let startTime = recordingStartTime else {
            return 0
        }
        return Date().timeIntervalSince(startTime)
    }

    @MainActor
    func startRecording(mode: RecordMode = .normal) {
        guard recordState == .idle else {
            log.warning("Cant Start recording, now state: \(recordState)")
            return
        }

        // 重置录音状态,但不清理 Audio Unit
        resetRecordingState()
        recordState = .recording
        recordMode = mode

        do {
            // 延迟初始化: 只在首次或重建后初始化
            try setupAudioUnit()

            guard let unit = audioUnit else {
                throw NSError(domain: "AudioUnit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio unit not initialized"])
            }

            // 启动 Audio Unit (不重新初始化)
            var status = AudioOutputUnitStart(unit)

            // 如果错误是 -10867
            // 可能是 Audio Unit 已在运行,先停止再启动
            if status == -10867 {
                log.warning("Audio Unit 可能已在运行,尝试先停止再启动")
                AudioOutputUnitStop(unit)
                status = AudioOutputUnitStart(unit)
            }

            guard status == noErr else {
                throw NSError(domain: "AudioUnit", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to start audio unit: \(status)"])
            }

            startRecordingTimers()
            log.info("🎙️ 开始录音")

        } catch {
            log.error("🙅 Failed to start recording: \(error.localizedDescription)".red)
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
        recordingStopTime = Date()

        // 停止 Audio Unit, 不销毁
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
        }

        // 刷新编码器缓冲区
        if let encoder = opusEncoder, let finalData = encoder.flush() {
            for packet in oggPacketizer.append(frame: finalData) {
                audioQueue.append(packet)
            }
        }

        flushPendingOggPackets(final: true)
        while let audioData = audioQueue.popFirst() {
            sendAudioData(audioData)
        }

        // 处理响应
        let canRecord = ConnectionCenter.shared.canRecord()
        let hasNetworkError = ConnectionCenter.shared.hasRecordingNetworkError()

        if !canRecord || hasNetworkError, !ConnectionCenter.shared.canResumeAfterNetworkError(), isRecordingStarted {
            saveAudioToDatabase(error: "转录未完成，你可在此处重新转录")
        }

        let shouldStopNormally = canRecord && (hasNetworkError || isRecordingStarted)

        recordState = shouldStopNormally ? stopState : .idle
        printRecordingStatistics()

        EventBus.shared.publish(
            .recordingStopped(
                isRecordingStarted: isRecordingStarted,
                shouldSetResponseTimer: shouldStopNormally && shouldSetResponseTimer
            )
        )
        log.info("✅ 录音停止")
    }

    @MainActor
    func resetState() {
        recordState = .idle
        resetRecordingState()
    }

    // 重置录音状态但保留 Audio Unit
    private func resetRecordingState() {
        audioQueue.removeAll()
        recordedAudioData.removeAll()
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
        }

        totalPacketsSent = 0
        totalBytesSent = 0
        totalRawBytesSent = 0
        recordingStartTime = Date()
        recordingStopTime = nil
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
        }

        audioUnit = nil
        avAudioConverter = nil
        inputAVFormat = nil

        log.debug("Audio Unit Cleaned Up!")
    }

    // MARK: - 设备切换

    @MainActor
    private func reconfigureAudioUnit() async {
        let wasRecording = recordState == .recording

        if wasRecording {
            stopRecording(stopState: .idle, shouldSetResponseTimer: false)
        }

        // 设备切换时必须完全重建 Audio Unit
        cleanup()

        // 等待设备稳定和资源释放
        // 这个延迟很重要,确保:
        // 1. 旧设备资源完全释放
        // 2. 新设备完全激活
        // 3. 系统音频服务器状态稳定
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        if wasRecording {
            startRecording(mode: recordMode)
        }

        log.info("✅ Audio Unit 已重新配置".yellow)
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

    func handleModeUpgrade(from _: RecordMode, to: RecordMode) {
        if isRecordingStarted {
            EventBus.shared.publish(.modeUpgraded(from: .normal, to: to))
        } else if to != .normal {
            recordMode = to
        }
    }

    private func saveAudioToDatabase(content: String = "", error: String = "") {
        guard let dir = UserConfigService.shared.audiosDirectory, isRecordingStarted else { return }

        if let startTime = recordingStartTime, let stopTime = recordingStopTime {
            let duration = stopTime.timeIntervalSince(startTime)
            if duration < 0.5 {
                log.info("录音时长小于 500 毫秒 (\(Int(duration * 1000))ms), 不保存")
                return
            }
        }

        // 当设置为 "never" 且没有错误时，不保存
        if Config.shared.USER_CONFIG.setting.historyRetention == "never", error.isEmpty {
            return
        }

        let sessionID = ConnectionCenter.shared.currentRecordingAppContext.sessionID
        let filename = "\(sessionID).wav"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            let wavData = toWavData(fromPCM: recordedAudioData, targetFormat: targetFormat)
            try wavData.write(to: fileURL)
            let clearBeforeInsert = Config.shared.USER_CONFIG.setting.historyRetention == "never" && !error.isEmpty
            try DatabaseService.shared.saveAudios(sessionID: sessionID, filename: filename, content: content, error: error, clearBeforeInsert: clearBeforeInsert)
            log.info("Audio saved to file: \(filename) \nError: \(error)\nContent: \(content)")
            EventBus.shared.publish(.userAudioSaved(sessionID: sessionID, filename: filename))
        } catch {
            log.error("Failed to save recording: \(error)")
        }
    }

    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0 else { return nil }

        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let realDataCount = Int(buffer.frameLength) * bytesPerFrame

        guard let mData = buffer.audioBufferList.pointee.mBuffers.mData else { return nil }
        return Data(bytes: mData, count: realDataCount)
    }

    func getCurrentRecordingSessionDuration() -> TimeInterval {
        if let startTime = recordingStartTime, let stopTime = recordingStopTime {
            return stopTime.timeIntervalSince(startTime)
        }
        return 0
    }

    func getCurrentRecordingSessionMode() -> RecordMode {
        recordMode
    }
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
                case let .serverResultReceived(summary, _, _, _):
                    Task { @MainActor in
                        if self?.recordState == .processing {
                            self?.saveAudioToDatabase(content: summary)
                            self?.resetState()
                        }
                    }
                case let .terminalLinuxChoice(_, _, _, commands):
                    Task { @MainActor in
                        if self?.recordState == .processing {
                            self?.saveAudioToDatabase(content: commands.map { $0.displayName }.joined(separator: "\n"))
                            self?.resetState()
                        }
                    }
                case let .notificationReceived(messageType):
                    switch messageType {
                    case .serverTimeout:
                        Task { @MainActor in
                            self?.saveAudioToDatabase(error: "转录未完成，你可在此处重新转录")
                            self?.resetState()
                        }

                    case let .networkUnavailable(duringRecording):
                        Task { @MainActor in
                            // 在录音过程中断网
                            // 需要继续保存录音
                            if duringRecording {
                            } else {
                                self?.resetState()
                            }
                        }

                    case .error:
                        Task { @MainActor in
                            self?.saveAudioToDatabase(error: "转录未完成，你可在此处重新转录")
                            self?.resetState()
                        }

                    case .serverUnavailable(duringRecording: true):
                        log.error("Server unavailable, stop recording")
                        Task { @MainActor in
                            if self?.recordState == .processing {
                                self?.saveAudioToDatabase(error: "转录未完成，你可在此处重新转录")
                                self?.resetState()
                            } else {
                                self?.stopRecording(stopState: .idle, shouldSetResponseTimer: false)
                            }
                        }

                    default:
                        break
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
        guard recordState == .recording, ConnectionCenter.shared.canRecord(), !isRecordingStarted else {
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
        guard !audioQueue.isEmpty else { return }
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
        } else if let startTime = queueStartTime, Date().timeIntervalSince(startTime) >= 3.0 {
            log.error("Audio queue timeout: failed to establish connection within 3 seconds.")
            Task { @MainActor in
                self.stopRecording()
                EventBus.shared.publish(.recordingCacheTimeout)
                EventBus.shared.publish(.notificationReceived(.networkUnavailable(duringRecording: false)))
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
                        EventBus.shared.publish(.recordingConfirmed)
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
        guard let startTime = recordingStartTime,
              let stopTime = recordingStopTime,
              isRecordingStarted else { return }

        let duration = stopTime.timeIntervalSince(startTime)
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
