import Foundation
import AVFoundation
import Accelerate

// MARK: - Audio Analyzer

/// Analyzes audio for BPM detection, key estimation, and waveform generation
/// Uses DSP techniques: onset detection, autocorrelation, chromagram analysis
public final class AudioAnalyzer: Sendable {

    // MARK: - BPM Detection

    /// Detect the tempo (BPM) of an audio buffer using onset detection + autocorrelation
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: Estimated BPM, or nil if detection failed
    public static func detectBPM(from buffer: AVAudioPCMBuffer) -> Double? {
        guard let floatData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard frameCount > Int(sampleRate * 2) else { return nil }  // Need at least 2 seconds

        // Mix to mono if stereo
        let mono = mixToMono(floatData, frameCount: frameCount, channelCount: Int(buffer.format.channelCount))

        // Step 1: Compute spectral flux (onset detection function)
        let hopSize = 512
        let fftSize = 1024
        let onsetSignal = computeSpectralFlux(mono, frameCount: frameCount, fftSize: fftSize, hopSize: hopSize)
        guard onsetSignal.count > 10 else { return nil }

        // Step 2: Autocorrelation of onset signal
        let onsetRate = sampleRate / Double(hopSize)
        let minBPM: Double = 60
        let maxBPM: Double = 200
        let minLag = Int(onsetRate * 60.0 / maxBPM)
        let maxLag = min(Int(onsetRate * 60.0 / minBPM), onsetSignal.count / 2)
        guard minLag < maxLag else { return nil }

        var autocorrelation = [Float](repeating: 0, count: maxLag - minLag)

        for lag in minLag..<maxLag {
            var sum: Float = 0
            let count = onsetSignal.count - lag
            for i in 0..<count {
                sum += onsetSignal[i] * onsetSignal[i + lag]
            }
            autocorrelation[lag - minLag] = sum / Float(count)
        }

        // Step 3: Find the peak in the autocorrelation
        guard let maxIndex = autocorrelation.indices.max(by: { autocorrelation[$0] < autocorrelation[$1] }) else {
            return nil
        }

        let bestLag = maxIndex + minLag
        let bpm = (onsetRate * 60.0) / Double(bestLag)

        // Validate: BPM should be in a reasonable range
        guard bpm >= minBPM && bpm <= maxBPM else { return nil }

        return round(bpm * 10) / 10  // Round to 1 decimal
    }

    /// Detect BPM from a file URL
    public static func detectBPM(from url: URL) async -> Double? {
        guard let buffer = loadAudioBuffer(from: url) else { return nil }
        return detectBPM(from: buffer)
    }

    // MARK: - Key Detection

    /// Estimate the musical key of an audio buffer using chromagram analysis
    /// Uses the Krumhansl-Schmuckler key-finding algorithm
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: Estimated key string (e.g., "C major", "A minor"), or nil
    public static func detectKey(from buffer: AVAudioPCMBuffer) -> String? {
        guard let floatData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        guard frameCount > Int(sampleRate) else { return nil }  // Need at least 1 second

        let mono = mixToMono(floatData, frameCount: frameCount, channelCount: Int(buffer.format.channelCount))

        // Compute chromagram (12 pitch classes)
        let chromagram = computeChromagram(mono, frameCount: frameCount, sampleRate: sampleRate)

        // Krumhansl-Schmuckler key profiles
        let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let noteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

        var bestCorrelation: Float = -Float.infinity
        var bestKey = ""

        // Test all 24 major and minor keys
        for root in 0..<12 {
            // Rotate chromagram to align with root
            var rotated = [Float](repeating: 0, count: 12)
            for i in 0..<12 {
                rotated[i] = chromagram[(i + root) % 12]
            }

            // Correlate with major profile
            let majorCorr = pearsonCorrelation(rotated, majorProfile)
            if majorCorr > bestCorrelation {
                bestCorrelation = majorCorr
                bestKey = "\(noteNames[root]) major"
            }

            // Correlate with minor profile
            let minorCorr = pearsonCorrelation(rotated, minorProfile)
            if minorCorr > bestCorrelation {
                bestCorrelation = minorCorr
                bestKey = "\(noteNames[root]) minor"
            }
        }

        // Require a minimum correlation threshold
        guard bestCorrelation > 0.3 else { return nil }

        return bestKey
    }

    /// Detect key from a file URL
    public static func detectKey(from url: URL) async -> String? {
        guard let buffer = loadAudioBuffer(from: url) else { return nil }
        return detectKey(from: buffer)
    }

    // MARK: - Full Analysis

    /// Perform complete analysis on an audio file
    public struct AnalysisResult: Sendable {
        public var bpm: Double?
        public var key: String?
        public var waveform: [Float]
        public var peakLevel: Float
        public var duration: TimeInterval
    }

    /// Analyze an audio file completely (BPM, key, waveform)
    public static func analyzeFile(at url: URL, waveformSampleCount: Int = 256) async -> AnalysisResult? {
        guard let buffer = loadAudioBuffer(from: url) else { return nil }

        let bpm = detectBPM(from: buffer)
        let key = detectKey(from: buffer)
        let waveform = generateWaveform(from: buffer, sampleCount: waveformSampleCount)
        let peak = computePeakLevel(from: buffer)
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate

        return AnalysisResult(
            bpm: bpm,
            key: key,
            waveform: waveform,
            peakLevel: peak,
            duration: duration
        )
    }

    // MARK: - Waveform Generation

