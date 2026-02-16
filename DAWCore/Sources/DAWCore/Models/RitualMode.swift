import Foundation

// MARK: - Ritual Mode

/// The operating mode of the Ritual DAW
/// Each mode provides a focused workflow with specific constraints and capabilities
public enum RitualMode: String, Codable, Sendable, CaseIterable {
    /// Always-recording capture mode with rolling buffer
    /// Save moments retroactively from the last 5 minutes
    case capture

    /// Live looping mode with per-track loop recording
    /// One-button record/play/overdub per track
    case loop

    /// Texture Canvas mode for ambient layering
    /// Build up atmospheric soundscapes with auto-fading layers
    case layer

    /// Locked-down performance mode with scene navigation
    /// Keyboard/mouse locked, large high-contrast display
    case perform

    /// Traditional DAW mode (escape hatch)
    /// Unlocks unlimited tracks, full automation, MIDI editing
    case studio

    /// Display name for the mode
    public var displayName: String {
        switch self {
        case .capture: return "Capture"
        case .loop: return "Loop"
        case .layer: return "Layer"
        case .perform: return "Perform"
        case .studio: return "Studio"
        }
    }

    /// Short description of the mode
    public var description: String {
        switch self {
        case .capture: return "Always recording. Save moments."
        case .loop: return "Build loops in real time."
        case .layer: return "Ambient texture canvas."
        case .perform: return "Locked for live performance."
        case .studio: return "Full DAW capabilities."
        }
    }

    /// SF Symbol icon for the mode
    public var icon: String {
        switch self {
        case .capture: return "record.circle"
        case .loop: return "repeat"
        case .layer: return "square.3.layers.3d"
        case .perform: return "theatermasks"
        case .studio: return "slider.horizontal.3"
        }
    }

    /// Whether this mode enforces the 8-track limit
    public var enforcesTrackLimit: Bool {
        self != .studio
    }

    /// Maximum number of tracks allowed in this mode
    public var maxTracks: Int {
        enforcesTrackLimit ? 8 : Int.max
    }

    /// Performance modes (all except studio)
    public static var performanceModes: [RitualMode] {
        [.capture, .loop, .layer, .perform]
    }

    /// Whether this mode is a performance mode
    public var isPerformanceMode: Bool {
        self != .studio
    }
}
