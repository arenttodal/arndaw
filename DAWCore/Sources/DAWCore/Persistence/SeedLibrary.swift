import Foundation
import Combine

// MARK: - Seed Library

/// Manages the persistent collection of captured audio seeds
/// Seeds are stored as audio files with a JSON metadata index
///
/// Storage structure:
/// ~/Music/Ritual Seeds/
/// ├── library.json
/// ├── audio/
/// │   └── {uuid}.wav
/// └── waveforms/
///     └── {uuid}.json
@MainActor
public final class SeedLibrary: ObservableObject {

    // MARK: - Published State

    @Published public var seeds: [Seed] = []
    @Published public var isLoading: Bool = false
    @Published public var lastError: String?

    // MARK: - Configuration

    /// Root directory for the seed library
    public let libraryURL: URL

    /// Audio files directory
    public var audioDirectoryURL: URL {
        libraryURL.appendingPathComponent("audio")
    }

    /// Metadata index file
    private var metadataFileURL: URL {
        libraryURL.appendingPathComponent("library.json")
    }

    /// Counter for auto-naming
    private var sequenceCounter: Int = 0

    /// The exporter for saving audio
    private let exporter = InstantExporter()

    // MARK: - Initialization

    public init(libraryURL: URL? = nil) {
        if let url = libraryURL {
            self.libraryURL = url
        } else {
            // Default: ~/Music/Ritual Seeds/
            let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
            self.libraryURL = musicDir.appendingPathComponent("Ritual Seeds")
        }
    }

    // MARK: - Library Lifecycle

    /// Load the seed library from disk
    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Ensure directories exist
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)

            // Load metadata
            if FileManager.default.fileExists(atPath: metadataFileURL.path) {
                let data = try Data(contentsOf: metadataFileURL)
                let library = try JSONDecoder().decode(SeedLibraryData.self, from: data)
                seeds = library.seeds
                sequenceCounter = library.sequenceCounter
            }
        } catch {
            lastError = "Failed to load seed library: \(error.localizedDescription)"
            print("[SeedLibrary] Load error: \(error)")
        }
    }

    /// Save the seed library metadata to disk
    public func save() async {
        do {
            let library = SeedLibraryData(seeds: seeds, sequenceCounter: sequenceCounter)
            let data = try JSONEncoder().encode(library)
            try data.write(to: metadataFileURL)
        } catch {
            lastError = "Failed to save seed library: \(error.localizedDescription)"
            print("[SeedLibrary] Save error: \(error)")
        }
    }

    // MARK: - Seed Management

    /// Save a new seed from the capture buffer
    /// - Parameters:
    ///   - captureBuffer: The rolling capture buffer to extract from
    ///   - seconds: How many seconds to save
    ///   - starred: Whether to immediately star this seed
    /// - Returns: The created seed
    @discardableResult
    public func saveSeed(
        from captureBuffer: RollingCaptureBuffer,
        seconds: TimeInterval,
        starred: Bool = false,
        sessionName: String? = nil
    ) async throws -> Seed {
        sequenceCounter += 1
        let seedID = UUID()
        let name = Seed.autoName(date: Date(), sequenceNumber: sequenceCounter)

        // Export audio from capture buffer
        let result = try await exporter.exportSeed(
            from: captureBuffer,
            seconds: seconds,
            seedLibraryAudioDir: audioDirectoryURL,
            seedID: seedID
        )

        // Create seed model
        var seed = Seed(
            id: seedID,
            name: name,
            createdAt: Date(),
            duration: seconds,
            audioFileName: "\(seedID.uuidString).wav",
            waveformSamples: result.waveform,
            isStarred: starred,
            captureSource: .rollingBuffer,
            captureDurationRequested: seconds,
            sessionName: sessionName
        )

        // Run audio analysis in background
        let audioURL = result.url
        let analysis = await AudioAnalyzer.analyzeFile(at: audioURL, waveformSampleCount: 256)
        seed.detectedBPM = analysis?.bpm
        seed.detectedKey = analysis?.key
        seed.duration = analysis?.duration ?? seconds

        // Add to library
        seeds.insert(seed, at: 0)  // Newest first
        await save()

        return seed
    }

    /// Add an existing audio file as a seed
    @discardableResult
    public func importSeed(from fileURL: URL, name: String? = nil) async throws -> Seed {
        sequenceCounter += 1
        let seedID = UUID()

        // Copy file to library
        let destURL = audioDirectoryURL.appendingPathComponent("\(seedID.uuidString).wav")
        try FileManager.default.copyItem(at: fileURL, to: destURL)

        // Analyze
        let analysis = await AudioAnalyzer.analyzeFile(at: destURL, waveformSampleCount: 256)

        let seed = Seed(
            id: seedID,
            name: name ?? fileURL.deletingPathExtension().lastPathComponent,
            createdAt: Date(),
            duration: analysis?.duration ?? 0,
            audioFileName: "\(seedID.uuidString).wav",
            detectedBPM: analysis?.bpm,
            detectedKey: analysis?.key,
            waveformSamples: analysis?.waveform,
            captureSource: .audioImport,
            captureDurationRequested: analysis?.duration ?? 0
        )

        seeds.insert(seed, at: 0)
        await save()

        return seed
    }

    /// Remove a seed from the library
    public func removeSeed(id: UUID) async {
        guard let seed = seeds.first(where: { $0.id == id }) else { return }

        // Delete audio file
        let audioURL = audioDirectoryURL.appendingPathComponent(seed.audioFileName)
        try? FileManager.default.removeItem(at: audioURL)

        // Remove from list
        seeds.removeAll { $0.id == id }
        await save()
    }

    /// Update seed metadata (star, tags, rating, etc.)
    public func updateSeed(_ updatedSeed: Seed) async {
        if let index = seeds.firstIndex(where: { $0.id == updatedSeed.id }) {
            seeds[index] = updatedSeed
            await save()
        }
    }

    /// Toggle star on a seed
    public func toggleStar(id: UUID) async {
        if let index = seeds.firstIndex(where: { $0.id == id }) {
            seeds[index].isStarred.toggle()
            await save()
        }
    }

    /// Get the audio file URL for a seed
    public func audioURL(for seed: Seed) -> URL {
        audioDirectoryURL.appendingPathComponent(seed.audioFileName)
    }

    // MARK: - Filtering

    /// Get seeds matching a filter
    public func filteredSeeds(_ filter: SeedFilter, sortedBy order: SeedSortOrder = .newestFirst) -> [Seed] {
        var result = seeds.filter { filter.matches($0) }

        switch order {
        case .newestFirst:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            result.sort { $0.createdAt < $1.createdAt }
        case .nameAZ:
            result.sort { $0.name < $1.name }
        case .nameZA:
            result.sort { $0.name > $1.name }
        case .longestFirst:
            result.sort { $0.duration > $1.duration }
        case .shortestFirst:
            result.sort { $0.duration < $1.duration }
        case .bpmLowHigh:
            result.sort { ($0.detectedBPM ?? 0) < ($1.detectedBPM ?? 0) }
        case .bpmHighLow:
            result.sort { ($0.detectedBPM ?? 0) > ($1.detectedBPM ?? 0) }
        case .ratingHighLow:
            result.sort { $0.rating > $1.rating }
        }

        return result
    }
}

// MARK: - Persistence Model

/// Internal model for JSON serialization of the seed library
private struct SeedLibraryData: Codable {
    var seeds: [Seed]
    var sequenceCounter: Int
}
