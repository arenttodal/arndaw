# Ritual DAW — Implementation Plan
## Transforming Musio Create into Ritual

---

## Executive Summary

Transform the existing Musio Create codebase (a traditional SwiftUI DAW) into **Ritual**, a performance-first DAW built around 4 modes (Capture, Loop, Layer, Perform), an 8-track constraint, a Seed Library, and a philosophy of "capture, don't construct."

The existing codebase provides a strong foundation: a working audio engine (CoreAudio + AVAudioEngine backends), MIDI system, plugin hosting (AU/VST3), project persistence, transport system, and SwiftUI view layer. The transformation preserves and adapts these systems while building entirely new workflows on top.

**Key decisions:**
- AI features adapted for Ritual (auto-tagging, BPM/key detection, smart export)
- Built-in instruments via curated AU plugin wrappers (not custom synth engines)
- Priority: Capture Mode + Seed Library first

---

## Phase 0: Foundation & Rebranding

### 0.1 — Rename & Rebrand
**Files affected:** `Package.swift`, `DAWApp/Sources/DAWApp/DAWApp.swift`, `DAWApp/Resources/Info.plist`, `README.md`

- Rename app target from `DAWApp` → `RitualApp`
- Update `Package.swift`: product names, target names, bundle identifier → `com.ritual.app`
- Update `Info.plist`: display name "Ritual", bundle ID, UTType `.ritual` (replaces `.dawproj`)
- Update `README.md` with Ritual branding and philosophy
- Rename `DAWCore` → keep as `DAWCore` internally (avoid massive rename churn), but public-facing types get Ritual prefixes where appropriate
- Update window title, about dialog, menu bar app name

### 0.2 — Mode System Architecture
**New file:** `DAWCore/Sources/DAWCore/Models/RitualMode.swift`

```swift
public enum RitualMode: String, Codable, CaseIterable {
    case capture    // Always-recording, save moments
    case loop       // Live looping workflow
    case layer      // Texture Canvas
    case perform    // Locked performance mode
    case studio     // Escape hatch (traditional DAW)
}
```

**Modified:** `DAWCore/Sources/DAWCore/Models/Project.swift`
- Add `currentMode: RitualMode` to Project (default: `.capture`)
- Add `scenes: [Scene]` array
- Add `seedLibraryPath: URL?`
- Add `trackRoles: [TrackID: TrackRole]` mapping

**New file:** `DAWCore/Sources/DAWCore/Models/TrackRole.swift`
```swift
public enum TrackRole: String, Codable {
    case melodicA, melodicB, melodicC, melodicD  // Tracks 1-4 (swappable)
    case bass       // Track 5 (fixed role)
    case drums      // Track 6 (fixed role)
    case percussion // Track 7 (fixed role)
    case groove     // Track 8 (Element Mixer)
}
```

### 0.3 — 8-Track Constraint Model
**Modified:** `DAWCore/Sources/DAWCore/Models/Project.swift`

- Add `isPerformanceMode: Bool` computed property (true unless `.studio`)
- Add track limit enforcement: `addTrack()` checks mode, refuses in performance modes if count >= 8
- Add `defaultPerformanceTracks()` factory method that creates the 8 default tracks with roles
- Track 5/6/7/8 get fixed roles but swappable sounds
- Existing `tracks` array stays, but UI enforces the constraint

### 0.4 — New App Shell with Mode Switching
**Modified:** `DAWUI/Sources/DAWUI/Views/MainWindowView.swift` (major rewrite)

Replace the current single-view layout with a mode-driven container:
```
RitualRootView
├── ModeTabBar (Capture | Loop | Layer | Perform)
├── Content (switches based on mode)
│   ├── CaptureView
│   ├── LoopView
│   ├── TextureCanvasView
│   ├── PerformView
│   └── StudioView (existing MainWindowView, mostly)
└── StatusBar (always visible: tempo, time, input level)
```

The existing `MainWindowView` becomes the basis for `StudioView`.

---

## Phase 1: Capture Mode + Rolling Buffer (PRIORITY)

### 1.1 — Rolling Audio Buffer
**New file:** `DAWCore/Sources/DAWCore/Audio/RollingCaptureBuffer.swift`

This is the heart of Capture Mode. A circular buffer that always records the last 5 minutes of audio input to RAM.