    /// Generate waveform preview data from an audio buffer
    public static func generateWaveform(from buffer: AVAudioPCMBuffer, sampleCount: Int = 256) -> [Float] {
        guard let floatData = buffer.floatChannelData else {
            return Array(repeating: 0, count: sampleCount)
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let framesPerSample = max(1, frameCount / sampleCount)
        var waveform: [Float] = []

        for i in 0..<sampleCount {
            let start = i * framesPerSample
            let end = min(start + framesPerSample, frameCount)
            var peak: Float = 0

            for frame in start..<end {
                for ch in 0..<channelCount {
                    peak = max(peak, abs(floatData[ch][frame]))
                }
            }
            waveform.append(peak)
        }

        return waveform
    }

    /// Generate waveform from a file URL
    public static func generateWaveform(from url: URL, sampleCount: Int = 256) async -> [Float] {
        guard let buffer = loadAudioBuffer(from: url) else {
            return Array(repeating: 0, count: sampleCount)
        }
        return generateWaveform(from: buffer, sampleCount: sampleCount)
    }

    // MARK: - Private Helpers

    /// Load an audio file into a PCM buffer
    private static func loadAudioBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        do {
            try audioFile.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    /// Mix multi-channel audio to mono
    private static func mixToMono(_ channelData: UnsafePointer<UnsafeMutablePointer<Float>>, frameCount: Int, channelCount: Int) -> [Float] {
        var mono = [Float](repeating: 0, count: frameCount)
        let scale = 1.0 / Float(channelCount)

        for ch in 0..<channelCount {
            for i in 0..<frameCount {
                mono[i] += channelData[ch][i] * scale
            }
        }

        return mono
    }

    /// Compute spectral flux (onset detection function)
    private static func computeSpectralFlux(_ signal: [Float], frameCount: Int, fftSize: Int, hopSize: Int) -> [Float] {
        let halfFFT = fftSize / 2
        var flux: [Float] = []
        var prevMagnitudes = [Float](repeating: 0, count: halfFFT)

        // Setup vDSP FFT
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var position = 0
        while position + fftSize <= frameCount {
            // Apply window
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(Array(signal[position..<position + fftSize]), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            // FFT
            var realPart = [Float](repeating: 0, count: halfFFT)
            var imagPart = [Float](repeating: 0, count: halfFFT)
            windowed.withUnsafeMutableBufferPointer { windowedPtr in
                realPart.withUnsafeMutableBufferPointer { realPtr in
                    imagPart.withUnsafeMutableBufferPointer { imagPtr in
                        var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                        windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfFFT))
                        }
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                        // Compute magnitudes
                        var magnitudes = [Float](repeating: 0, count: halfFFT)
                        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFT))

                        // Spectral flux: sum of positive differences
                        var fluxValue: Float = 0
                        for i in 0..<halfFFT {
                            let diff = magnitudes[i] - prevMagnitudes[i]
                            if diff > 0 {
                                fluxValue += diff
                            }
                        }
                        flux.append(fluxValue)
                        prevMagnitudes = magnitudes
                    }
                }
            }

            position += hopSize
        }

        return flux
    }

    /// Compute chromagram (12-bin pitch class distribution)
    private static func computeChromagram(_ signal: [Float], frameCount: Int, sampleRate: Double) -> [Float] {
        var chroma = [Float](repeating: 0, count: 12)
        let fftSize = 4096
        let hopSize = 2048

        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return chroma
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        let halfFFT = fftSize / 2
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var frameCountProcessed = 0
        var position = 0

        while position + fftSize <= frameCount {
            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(Array(signal[position..<position + fftSize]), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            var realPart = [Float](repeating: 0, count: halfFFT)
            var imagPart = [Float](repeating: 0, count: halfFFT)
            windowed.withUnsafeMutableBufferPointer { windowedPtr in
                realPart.withUnsafeMutableBufferPointer { realPtr in
                    imagPart.withUnsafeMutableBufferPointer { imagPtr in
                        var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                        windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfFFT))
                        }
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                        var magnitudes = [Float](repeating: 0, count: halfFFT)
                        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFT))

                        // Map FFT bins to pitch classes
                        for bin in 1..<halfFFT {
                            let frequency = Double(bin) * sampleRate / Double(fftSize)
                            guard frequency > 20 && frequency < 5000 else { continue }

                            // Convert frequency to MIDI note, then to pitch class
                            let midiNote = 69.0 + 12.0 * log2(frequency / 440.0)
                            let pitchClass = Int(round(midiNote)) % 12
                            let adjustedPC = pitchClass < 0 ? pitchClass + 12 : pitchClass

                            chroma[adjustedPC] += magnitudes[bin] * magnitudes[bin]  // Energy weighting
                        }
                    }
                }
            }

            position += hopSize
            frameCountProcessed += 1
        }

        // Normalize
        if frameCountProcessed > 0 {
            let scale = 1.0 / Float(frameCountProcessed)
            for i in 0..<12 {
                chroma[i] *= scale
            }
        }

        // Normalize to sum = 1
        let total = chroma.reduce(0, +)
        if total > 0 {
            for i in 0..<12 {
                chroma[i] /= total
            }
        }

        return chroma
    }

    /// Pearson correlation between two arrays
    private static func pearsonCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        guard x.count == y.count, !x.isEmpty else { return 0 }
        let n = Float(x.count)

        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let meanX = sumX / n
        let meanY = sumY / n

        var numerator: Float = 0
        var denomX: Float = 0
        var denomY: Float = 0

        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            numerator += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }

        let denom = sqrt(denomX * denomY)
        guard denom > 0 else { return 0 }

        return numerator / denom
    }

    /// Compute peak level of a buffer
    private static func computePeakLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        for ch in 0..<channelCount {
            for i in 0..<frameCount {
                peak = max(peak, abs(floatData[ch][i]))
            }
        }

        return peak
    }
}
