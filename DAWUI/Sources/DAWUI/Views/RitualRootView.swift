import SwiftUI
import DAWCore

// MARK: - Ritual Root View

/// The root view for the Ritual DAW
/// Manages mode switching and routes to the appropriate mode-specific view
public struct RitualRootView: View {
    @StateObject private var viewModel: ProjectViewModel
    @State private var currentMode: RitualMode = .capture
    @State private var showModeTransitionAlert: Bool = false
    @State private var pendingMode: RitualMode?
    @State private var showSeedLibrary: Bool = false

    public init(project: Project) {
        self._viewModel = StateObject(wrappedValue: ProjectViewModel(project: project))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Mode tab bar
            modeTabBar

            Divider()

            // Content area — switches based on current mode
            ZStack {
                switch currentMode {
                case .capture:
                    CaptureView(viewModel: viewModel)
                case .loop:
                    loopModePlaceholder
                case .layer:
                    layerModePlaceholder
                case .perform:
                    performModePlaceholder
                case .studio:
                    // The original DAW view becomes Studio Mode
                    MainWindowView(project: viewModel.project)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Status bar (always visible)
            statusBar
        }
        .sheet(isPresented: $showSeedLibrary) {
            SeedLibraryView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .alert("Switch to Studio Mode?", isPresented: $showModeTransitionAlert) {
            Button("Switch", role: .none) {
                if let mode = pendingMode {
                    currentMode = mode
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Studio Mode unlocks unlimited tracks and full DAW features. Your current session will be preserved.")
        }
    }

    // MARK: - Mode Tab Bar

    private var modeTabBar: some View {
        HStack(spacing: 0) {
            // Ritual logo / app name
            Text("RITUAL")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            Divider()
                .frame(height: 20)

            // Mode buttons
            ForEach(RitualMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }

            Spacer()

            // Seed Library button
            Button {
                showSeedLibrary.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "leaf")
                    Text("Seeds")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(showSeedLibrary ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func modeButton(_ mode: RitualMode) -> some View {
        Button {
            switchToMode(mode)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10))
                Text(mode.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(currentMode == mode ? modeAccentColor(mode).opacity(0.2) : Color.clear)
            .foregroundColor(currentMode == mode ? modeAccentColor(mode) : .secondary)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func modeAccentColor(_ mode: RitualMode) -> Color {
        switch mode {
        case .capture: return .red
        case .loop: return .green
        case .layer: return .purple
        case .perform: return .orange
        case .studio: return .blue
        }
    }

    private func switchToMode(_ mode: RitualMode) {
        if mode == .studio && currentMode != .studio {
            // Show confirmation before entering Studio Mode
            pendingMode = mode
            showModeTransitionAlert = true
        } else {
            currentMode = mode
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Mode indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(currentMode == .capture && viewModel.transportState.isPlaying ? Color.red : Color.gray)
                    .frame(width: 6, height: 6)
                Text(currentMode.displayName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 12)

            // Tempo
            Text("\(Int(viewModel.project.tempo.bpm)) BPM")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            // Time signature
            Text("\(viewModel.project.timeSignature.numerator)/\(viewModel.project.timeSignature.denominator)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Divider().frame(height: 12)

            // Position
            Text(viewModel.transportState.formattedPosition)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Sample rate
            Text("\(Int(viewModel.project.sampleRate / 1000))kHz")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Placeholder Views

    private var loopModePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat")
                .font(.system(size: 48))
                .foregroundColor(.green.opacity(0.5))
            Text("Loop Mode")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Coming in Phase 2")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var layerModePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 48))
                .foregroundColor(.purple.opacity(0.5))
            Text("Texture Canvas")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Coming in Phase 3")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var performModePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "theatermasks")
                .font(.system(size: 48))
                .foregroundColor(.orange.opacity(0.5))
            Text("Perform Mode")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Coming in Phase 4")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
