import AudioToolbox
import Foundation

func sleep(_ milliseconds: Int64) async throws {
    try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
}

func toWavData(fromPCM pcmData: Data, targetFormat: AudioStreamBasicDescription) -> Data {
    let sampleRate = UInt32(targetFormat.mSampleRate)
    let channels = UInt16(targetFormat.mChannelsPerFrame)
    let bitsPerSample = UInt16(targetFormat.mBitsPerChannel)
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
    let blockAlign = UInt16(channels * bitsPerSample / 8)

    var data = Data()
    func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    data.append("RIFF".data(using: .ascii)!)
    appendLE(UInt32(36) + UInt32(pcmData.count))
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    appendLE(UInt32(16))
    appendLE(UInt16(1))
    appendLE(channels)
    appendLE(sampleRate)
    appendLE(byteRate)
    appendLE(blockAlign)
    appendLE(bitsPerSample)
    data.append("data".data(using: .ascii)!)
    appendLE(UInt32(pcmData.count))
    data.append(pcmData)
    return data
}