```swift
public class RollingCaptureBuffer {
    // 5 minutes at 48kHz stereo = ~57.6 MB (very manageable)
    private let bufferDuration: TimeInterval = 300  // 5 minutes
    private var buffer: UnsafeMutablePointer<Float>
    private var writePosition: Int64 = 0
    private var sampleRate: Double
    private var channelCount: Int

    // Extract last N seconds as audio data
    func extractLast(seconds: TimeInterval) -> AVAudioPCMBuffer

    // Save extracted audio to file (WAV/MP3)
    func saveLast(seconds: TimeInterval, to url: URL, format: ExportFormat) async throws -> URL

    // Mark current position (for star rating / bookmarks)
    func markCurrentPosition() -> CaptureMarker
}
```

**Integration with AudioEngine:**
- Modified: `DAWCore/Sources/DAWCore/Audio/AudioEngine.swift`
- Install an input tap on the audio engine's input node
- Route input samples to `RollingCaptureBuffer` continuously
- Buffer runs independently of transport state (always capturing)

### 1.2 — Capture Mode Data Model
**New file:** `DAWCore/Sources/DAWCore/Models/Seed.swift`

```swift
public struct Seed: Identifiable, Codable {
    public let id: UUID
    public var name: String              // Auto-generated: "morning_idea_042"
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFileURL: URL         // Path to saved audio

    // Auto-detected metadata
    public var detectedBPM: Double?
    public var detectedKey: String?
    public var waveformData: [Float]?    // Pre-computed for preview

    // User metadata
    public var isStarred: Bool = false
    public var tags: [String] = []
    public var rating: Int = 0           // 0-5 stars

    // Session context
    public var sessionName: String?
    public var capturedDuration: TimeInterval  // How much was saved (30s, 1m, 2m)
}
```

### 1.3 — Seed Library
**New file:** `DAWCore/Sources/DAWCore/Persistence/SeedLibrary.swift`

```swift
public class SeedLibrary: ObservableObject {
    @Published public var seeds: [Seed] = []

    private let libraryURL: URL  // ~/Music/Ritual Seeds/
    private let metadataFile: URL  // library.json

    // Core operations
    func addSeed(_ seed: Seed) async throws
    func removeSeed(id: UUID) throws
    func exportSeed(id: UUID, format: ExportFormat, to: URL) async throws -> URL
    func loadIntoSession(seedID: UUID, trackID: TrackID) throws

    // Filtering
    func seeds(starred: Bool?, dateRange: DateInterval?, tags: [String]?) -> [Seed]

    // Auto-analysis (uses existing MIDIContextAnalyzer + new audio analysis)
    func analyzeSeed(_ seed: Seed) async -> SeedAnalysis
}
```

**Storage structure:**
```
~/Music/Ritual Seeds/
├── library.json                    // Seed metadata index
├── audio/
│   ├── {uuid}.wav                 // Lossless audio files
│   └── {uuid}_preview.mp3        // Quick preview files
└── waveforms/
    └── {uuid}.json                // Pre-computed waveform data
```

### 1.4 — BPM & Key Detection
**New file:** `DAWCore/Sources/DAWCore/Audio/AudioAnalyzer.swift`

- BPM detection via onset detection + autocorrelation (standard DSP approach)
- Key detection: extend the existing `MIDIContextAnalyzer`'s Krumhansl-Schmuckler algorithm to work on audio spectral data (chromagram → pitch class profile → key correlation)
- AI-assisted enhancement: Use Claude to refine analysis when network available (adapt existing `ClaudeService`)
- Waveform data extraction for previews

### 1.5 — Capture Mode UI
**New file:** `DAWUI/Sources/DAWUI/Views/Capture/CaptureView.swift`

```
┌─────────────────────────────────────────────────────┐
│                   CAPTURE MODE                       │
│                                                      │
│   ◉ ALWAYS RECORDING (buffered)                     │
│                                                      │
│   Input Level: ████████████████░░░░░  -6 dB         │
│                                                      │
│   [ SAVE 30s ] [ SAVE 1m ] [ SAVE 2m ] [ ⭐ MARK ]  │
│                                                      │
│   ════════════════════●═══════════════               │
│                      NOW                              │
│                                                      │
│   Recent Saves:                                      │
│   ⭐ morning_042  0:34  92 BPM  Dm   [▶] [↗]       │
│      morning_041  1:12  78 BPM  Em   [▶] [↗]       │
│                                                      │
└─────────────────────────────────────────────────────┘
```

