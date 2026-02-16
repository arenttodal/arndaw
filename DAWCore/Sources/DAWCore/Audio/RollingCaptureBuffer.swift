import Foundation
import AVFoundation
import Combine

// MARK: - Rolling Capture Buffer

/// A lock-free circular audio buffer that continuously captures the last N minutes of audio input
/// This is the heart of Capture Mode — audio is always being recorded to RAM,
/// and the user can retroactively save any portion of the buffer
public final class RollingCaptureBuffer: @unchecked Sendable {

    // MARK: - Configuration

    /// Maximum buffer duration in seconds (default: 5 minutes)
    public let maxDuration: TimeInterval

    /// Sample rate of the captured audio
    public let sampleRate: Double

    /// Number of channels (1 = mono, 2 = stereo)
    public let channelCount: Int

    // MARK: - Buffer Storage

    /// Interleaved audio samples (channel 0 sample 0, channel 1 sample 0, channel 0 sample 1, ...)
    private var buffer: UnsafeMutablePointer<Float>

    /// Total capacity in frames (samples per channel)
    private let capacityInFrames: Int

    /// Current write position in frames (monotonically increasing, use modulo for ring index)
    private var writePosition: Int64 = 0

    /// Total frames written since start (for duration tracking)
    private var totalFramesWritten: Int64 = 0

    /// Whether the buffer is actively capturing
    private var _isCapturing: Bool = false
    public var isCapturing: Bool { _isCapturing }

    /// Lock for state changes (not used on audio thread — audio thread is lock-free)
    private let stateLock = NSLock()

    // MARK: - Level Metering

    /// Current input level (0-1 range, for UI display)
    private var _inputLevel: (left: Float, right: Float) = (0, 0)
    public var inputLevel: (left: Float, right: Float) { _inputLevel }

    /// Publisher for input level updates
    public let inputLevelSubject = PassthroughSubject<(left: Float, right: Float), Never>()

    // MARK: - Capture Markers

    /// Marked positions in the buffer (for star/bookmark feature)
    private var markers: [CaptureMarker] = []

    // MARK: - Initialization

