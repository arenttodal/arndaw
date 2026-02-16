import Foundation

// MARK: - Track Role

/// Defines the role of a track in Ritual's 8-track system
/// Tracks 1-4 are melodic (swappable), 5-8 have fixed roles
public enum TrackRole: String, Codable, Sendable, CaseIterable {
    // Melodic tracks (1-4) - swappable instruments
    case melodicA   // Track 1
    case melodicB   // Track 2
    case melodicC   // Track 3
    case melodicD   // Track 4

    // Fixed-role tracks (5-8)
    case bass       // Track 5 - always bass
    case drums      // Track 6 - always drums
    case percussion // Track 7 - always percussion
    case groove     // Track 8 - Element Mixer (sub-mixer with 7 sub-tracks)

    /// Display name for the role
    public var displayName: String {
        switch self {
        case .melodicA: return "Melodic A"
        case .melodicB: return "Melodic B"
        case .melodicC: return "Melodic C"
        case .melodicD: return "Melodic D"
        case .bass: return "Bass"
        case .drums: return "Drums"
        case .percussion: return "Percussion"
        case .groove: return "Groove"
        }
    }

    /// Short label for compact UI (track header)
    public var shortLabel: String {
        switch self {
        case .melodicA: return "MEL A"
        case .melodicB: return "MEL B"
        case .melodicC: return "MEL C"
        case .melodicD: return "MEL D"
        case .bass: return "BASS"
        case .drums: return "DRUMS"
        case .percussion: return "PERC"
        case .groove: return "GRV"
        }
    }

    /// Default track number (1-8)
    public var defaultTrackNumber: Int {
        switch self {
        case .melodicA: return 1
        case .melodicB: return 2
        case .melodicC: return 3
        case .melodicD: return 4
        case .bass: return 5
        case .drums: return 6
        case .percussion: return 7
        case .groove: return 8
        }
    }

    /// Whether this role's instrument can be swapped freely
    public var isSwappable: Bool {
        switch self {
        case .melodicA, .melodicB, .melodicC, .melodicD:
            return true
        case .bass, .drums, .percussion, .groove:
            return false
        }
    }

    /// Whether this is a melodic role
    public var isMelodic: Bool {
        switch self {
        case .melodicA, .melodicB, .melodicC, .melodicD:
            return true
        default:
            return false
        }
    }

    /// Default color for this track role
    public var defaultColor: TrackColor {
        switch self {
        case .melodicA: return .blue
        case .melodicB: return .green
        case .melodicC: return .purple
        case .melodicD: return .cyan
        case .bass: return .orange
        case .drums: return .red
        case .percussion: return .yellow
        case .groove: return .pink
        }
    }

    /// Default instrument category for this role
    public var defaultInstrumentCategory: String {
        switch self {
        case .melodicA: return "keys"
        case .melodicB: return "pads"
        case .melodicC: return "synth"
        case .melodicD: return "strings"
        case .bass: return "bass"
        case .drums: return "drums"
        case .percussion: return "percussion"
        case .groove: return "groove"
        }
    }

    /// All melodic roles
    public static var melodicRoles: [TrackRole] {
        [.melodicA, .melodicB, .melodicC, .melodicD]
    }

    /// All fixed roles
    public static var fixedRoles: [TrackRole] {
        [.bass, .drums, .percussion, .groove]
    }
}

// MARK: - Track Role Assignment

/// Maps track IDs to their roles in the 8-track system
public struct TrackRoleAssignment: Codable, Sendable {
    public var assignments: [String: TrackRole]  // TrackID.rawValue.uuidString -> Role

    public init() {
        self.assignments = [:]
    }

    public func role(for trackID: TrackID) -> TrackRole? {
        assignments[trackID.rawValue.uuidString]
    }

    public mutating func assign(role: TrackRole, to trackID: TrackID) {
        assignments[trackID.rawValue.uuidString] = role
    }

    public mutating func removeRole(for trackID: TrackID) {
        assignments.removeValue(forKey: trackID.rawValue.uuidString)
    }
}