**New files:**
- `DAWUI/Sources/DAWUI/Views/Capture/CaptureView.swift` — Main capture UI
- `DAWUI/Sources/DAWUI/Views/Capture/RecentSavesListView.swift` — Recent captures list
- `DAWUI/Sources/DAWUI/Views/Capture/CaptureTimelineView.swift` — Visual buffer timeline
- `DAWUI/Sources/DAWUI/ViewModels/CaptureViewModel.swift` — State management

**Key interactions:**
- Number keys 1/2/3 → save last 30s/1m/2m
- Star key → toggle star on last save
- Space → preview last save
- Enter → save current moment
- All saves auto-added to Seed Library
- Input level meter always visible
- No transport controls needed — always recording

### 1.6 — Instant Export Engine
**New file:** `DAWCore/Sources/DAWCore/Audio/InstantExporter.swift`

- Extract from rolling buffer → render to WAV/MP3 immediately
- MP3 encoding via AudioToolbox (CBR 320kbps)
- Background thread rendering (non-blocking)
- Auto-generates waveform preview data during export
- Triggers BPM/key analysis after export

### 1.7 — Seed Library UI
**New file:** `DAWUI/Sources/DAWUI/Views/SeedLibrary/SeedLibraryView.swift`

```
┌─────────────────────────────────────────────────────┐
│                   SEED LIBRARY                       │
│                                                      │
│   Filter: [All ▼] [This Week ▼] [⭐ Starred]       │
│                                                      │
│   ⭐ morning_042      Feb 5  0:34  92BPM  Dm       │
│      ▓▓▓▓▓░░░▓▓▓▓▓▓░░░▓▓▓▓         [▶] [↗] [+]   │
│                                                      │
│      morning_041      Feb 5  1:12  78BPM  Em       │
│      ░░▓▓▓▓▓▓▓▓▓░░░░▓▓▓▓▓▓▓        [▶] [↗] [+]   │
│                                                      │
│   [▶] Preview  [↗] Export  [+] Load into Session    │
└─────────────────────────────────────────────────────┘
```

**New files:**
- `DAWUI/Sources/DAWUI/Views/SeedLibrary/SeedLibraryView.swift`
- `DAWUI/Sources/DAWUI/Views/SeedLibrary/SeedRowView.swift`
- `DAWUI/Sources/DAWUI/Views/SeedLibrary/SeedDetailView.swift`
- `DAWUI/Sources/DAWUI/Views/SeedLibrary/WaveformPreviewView.swift`

---

## Phase 2: Loop Mode

### 2.1 — Looper Engine
**New file:** `DAWCore/Sources/DAWCore/Audio/LooperEngine.swift`

Per-track looper with state machine:

```swift
public enum LooperState {
    case empty
    case recording    // First recording sets loop length
    case playing
    case overdubbing  // Adding layers
}

public class TrackLooper {
    var state: LooperState = .empty
    var layers: [AudioLayer] = []
    var loopLengthInBeats: Double = 0
    var loopLengthInSamples: Int64 = 0

    func toggle()           // Main button: cycles through states
    func undoLastLayer()    // Remove most recent layer
    func clear()            // Reset to empty
    func extractToClip() -> Clip  // Convert to timeline clip
}

public class LooperEngine {
    var trackLoopers: [TrackID: TrackLooper]
    var globalTempo: Double
    var masterLoopLength: Double  // Set by first loop recorded

    func toggleTrack(_ id: TrackID)
    func undoTrack(_ id: TrackID)
    func clearTrack(_ id: TrackID)
    func stopAll()
}
```

**Integration:**
- Modified: `AudioEngine` — add looper recording/playback nodes per track
- Looper records from track input, plays back mixed with other loops
- First loop sets the global loop length; subsequent loops quantize to it
- Overdub adds new layer on top of existing layers

### 2.2 — Loop Mode UI
**New files:**
- `DAWUI/Sources/DAWUI/Views/Loop/LoopView.swift` — Main loop mode layout
- `DAWUI/Sources/DAWUI/Views/Loop/TrackLooperView.swift` — Per-track looper strip
- `DAWUI/Sources/DAWUI/Views/Loop/LoopProgressView.swift` — Circular/linear loop position
- `DAWUI/Sources/DAWUI/ViewModels/LoopViewModel.swift`

