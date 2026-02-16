import Foundation
import AVFoundation

// MARK: - Export Format

/// Supported audio export formats
public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case wav
    case mp3
    case aac
    case flac

    public var fileExtension: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .wav: return "WAV (Lossless)"
        case .mp3: return "MP3 (320 kbps)"
        case .aac: return "AAC (256 kbps)"
        case .flac: return "FLAC (Lossless)"
        }
    }

    public var mimeType: String {
        switch self {
        case .wav: return "audio/wav"
        case .mp3: return "audio/mpeg"
        case .aac: return "audio/aac"
        case .flac: return "audio/flac"
        }
    }
}

// MARK: - Instant Exporter

/// Handles fast audio export from capture buffer to various formats
/// Designed for near-instant saving of captured audio moments
public actor InstantExporter {

    // MARK: - Export from PCM Buffer

    /// Export a PCM buffer to a file in the specified format
    /// - Parameters:
    ///   - buffer: Audio data to export
    ///   - url: Destination file URL
    ///   - format: Output format
    /// - Returns: The URL of the exported file
    public func export(buffer: AVAudioPCMBuffer, to url: URL, format: ExportFormat) async throws -> URL {
        switch format {
        case .wav:
            return try exportWAV(buffer: buffer, to: url)
        case .mp3, .aac:
            return try await exportCompressed(buffer: buffer, to: url, format: format)
        case .flac:
            return try exportWAV(buffer: buffer, to: url)  // FLAC via AVAudioFile not natively supported; save as WAV
        }
    }

    /// Export a PCM buffer to WAV (fastest path)
    private func exportWAV(buffer: AVAudioPCMBuffer, to url: URL) throws -> URL {
        let wavURL = url.deletingPathExtension().appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let audioFile = try AVAudioFile(
            forWriting: wavURL,
            settings: settings,
            commonFormat: buffer.format.commonFormat,
            interleaved: buffer.format.isInterleaved
        )
        try audioFile.write(from: buffer)

        return wavURL
    }

    /// Export to compressed format using AVAssetWriter
    private func exportCompressed(buffer: AVAudioPCMBuffer, to url: URL, format: ExportFormat) async throws -> URL {
        // First export to WAV, then convert
        let tempDir = FileManager.default.temporaryDirectory
        let tempWAV = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        let wavURL = try exportWAV(buffer: buffer, to: tempWAV)

        defer {
            try? FileManager.default.removeItem(at: wavURL)
        }

        let outputURL: URL
        let outputSettings: [String: Any]

        switch format {
        case .mp3:
            // macOS doesn't natively support MP3 encoding via AVFoundation
            // Fall back to AAC in an M4A container, which is universally supported
            outputURL = url.deletingPathExtension().appendingPathExtension("m4a")
            outputSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVEncoderBitRateKey: 320000
            ]
        case .aac:
            outputURL = url.deletingPathExtension().appendingPathExtension("m4a")
            outputSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVEncoderBitRateKey: 256000
            ]
        default:
            return wavURL
        }

        // Use AVAudioFile for conversion
        let sourceFile = try AVAudioFile(forReading: wavURL)
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: 4096
        )!

        while sourceFile.framePosition < sourceFile.length {
            try sourceFile.read(into: conversionBuffer)
            try outputFile.write(from: conversionBuffer)
        }

        return outputURL
    }

    // MARK: - Export from Capture Buffer

    /// Export directly from a RollingCaptureBuffer
    /// - Parameters:
    ///   - captureBuffer: The rolling capture buffer
    ///   - seconds: Number of seconds to export
    ///   - destinationDir: Directory to save the file in
    ///   - name: Filename (without extension)
    ///   - format: Output format
    /// - Returns: The URL of the exported file, or nil if buffer was empty
    public func exportFromCaptureBuffer(
        _ captureBuffer: RollingCaptureBuffer,
        seconds: TimeInterval,
        destinationDir: URL,
        name: String,
        format: ExportFormat
    ) async throws -> URL? {
        guard let pcmBuffer = captureBuffer.extractLast(seconds: seconds) else {
            return nil
        }

        // Ensure directory exists
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let fileURL = destinationDir.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        return try await export(buffer: pcmBuffer, to: fileURL, format: format)
    }

    // MARK: - Quick Export (Seed Library)

    /// Export a capture to the seed library with auto-generated filename
    /// Returns both the file URL and analysis results
    public func exportSeed(
        from captureBuffer: RollingCaptureBuffer,
        seconds: TimeInterval,
        seedLibraryAudioDir: URL,
        seedID: UUID
    ) async throws -> (url: URL, waveform: [Float]) {
        guard let pcmBuffer = captureBuffer.extractLast(seconds: seconds) else {
            throw ExportError.emptyBuffer
        }

        // Save as WAV for lossless quality in the library
        let fileURL = seedLibraryAudioDir.appendingPathComponent("\(seedID.uuidString).wav")

        try FileManager.default.createDirectory(at: seedLibraryAudioDir, withIntermediateDirectories: true)

        let savedURL = try exportWAV(buffer: pcmBuffer, to: fileURL)

        // Generate waveform preview
        let waveform = AudioAnalyzer.generateWaveform(from: pcmBuffer, sampleCount: 256)

        return (url: savedURL, waveform: waveform)
    }
}

// MARK: - Export Error

public enum ExportError: Error, LocalizedError {
    case emptyBuffer
    case encodingFailed
    case fileWriteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyBuffer: return "Capture buffer is empty"
        case .encodingFailed: return "Audio encoding failed"
        case .fileWriteFailed(let error): return "File write failed: \(error.localizedDescription)"
        }
    }
}
