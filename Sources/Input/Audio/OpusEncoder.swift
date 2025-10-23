//
//  OpusEncoder.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/21.
//

import AVFoundation
import Foundation
import Opus

/// Opus 编码器封装
/// 专为语音优化，提供高压缩比和低延迟
class OpusEncoder {
    private let encoder: Opus.Encoder
    private let format: AVAudioFormat
    private let frameSize: AVAudioFrameCount

    // 样本缓冲区：用于累积不完整的帧
    private var sampleBuffer: [Int16] = []
    private let lock = NSLock()

    /// 初始化 Opus 编码器
    /// - Parameters:
    ///   - format: 音频格式（必须 16-bit PCM）
    ///   - application: 应用类型 (.voip 为语音优化)
    ///   - frameSize: 每帧样本数 (建议 160 samples @ 16kHz = 10ms)
    init?(
        format: AVAudioFormat,
        application: Opus.Application = .voip,
        frameSize: AVAudioFrameCount = 160
    ) {
        self.frameSize = frameSize
        self.format = format

        do {
            self.encoder = try Opus.Encoder(format: format, application: application)
            log.debug("Opus encoder initialized")
        } catch {
            log.error("Opus encoder create failed: \(error)")
            return nil
        }
    }

    /// 编码单个完整帧（内部方法）
    /// - Parameter buffer: AVAudioPCMBuffer（必须是 frameSize 大小）
    /// - Returns: 编码后的 Opus 数据，失败返回 nil
    private func encodeSingleFrame(_ buffer: AVAudioPCMBuffer) -> Data? {
        do {
            // 预分配输出缓冲区 (Opus 最大输出 4000 bytes)
            var output = Data(count: 1000)
            let bytesEncoded = try encoder.encode(buffer, to: &output)
            // 截取实际编码的数据
            output = output.prefix(bytesEncoded)
            // log.debug("Opus encode success: \(buffer.frameLength) samples -> \(bytesEncoded) bytes")
            return output
        } catch {
            log.error("Opus encode failed: \(error)")
            return nil
        }
    }

    /// 编码 PCM 缓冲区
    /// - Parameter inputBuffer: AVAudioPCMBuffer
    /// - Returns: 编码后的 Opus 数据数组
    func encodeBuffer(_ inputBuffer: AVAudioPCMBuffer) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        var encodedFrames: [Data] = []

        // 验证输入
        guard inputBuffer.frameLength > 0,
              let channelData = inputBuffer.int16ChannelData?[0]
        else {
            log.warning("empty pcm buffer")
            return []
        }

        // 将新 buffer 样本追加到样本缓冲区
        let samples = UnsafeBufferPointer(start: channelData, count: Int(inputBuffer.frameLength))
        sampleBuffer.append(contentsOf: samples)


        // 处理缓冲区中所有完整的帧
        var frameCount = 0
        while sampleBuffer.count >= Int(frameSize) {
            frameCount += 1

            // 创建临时 PCM buffer 用于编码
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameSize)
            else {
                log.error("failed to create pcm buffer")
                break
            }

            pcmBuffer.frameLength = frameSize

            // 从 sampleBuffer 复制到 PCM buffer
            if let dst = pcmBuffer.int16ChannelData?[0] {
                _ = sampleBuffer.withUnsafeBufferPointer { src in
                    memcpy(dst, src.baseAddress!, Int(frameSize) * 2)
                }

                // 编码
                if let encoded = encodeSingleFrame(pcmBuffer) {
                    encodedFrames.append(encoded)
                } else {
                    log.error("encode single frame failed")
                }

                // 移除已处理的样本
                sampleBuffer.removeFirst(Int(frameSize))
            }
        }

        // log.debug("Encode \(frameCount) frames, remaining \(sampleBuffer.count) samples")
        return encodedFrames
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        sampleBuffer.removeAll()
    }

    /// 刷新缓冲区，强制编码剩余数据（用于录音结束时）
    /// - Returns: 编码后的数据，如果没有足够数据则返回 nil
    func flush() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard !sampleBuffer.isEmpty else { return nil }

        // 如果缓冲区数据不足一帧，填充静音
        if sampleBuffer.count < Int(frameSize) {
            let silenceSamples = Int(frameSize) - sampleBuffer.count
            sampleBuffer.append(contentsOf: [Int16](repeating: 0, count: silenceSamples))
        }

        // 编码最后一帧
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameSize) else {
            return nil
        }

        pcmBuffer.frameLength = frameSize

        if let dst = pcmBuffer.int16ChannelData?[0] {
            _ = sampleBuffer.withUnsafeBufferPointer { src in
                memcpy(dst, src.baseAddress!, Int(frameSize) * 2)
            }
        }

        sampleBuffer.removeAll()
        return encodeSingleFrame(pcmBuffer)
    }
}