```
┌──────────────────────────────────────────────────────┐
│  Global: ▶ PLAYING   BPM: 92   Bars: 8              │
│                                                       │
│  [1:VLN] [2:PAD] [3:GTR] [4:SYN] [5:BAS] [6:DRM]   │
│   ████    ░░░░    ████    ░░░░    ████    ████       │
│   ████    ░░░░    ░░░░    ░░░░    ████    ████       │
│    ●       ○       ●       ○       ●       ●         │
│  [REC]   [REC]  [PLAY]  [STOP]  [PLAY]  [PLAY]      │
│                                                       │
│  ┌─ TRACK 1 LOOPER ───────────── ◉ RECORDING ──┐    │
│  │ ════════●══════════════                       │    │
│  │ Layer 1: ████████████████████ (playing)       │    │
│  │ Layer 2: recording...                         │    │
│  └───────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### 2.3 — Quantized Loop Recording
**Modified:** `DAWCore/Sources/DAWCore/Audio/LooperEngine.swift`

- First loop: free-form recording, length becomes master
- Subsequent loops: auto-quantized to bar boundaries of master loop
- Visual countdown showing position within loop cycle
- Pre-roll count-in option (1 bar visual countdown before recording starts)

---

## Phase 3: Texture Canvas (Layer Mode)

### 3.1 — Texture Canvas Engine
**New file:** `DAWCore/Sources/DAWCore/Audio/TextureCanvas.swift`

```swift
public class TextureCanvas: ObservableObject {
    @Published var layers: [TextureLayer] = []
    @Published var masterVolume: Float = 1.0

    let maxLayers: Int = 8
    var autoFadeDuration: Double = 8.0  // bars
    var inputSource: InputSource?

    struct TextureLayer: Identifiable {
        let id: UUID
        var audioBuffer: AVAudioPCMBuffer
        var volume: Float = 1.0
        var fadeState: FadeState
        var createdAt: Date
        var age: TimeInterval  // For auto-fade calculation
    }

    func addLayer()       // Record new layer from input
    func fadeOldest()     // Manually fade oldest layer
    func clearAll()       // Remove all layers

    // Effects chain (shared across all layers)
    var reverbAmount: Float
    var delayAmount: Float
    var lowPassFrequency: Float
}
```

**Integration:**
- Canvas output routes to a dedicated mixer node before master
- Single fader controls entire canvas volume
- Auto-fade: oldest layers reduce volume over configurable time
- Independent from 8-track system

### 3.2 — Texture Canvas UI
**New files:**
- `DAWUI/Sources/DAWUI/Views/Layer/TextureCanvasView.swift`
- `DAWUI/Sources/DAWUI/ViewModels/TextureCanvasViewModel.swift`

Visual representation of ambient layers with input routing, FX controls, and fade management.

---

## Phase 4: Perform Mode + Scenes

### 4.1 — Scene Model
**New file:** `DAWCore/Sources/DAWCore/Models/Scene.swift`

```swift
public struct Scene: Identifiable, Codable {
    public let id: UUID
    public var name: String               // "BASE", "BUILD", "PEAK", "DROP"
    public var trackStates: [TrackID: TrackSceneState]
    public var canvasVolume: Float?        // nil = no change
    public var tempoChange: Double?        // nil = no change
    public var fxOverrides: [String: Float]?

