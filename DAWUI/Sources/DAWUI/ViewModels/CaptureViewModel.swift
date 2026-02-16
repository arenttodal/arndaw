import Foundation
import SwiftUI
import Combine
import AVFoundation
import DAWCore

// MARK: - Capture View Model

/// Manages the state and logic for Capture Mode
/// Coordinates the rolling capture buffer, seed library, and UI state
@MainActor
public final class CaptureViewModel: ObservableObject {

    // MARK: - Published State

    /// Whether the capture buffer is actively recording
    @Published public var isCapturing: Bool = false

    /// Current input level (left, right) for the level meter
    @Published public var inputLevel: (left: Float, right: Float) = (0, 0)

    /// Duration available in the buffer (up to 5 minutes)
    @Published public var bufferDuration: TimeInterval = 0

    /// Recently saved seeds (most recent first)
    @Published public var recentSeeds: [Seed] = []

    /// Whether a save is currently in progress
    @Published public var isSaving: Bool = false

    /// Feedback message shown after an action
    @Published public var feedbackMessage: String?

    /// Error message if something goes wrong
    @Published public var errorMessage: String?

    // MARK: - Dependencies

    /// The rolling capture buffer (owned by the audio engine layer)
    public var captureBuffer: RollingCaptureBuffer?

    /// The seed library for persisting captures
    public var seedLibrary: SeedLibrary?

    /// Current session name (for tagging seeds)
    public var sessionName: String?

    // MARK: - Internal State

    private var levelUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {}

    // MARK: - Setup

    /// Configure with dependencies
    public func configure(captureBuffer: RollingCaptureBuffer, seedLibrary: SeedLibrary) {
        self.captureBuffer = captureBuffer
        self.seedLibrary = seedLibrary

        // Start monitoring input levels
        startLevelMonitoring()
    }

    // MARK: - Capture Control

    /// Start the rolling capture
    public func startCapture() {
        captureBuffer?.startCapturing()
        isCapturing = true
    }

    /// Stop the rolling capture
    public func stopCapture() {
        captureBuffer?.stopCapturing()
        isCapturing = false
    }

    /// Toggle capture on/off
    public func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    // MARK: - Save Actions

    /// Save the last N seconds from the capture buffer
    /// - Parameters:
    ///   - seconds: Duration to save (30, 60, or 120)
    ///   - starred: Whether to immediately star this seed
    public func saveLast(seconds: TimeInterval, starred: Bool = false) async {
        guard let captureBuffer = captureBuffer, let seedLibrary = seedLibrary else {
            errorMessage = "Capture not configured"
            return
        }

        guard captureBuffer.availableDuration >= seconds else {
            errorMessage = "Not enough audio buffered yet (\(Int(captureBuffer.availableDuration))s available)"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let seed = try await seedLibrary.saveSeed(
                from: captureBuffer,
                seconds: seconds,
                starred: starred,
                sessionName: sessionName
            )

            recentSeeds.insert(seed, at: 0)
            if recentSeeds.count > 20 {
                recentSeeds = Array(recentSeeds.prefix(20))
            }

            let durationStr = seconds >= 60 ? "\(Int(seconds / 60))m" : "\(Int(seconds))s"
            feedbackMessage = "Saved \(durationStr) as \(seed.name)"

            // Auto-clear feedback after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                feedbackMessage = nil
            }
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Quick save with star (mark as important)
    public func markAndSave(seconds: TimeInterval = 30) async {
        await saveLast(seconds: seconds, starred: true)
    }

    /// Toggle star on the most recent seed
    public func toggleStarOnLatest() async {
        guard let latest = recentSeeds.first, let seedLibrary = seedLibrary else { return }
        await seedLibrary.toggleStar(id: latest.id)

        // Update local copy
        if var seed = recentSeeds.first {
            seed.isStarred.toggle()
            recentSeeds[0] = seed
        }
    }

    // MARK: - Level Monitoring

    private func startLevelMonitoring() {
        // Poll capture buffer levels at ~30fps for UI updates
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let buffer = self.captureBuffer else { return }
                self.inputLevel = buffer.inputLevel
                self.bufferDuration = buffer.availableDuration
            }
        }
    }

    /// Stop level monitoring
    public func stopLevelMonitoring() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
    }

    deinit {
        levelUpdateTimer?.invalidate()
    }
}