    /// Initialize the rolling capture buffer
    /// - Parameters:
    ///   - maxDuration: Maximum buffer duration in seconds (default 300 = 5 minutes)
    ///   - sampleRate: Audio sample rate (default 48000)
    ///   - channelCount: Number of audio channels (default 2 for stereo)
    public init(maxDuration: TimeInterval = 300, sampleRate: Double = 48000, channelCount: Int = 2) {
        self.maxDuration = maxDuration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.capacityInFrames = Int(maxDuration * sampleRate)

        // Allocate buffer: frames * channels
        // At 48kHz stereo, 5 minutes = 48000 * 300 * 2 * 4 bytes = ~115 MB
        let totalSamples = capacityInFrames * channelCount
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: totalSamples)
        self.buffer.initialize(repeating: 0, count: totalSamples)
    }

    deinit {
        let totalSamples = capacityInFrames * channelCount
        buffer.deinitialize(count: totalSamples)
        buffer.deallocate()
    }

    // MARK: - Capture Control

    /// Start capturing audio to the buffer
    public func startCapturing() {
        stateLock.lock()
        _isCapturing = true
        stateLock.unlock()
    }

    /// Stop capturing audio
    public func stopCapturing() {
        stateLock.lock()
        _isCapturing = false
        stateLock.unlock()
    }

    /// Reset the buffer (clear all data)
    public func reset() {
        stateLock.lock()
        _isCapturing = false
        writePosition = 0
        totalFramesWritten = 0
        markers.removeAll()
        let totalSamples = capacityInFrames * channelCount
        buffer.initialize(repeating: 0, count: totalSamples)
        stateLock.unlock()
    }

    // MARK: - Audio Thread Write (lock-free)

    /// Write audio samples into the ring buffer
    /// Called from the audio render callback — must be lock-free and real-time safe
    /// - Parameters:
    ///   - audioBuffer: The audio buffer to write from
    ///   - frameCount: Number of frames to write
    public func writeFromAudioBuffer(_ audioBuffer: UnsafePointer<UnsafePointer<Float>?>, frameCount: Int) {
        guard _isCapturing else { return }

        // Calculate ring buffer index
        let startFrame = Int(writePosition % Int64(capacityInFrames))

        // Write interleaved samples
        for frame in 0..<frameCount {
            let ringFrame = (startFrame + frame) % capacityInFrames
            let baseIndex = ringFrame * channelCount

            for channel in 0..<channelCount {
                if let channelData = audioBuffer[channel] {
                    buffer[baseIndex + channel] = channelData[frame]
                } else {
                    buffer[baseIndex + channel] = 0
                }
            }
        }

        // Update metering (simple peak detection)
        var peakLeft: Float = 0
        var peakRight: Float = 0
        if let leftData = audioBuffer[0] {
            for i in 0..<frameCount {
                peakLeft = max(peakLeft, abs(leftData[i]))
            }
        }
        if channelCount > 1, let rightData = audioBuffer[1] {
            for i in 0..<frameCount {
                peakRight = max(peakRight, abs(rightData[i]))
            }
        } else {
            peakRight = peakLeft
        }
        _inputLevel = (left: peakLeft, right: peakRight)

        // Advance write position
        writePosition += Int64(frameCount)
        totalFramesWritten += Int64(frameCount)
    }

    /// Write from an AVAudioPCMBuffer (convenience for AVAudioEngine tap)
    public func writeFromPCMBuffer(_ pcmBuffer: AVAudioPCMBuffer) {
        guard _isCapturing else { return }
        guard let floatData = pcmBuffer.floatChannelData else { return }

        let frameCount = Int(pcmBuffer.frameLength)
        let bufferChannels = Int(pcmBuffer.format.channelCount)

        let startFrame = Int(writePosition % Int64(capacityInFrames))

        for frame in 0..<frameCount {
            let ringFrame = (startFrame + frame) % capacityInFrames
            let baseIndex = ringFrame * channelCount

            for channel in 0..<min(channelCount, bufferChannels) {
                buffer[baseIndex + channel] = floatData[channel][frame]
            }
        }

        // Update metering
        var peakLeft: Float = 0
        var peakRight: Float = 0
        for i in 0..<frameCount {
            peakLeft = max(peakLeft, abs(floatData[0][i]))
        }
        if bufferChannels > 1 {
            for i in 0..<frameCount {
                peakRight = max(peakRight, abs(floatData[1][i]))
            }
        } else {
            peakRight = peakLeft
        }
        _inputLevel = (left: peakLeft, right: peakRight)

        writePosition += Int64(frameCount)
        totalFramesWritten += Int64(frameCount)
    }

    // MARK: - Extract Audio

    /// How many seconds of audio are currently available in the buffer
    public var availableDuration: TimeInterval {
        let framesAvailable = min(totalFramesWritten, Int64(capacityInFrames))
        return TimeInterval(framesAvailable) / sampleRate
    }

    /// Extract the last N seconds from the buffer as an AVAudioPCMBuffer
    /// - Parameter seconds: Number of seconds to extract
    /// - Returns: PCM buffer with the extracted audio, or nil if not enough data
    public func extractLast(seconds: TimeInterval) -> AVAudioPCMBuffer? {
        let framesToExtract = min(Int(seconds * sampleRate), Int(min(totalFramesWritten, Int64(capacityInFrames))))
        guard framesToExtract > 0 else { return nil }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount))!
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesToExtract)) else {
            return nil
        }
        outputBuffer.frameLength = AVAudioFrameCount(framesToExtract)

        guard let floatData = outputBuffer.floatChannelData else { return nil }

        // Calculate start position in ring buffer
        let currentWrite = writePosition
        let startFrame = Int((currentWrite - Int64(framesToExtract)) % Int64(capacityInFrames))
        let adjustedStart = startFrame < 0 ? startFrame + capacityInFrames : startFrame

        // Copy from ring buffer to output
        for frame in 0..<framesToExtract {
            let ringFrame = (adjustedStart + frame) % capacityInFrames
            let baseIndex = ringFrame * channelCount

            for channel in 0..<channelCount {
                floatData[channel][frame] = buffer[baseIndex + channel]
            }
        }

        return outputBuffer
    }

    /// Extract the last N seconds and save directly to a file
    /// - Parameters:
    ///   - seconds: Duration to extract
    ///   - url: File URL to save to
    ///   - format: Audio file format settings
    /// - Returns: True if save was successful
    public func saveLastToFile(seconds: TimeInterval, url: URL, settings: [String: Any]? = nil) throws -> Bool {
        guard let pcmBuffer = extractLast(seconds: seconds) else {
            return false
        }

        let format = pcmBuffer.format
        let outputSettings = settings ?? [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try audioFile.write(from: pcmBuffer)
        return true
    }

    // MARK: - Markers

    /// Mark the current buffer position (for star/bookmark)
    @discardableResult
    public func markCurrentPosition(name: String? = nil) -> CaptureMarker {
        let marker = CaptureMarker(
            id: UUID(),
            framePosition: writePosition,
            timestamp: Date(),
            name: name
        )
        stateLock.lock()
        markers.append(marker)
        stateLock.unlock()
        return marker
    }

    /// Get all markers within the current buffer window
    public var currentMarkers: [CaptureMarker] {
        stateLock.lock()
        defer { stateLock.unlock() }
        let oldestFrame = writePosition - Int64(capacityInFrames)
        return markers.filter { $0.framePosition > oldestFrame }
    }

    // MARK: - Waveform Data

    /// Generate waveform preview data from the last N seconds
    /// Returns an array of peak values suitable for waveform display
    public func generateWaveformPreview(seconds: TimeInterval, sampleCount: Int = 256) -> [Float] {
        guard let pcmBuffer = extractLast(seconds: seconds),
              let floatData = pcmBuffer.floatChannelData else {
            return Array(repeating: 0, count: sampleCount)
        }

        let totalFrames = Int(pcmBuffer.frameLength)
        let framesPerSample = max(1, totalFrames / sampleCount)
        var waveform: [Float] = []

        for i in 0..<sampleCount {
            let start = i * framesPerSample
            let end = min(start + framesPerSample, totalFrames)
            var peak: Float = 0

            for frame in start..<end {
                for channel in 0..<channelCount {
                    peak = max(peak, abs(floatData[channel][frame]))
                }
            }
            waveform.append(peak)
        }

        return waveform
    }
}

// MARK: - Capture Marker

/// A marked position within the rolling capture buffer
public struct CaptureMarker: Identifiable, Sendable {
    public let id: UUID
    public let framePosition: Int64
    public let timestamp: Date
    public var name: String?
}