    public struct TrackSceneState: Codable {
        var isPlaying: Bool
        var isMuted: Bool
        var volume: Float?     // nil = no change from current
    }
}
```

### 4.2 — Perform Mode Engine
**New file:** `DAWCore/Sources/DAWCore/Transport/PerformModeController.swift`

- Locks keyboard input (except mapped controls + triple-Escape)
- Disables mouse interaction on non-control elements
- Scene navigation: advance/retreat through scene list
- Scene transitions: crossfade track states over configurable duration
- Auto-recording of entire performance to capture buffer

### 4.3 — Perform Mode UI
**New files:**
- `DAWUI/Sources/DAWUI/Views/Perform/PerformView.swift`
- `DAWUI/Sources/DAWUI/Views/Perform/SceneStripView.swift`
- `DAWUI/Sources/DAWUI/Views/Perform/PerformTrackIndicator.swift`

Large, high-contrast display. Readable from 10 feet. Minimal information: current scene, track states, position, next scene hint.

---

## Phase 5: Hardware Integration

### 5.1 — Foot Pedal System
**New file:** `DAWCore/Sources/DAWCore/MIDI/FootPedalController.swift`

- MIDI CC mapping for 3-button foot pedal
- Short press vs long press (2s) detection
- Pedal banks (Loop Control, Scene Control, Track 1, Canvas)
- Bank switching via modifier or double-tap
- Default mappings per the spec

### 5.2 — Zero-Config Controller Profiles
**New file:** `DAWCore/Sources/DAWCore/MIDI/ControllerProfiles.swift`

- Built-in profiles for: Ableton Push, Novation Launchpad, Korg NanoKontrol, Akai APC40, generic 8-fader, generic foot pedal, generic expression pedal
- Auto-detection by MIDI device name
- Fallback MIDI learn mode: click parameter → move control → mapped

### 5.3 — Controller Mapping UI
**New file:** `DAWUI/Sources/DAWUI/Views/Settings/ControllerMappingView.swift`

Simple learn-mode interface. No MIDI channel hunting.

---

## Phase 6: Element Mixer (Track 8)

### 6.1 — Element Mixer Engine
**New file:** `DAWCore/Sources/DAWCore/Audio/ElementMixer.swift`

Track 8 becomes a sub-mixer:
```swift
public class ElementMixer {
    var elements: [MixerElement]  // 7 sub-tracks
    var banks: [ElementBank]      // 4 switchable configurations
    var currentBankIndex: Int = 0
    var masterVolume: Float       // Controlled by Track 8 fader

    struct MixerElement {
        var name: String          // "Top 1", "Groove 1", "Snare", "Kick", "FX"
        var volume: Float
        var isMuted: Bool
        var audioSource: URL?     // Loop/sample
    }

    struct ElementBank {
        var name: String          // "Half-Time", "House", "Broken", "Ambient"
        var elements: [MixerElement]
    }
}
```

### 6.2 — Element Mixer UI
**New file:** `DAWUI/Sources/DAWUI/Views/Mixer/ElementMixerView.swift`

7 mini faders with mute buttons, bank selector, master fader from Track 8.

---

## Phase 7: Built-in Instruments & Effects (AU Wrappers)

### 7.1 — Curated Instrument Library
**New file:** `DAWCore/Sources/DAWCore/Plugins/RitualInstrumentLibrary.swift`

Wrap macOS built-in Audio Units with curated presets:

```swift
public struct RitualInstrument {
    let category: InstrumentCategory  // .keys, .pads, .bass, .synth, .drums
    let name: String                  // "Piano", "Analog Pad", "Sub Bass"
    let auDescription: AudioComponentDescription
    let presetData: Data?             // AU preset that configures the sound
    let icon: String                  // SF Symbol
}

public enum InstrumentCategory: String, CaseIterable {
    case keys, pads, bass, synth, drums
}
```

- Piano: Apple DLS Music Device with piano bank
- Pads: AU with pad presets (or configure simple synth patch)
- Bass: AU configured for bass range
- Drums: Apple DLS with GM drum kit
- Each category: 3-5 presets max (per spec)

### 7.2 — One-Knob Effects
**New file:** `DAWCore/Sources/DAWCore/Plugins/RitualEffectLibrary.swift`

Each effect has a single macro knob that controls the "right" thing:

```swift
public struct RitualEffect {
    let type: EffectType
    let name: String
    let auDescription: AudioComponentDescription
    let macroMapping: MacroMapping  // Maps single 0-1 knob to multiple AU params

