import Foundation

// MARK: - Scene

/// A scene captures the state of all tracks for instant recall during performance
/// Scenes are used in Perform Mode to switch between different arrangements
public struct Scene: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var trackStates: [String: TrackSceneState]  // TrackID.rawValue.uuidString -> state
    public var canvasVolume: Float?       // nil = no change to texture canvas
    public var tempoOverride: Double?     // nil = no tempo change
    public var transitionDuration: Double  // In beats, for crossfading between scenes
    public var color: TrackColor

    public init(
        id: UUID = UUID(),
        name: String = "Scene",
        trackStates: [String: TrackSceneState] = [:],
        canvasVolume: Float? = nil,
        tempoOverride: Double? = nil,
        transitionDuration: Double = 4.0,
        color: TrackColor = .blue
    ) {
        self.id = id
        self.name = name
        self.trackStates = trackStates
        self.canvasVolume = canvasVolume
        self.tempoOverride = tempoOverride
        self.transitionDuration = transitionDuration
        self.color = color
    }

    /// Get the state for a specific track
    public func state(for trackID: TrackID) -> TrackSceneState? {
        trackStates[trackID.rawValue.uuidString]
    }

    /// Set the state for a specific track
    public mutating func setState(_ state: TrackSceneState, for trackID: TrackID) {
        trackStates[trackID.rawValue.uuidString] = state
    }
}

// MARK: - Track Scene State

/// The state of a single track within a scene
public struct TrackSceneState: Codable, Sendable {
    public var isPlaying: Bool
    public var isMuted: Bool
    public var volume: Float?      // nil = no change from current volume
    public var pan: Float?         // nil = no change from current pan

    public init(
        isPlaying: Bool = true,
        isMuted: Bool = false,
        volume: Float? = nil,
        pan: Float? = nil
    ) {
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.volume = volume
        self.pan = pan
    }
}

// MARK: - Scene List

/// Ordered collection of scenes for a project
public struct SceneList: Codable, Sendable {
    public var scenes: [Scene]
    public var activeSceneIndex: Int?

    public init(scenes: [Scene] = [], activeSceneIndex: Int? = nil) {
        self.scenes = scenes
        self.activeSceneIndex = activeSceneIndex
    }

    /// Currently active scene
    public var activeScene: Scene? {
        guard let index = activeSceneIndex, scenes.indices.contains(index) else {
            return nil
        }
        return scenes[index]
    }

    /// Advance to the next scene
    public mutating func nextScene() {
        guard !scenes.isEmpty else { return }
        if let current = activeSceneIndex {
            activeSceneIndex = min(current + 1, scenes.count - 1)
        } else {
            activeSceneIndex = 0
        }
    }

    /// Go to the previous scene
    public mutating func previousScene() {
        guard !scenes.isEmpty else { return }
        if let current = activeSceneIndex {
            activeSceneIndex = max(current - 1, 0)
        } else {
            activeSceneIndex = scenes.count - 1
        }
    }

    /// Add a new scene
    public mutating func addScene(_ scene: Scene) {
        scenes.append(scene)
    }

    /// Remove a scene by ID
    public mutating func removeScene(id: UUID) {
        scenes.removeAll { $0.id == id }
        // Adjust active index if needed
        if let index = activeSceneIndex {
            if scenes.isEmpty {
                activeSceneIndex = nil
            } else if index >= scenes.count {
                activeSceneIndex = scenes.count - 1
            }
        }
    }
}
