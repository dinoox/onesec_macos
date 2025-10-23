//
//  OggOpusPacketizer.swift
//  OnesecCore
//
//  Created by Codex on 2024/11/08.
//

import Foundation

/// 将连续的 Opus 帧封装为同一个 Ogg/Opus 流
final class OpusOggStreamPacketizer {
    private static let opusInternalSampleRate = 48_000
    private static let oggSignature: [UInt8] = [0x4F, 0x67, 0x67, 0x53] // "OggS"
    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var r = UInt32(index) << 24
            for _ in 0..<8 {
                if (r & 0x8000_0000) != 0 {
                    r = (r << 1) ^ 0x04C11DB7
                } else {
                    r <<= 1
                }
            }
            return r & 0xFFFF_FFFF
        }
    }()

    private let sampleRate: Int
    private let channelCount: Int
    private let opusFrameSamples: Int
    private var framesPerPacket: Int
    private let vendorString: String

    private var streamSerial: UInt32 = UInt32.random(in: UInt32.min...UInt32.max)
    private var sequenceNumber: UInt32 = 0
    private var granulePosition: UInt64 = 0
    private var headersSent = false
    private var finished = false
    private var pendingFrames: [Data] = []
    private var cachedHeaderPages: Data = Data()

    private var granuleIncrementPerFrame: Int {
        max(
            1,
            (Self.opusInternalSampleRate * opusFrameSamples) / max(sampleRate, 1)
        )
    }

    init(
        sampleRate: Int,
        channelCount: Int,
        opusFrameSamples: Int,
        framesPerPacket: Int,
        vendorString: String = "Onesec"
    ) {
        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.opusFrameSamples = opusFrameSamples
        self.framesPerPacket = max(1, framesPerPacket)
        self.vendorString = vendorString
        rebuildHeaders()
    }

    func reset() {
        streamSerial = UInt32.random(in: UInt32.min...UInt32.max)
        sequenceNumber = 0
        granulePosition = 0
        headersSent = false
        finished = false
        pendingFrames.removeAll(keepingCapacity: true)
        rebuildHeaders()
    }

    func updateFramesPerPacket(_ count: Int) {
        framesPerPacket = max(1, count)
    }

    func append(frame: Data) -> [Data] {
        guard !finished else { return [] }
        pendingFrames.append(frame)
        return drainReadyPackets(triggerFinal: false)
    }

    func flush(final: Bool) -> [Data] {
        guard !finished else { return [] }

        var output = drainReadyPackets(triggerFinal: final)
        if final {
            if !headersSent {
                output.append(cachedHeaderPages)
                headersSent = true
            }
            output.append(makeEndPage())
            finished = true
        }
        return output
    }

    // MARK: - Internal helpers

    private func drainReadyPackets(triggerFinal: Bool) -> [Data] {
        var output: [Data] = []

        if !headersSent, !pendingFrames.isEmpty {
            output.append(cachedHeaderPages)
            headersSent = true
        }

        while pendingFrames.count >= framesPerPacket {
            let frames = Array(pendingFrames.prefix(framesPerPacket))
            pendingFrames.removeFirst(framesPerPacket)
            output.append(makeAudioPage(with: frames))
        }

        if triggerFinal, !pendingFrames.isEmpty {
            let remainingFrames = pendingFrames
            pendingFrames.removeAll()
            output.append(makeAudioPage(with: remainingFrames))
        }

        return output
    }

    private func rebuildHeaders() {
        let headPage = makeHeaderPage()
        let tagsPage = makeTagsPage()
        cachedHeaderPages = headPage + tagsPage
    }

    private func makeHeaderPage() -> Data {
        var payload = Data()
        payload.append(contentsOf: [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]) // "OpusHead"
        payload.append(0x01) // version
        payload.append(UInt8(channelCount))
        payload.appendUInt16LE(0) // pre-skip
        payload.appendUInt32LE(UInt32(sampleRate))
        payload.appendUInt16LE(0) // output gain
        payload.append(0x00) // channel mapping family

        return makeOggPage(
            packets: [payload],
            headerType: 0x02,
            advanceGranuleBy: 0
        )
    }

    private func makeTagsPage() -> Data {
        var payload = Data()
        payload.append(contentsOf: [0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73]) // "OpusTags"

        let vendorData = vendorString.data(using: .utf8) ?? Data()
        payload.appendUInt32LE(UInt32(vendorData.count))
        payload.append(vendorData)
        payload.appendUInt32LE(0) // user comment list length

        return makeOggPage(
            packets: [payload],
            headerType: 0x00,
            advanceGranuleBy: 0
        )
    }

    private func makeAudioPage(with frames: [Data]) -> Data {
        let increment = frames.count * granuleIncrementPerFrame
        return makeOggPage(
            packets: frames,
            headerType: 0x00,
            advanceGranuleBy: increment
        )
    }

    private func makeEndPage() -> Data {
        return makeOggPage(
            packets: [Data()],
            headerType: 0x04,
            advanceGranuleBy: 0
        )
    }

    private func makeOggPage(
        packets: [Data],
        headerType: UInt8,
        advanceGranuleBy: Int
    ) -> Data {
        if advanceGranuleBy > 0 {
            granulePosition &+= UInt64(advanceGranuleBy)
        }

        let (lacingValues, payload) = segmentPackets(packets: packets)
        var page = Data()

        page.append(contentsOf: Self.oggSignature)
        page.append(0x00) // version
        page.append(headerType)
        page.appendUInt64LE(granulePosition)
        page.appendUInt32LE(streamSerial)
        page.appendUInt32LE(sequenceNumber)
        page.appendUInt32LE(0) // CRC placeholder
        page.append(UInt8(lacingValues.count))
        page.append(contentsOf: lacingValues)
        page.append(payload)

        let checksum = Self.computeCRC(page)
        page.replaceSubrange(22..<26, with: checksum.bytesLE)

        sequenceNumber &+= 1
        return page
    }

    private func segmentPackets(packets: [Data]) -> ([UInt8], Data) {
        var lacing: [UInt8] = []
        var payload = Data()

        for packet in packets {
            var remaining = packet.count
            var offset = 0

            if remaining == 0 {
                lacing.append(0)
                continue
            }

            while remaining > 0 && lacing.count < 255 {
                let segmentSize = min(remaining, 255)
                lacing.append(UInt8(segmentSize))
                if segmentSize > 0 {
                    payload.append(packet[offset..<offset + segmentSize])
                }

                offset += segmentSize
                remaining -= segmentSize
            }

            if remaining > 0 {
                log.warning("Ogg page overflow, truncating packet")
                remaining = 0
            }

            if packet.count > 0, packet.count % 255 == 0, lacing.count < 255 {
                lacing.append(0)
            }
        }

        if lacing.isEmpty {
            lacing.append(0)
        }

        return (lacing, payload)
    }

    private static func computeCRC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            let index = Int(((crc >> 24) & 0xFF) ^ UInt32(byte))
            crc = (crc << 8) ^ crcTable[index]
        }
        return crc & 0xFFFF_FFFF
    }
}

private extension UInt32 {
    var bytesLE: [UInt8] {
        let little = self.littleEndian
        return withUnsafeBytes(of: little) { Array($0) }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