    struct MacroMapping {
        let parameters: [(paramID: AudioUnitParameterID, range: ClosedRange<Float>)]
    }
}
```

Effect categories per spec:
- Space: Room, Hall, Plate, Shimmer
- Time: Delay, Tape Echo, Ping Pong
- Tone: EQ, Filter, Saturation
- Dynamics: Compressor, Limiter
- Creative: Stutter, Glitch, Freeze

---

## Phase 8: Export & Sharing

### 8.1 — Enhanced Export System
**Modified:** `DAWCore/Sources/DAWCore/Audio/InstantExporter.swift`

- One-click export dialog (WAV, MP3 320kbps, FLAC, Stems)
- Stems export: 8 individual track files + canvas + master
- Background rendering (continue playing while exporting)
- Auto-add to Seed Library option
- Session file inclusion option

### 8.2 — Export UI
**New file:** `DAWUI/Sources/DAWUI/Views/Export/ExportView.swift`

Clean dialog matching spec: format selector, destination, filename preview, checkboxes.

---

## Phase 9: Studio Mode (Escape Hatch)

### 9.1 — Mode Transition
**Modified:** `DAWCore/Sources/DAWCore/Models/Project.swift`

- "Graduate" session: entering Studio Mode lifts 8-track limit
- Returning to Performance Mode: tracks beyond 8 get bounced to audio
- Confirmation dialog with philosophy reminder

### 9.2 — Studio View
**Modified:** `DAWUI/Sources/DAWUI/Views/MainWindowView.swift`

The existing Musio Create UI becomes Studio Mode:
- Full timeline/arrangement view
- Piano roll MIDI editor (already built)
- Complex mixer (already built)
- Full automation
- Plugin browser (already built)
- Wrap with mode indicator showing "STUDIO MODE"

---

## Phase 10: AI Adaptation

### 10.1 — AI-Powered Seed Analysis
**Modified:** `DAWCore/Sources/DAWCore/AI/ClaudeService.swift`

- Auto-tag seeds with descriptive labels using audio analysis + AI
- Suggest similar seeds from library
- Generate descriptions for export

### 10.2 — Smart Audio Analysis
**Modified:** `DAWCore/Sources/DAWCore/AI/MIDIContextAnalyzer.swift`

- Extend to work on audio (not just MIDI)
- Chromagram-based key detection for audio seeds
- Onset-based BPM detection
- Integration with Seed Library auto-analysis pipeline

### 10.3 — AI Assistant in Studio Mode
**Modified:** `DAWUI/Sources/DAWUI/Views/AI/AIAssistantView.swift`

- AI assistant available in Studio Mode (existing functionality)
- Contextual AI suggestions in other modes (non-intrusive)
- Voice commands adapted for Ritual workflows

---

## Phase 11: Keyboard Shortcuts & Input

### 11.1 — Mode-Specific Shortcuts
**Modified:** `DAWUI/Sources/DAWUI/Views/Shared/KeyboardShortcuts.swift`

**Global:**
| Key | Action |
|-----|--------|
| Space | Play/Pause |
| Enter | Save capture (Capture Mode) |
| Tab | Cycle modes |
| 1-8 | Select track |
| M | Mute selected |
| S | Solo selected |
| R | Arm selected |
| Esc×3 | Emergency unlock |

**Capture Mode:**
| Key | Action |
|-----|--------|
| 1 | Save last 30s |
| 2 | Save last 1m |
| 3 | Save last 2m |
| * | Star current |

**Loop Mode:**
| Key | Action |
|-----|--------|
| [ | Record/play/overdub selected track |
| ] | Undo last layer |
| \ | Clear track |
| , | Previous scene |
| . | Next scene |

---

## File Structure Summary

### New Files (by phase)

```
DAWCore/Sources/DAWCore/
├── Models/
│   ├── RitualMode.swift          (Phase 0)
│   ├── TrackRole.swift           (Phase 0)
│   ├── Seed.swift                (Phase 1)
│   └── Scene.swift               (Phase 4)
├── Audio/
│   ├── RollingCaptureBuffer.swift (Phase 1)
│   ├── AudioAnalyzer.swift        (Phase 1)
│   ├── InstantExporter.swift      (Phase 1)
│   ├── LooperEngine.swift         (Phase 2)
│   ├── TextureCanvas.swift        (Phase 3)
│   └── ElementMixer.swift         (Phase 6)
├── Persistence/
│   └── SeedLibrary.swift          (Phase 1)
├── Transport/
│   └── PerformModeController.swift (Phase 4)
├── MIDI/
│   ├── FootPedalController.swift  (Phase 5)
│   └── ControllerProfiles.swift   (Phase 5)
└── Plugins/
    ├── RitualInstrumentLibrary.swift (Phase 7)
    └── RitualEffectLibrary.swift     (Phase 7)

DAWUI/Sources/DAWUI/
├── Views/
│   ├── RitualRootView.swift       (Phase 0)
│   ├── Capture/
│   │   ├── CaptureView.swift      (Phase 1)
│   │   ├── CaptureTimelineView.swift
│   │   └── RecentSavesListView.swift
│   ├── SeedLibrary/
│   │   ├── SeedLibraryView.swift  (Phase 1)
│   │   ├── SeedRowView.swift
│   │   ├── SeedDetailView.swift
│   │   └── WaveformPreviewView.swift
│   ├── Loop/
│   │   ├── LoopView.swift         (Phase 2)
│   │   ├── TrackLooperView.swift
│   │   └── LoopProgressView.swift
│   ├── Layer/
│   │   └── TextureCanvasView.swift (Phase 3)
│   ├── Perform/
│   │   ├── PerformView.swift      (Phase 4)
│   │   ├── SceneStripView.swift
│   │   └── PerformTrackIndicator.swift
│   ├── Mixer/
│   │   └── ElementMixerView.swift (Phase 6)
│   ├── Export/
│   │   └── ExportView.swift       (Phase 8)
│   └── Settings/
│       └── ControllerMappingView.swift (Phase 5)
└── ViewModels/
    ├── CaptureViewModel.swift     (Phase 1)
    ├── LoopViewModel.swift        (Phase 2)
    └── TextureCanvasViewModel.swift (Phase 3)
```

### Heavily Modified Existing Files
- `Package.swift` — Target renames, new dependencies
- `DAWApp/Sources/DAWApp/DAWApp.swift` — App entry point, menus, mode system
- `DAWCore/Sources/DAWCore/Models/Project.swift` — Mode, scenes, track roles, 8-track limit
- `DAWCore/Sources/DAWCore/Models/Track.swift` — Track roles
- `DAWCore/Sources/DAWCore/Audio/AudioEngine.swift` — Capture buffer tap, looper integration
- `DAWCore/Sources/DAWCore/Transport/TransportState.swift` — Mode-aware transport
- `DAWUI/Sources/DAWUI/Views/MainWindowView.swift` — Becomes Studio Mode container
- `DAWUI/Sources/DAWUI/Views/Shared/KeyboardShortcuts.swift` — Mode-specific shortcuts
- `DAWUI/Sources/DAWUI/ViewModels/ProjectViewModel.swift` — Mode switching, capture integration

### Preserved As-Is (Foundation)
- Core audio engine architecture (AudioBackendProtocol, CoreAudioBackend, RenderGraph)
- MIDI system (MIDIManager, MIDISequencer)
- Plugin hosting (PluginHost, VST3Bridge)
- Undo system (DAWUndoManager)
- Project persistence structure (adapted for .ritual format)
- AI services (adapted, not rewritten)
- Metal waveform rendering
- Piano roll (Studio Mode only)
- Existing mixer (Studio Mode only, simplified version for Performance)

---

## Implementation Order

| Order | Phase | Effort | Description |
|-------|-------|--------|-------------|
| 1 | Phase 0 | Medium | Foundation: rebrand, mode system, 8-track model, app shell |
| 2 | Phase 1 | Large | **Capture Mode + Seed Library** (priority) |
| 3 | Phase 2 | Large | Loop Mode + looper engine |
| 4 | Phase 3 | Medium | Texture Canvas |
| 5 | Phase 4 | Medium | Perform Mode + Scenes |
| 6 | Phase 9 | Small | Studio Mode (wrap existing UI) |
| 7 | Phase 5 | Medium | Hardware integration (pedals, controllers) |
| 8 | Phase 6 | Medium | Element Mixer (Track 8) |
| 9 | Phase 7 | Medium | Built-in instruments & effects |
| 10 | Phase 8 | Small | Export system |
| 11 | Phase 10 | Medium | AI adaptation |
| 12 | Phase 11 | Small | Keyboard shortcuts refinement |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Rolling buffer latency/performance | Use lock-free ring buffer, pre-allocated memory, separate audio thread |
| Loop sync drift over time | Sample-accurate loop boundaries, compensate for buffer sizes |
| AU preset availability varies by macOS version | Test on macOS 14+, fallback to DLS Music Device for all instruments |
| Texture Canvas memory growth | Hard cap at 8 layers, auto-fade enforced, memory monitoring |
| Perform Mode input blocking on macOS | Use NSEvent local/global monitors, CGEvent taps for keyboard lock |
| File format migration (.dawproj → .ritual) | Support reading both formats, auto-convert on open |
