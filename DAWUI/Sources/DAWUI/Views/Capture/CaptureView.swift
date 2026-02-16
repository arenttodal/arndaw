import SwiftUI
import DAWCore

// MARK: - Capture View

/// The main view for Capture Mode
/// Shows the rolling buffer status, save controls, and recent captures
public struct CaptureView: View {
    @ObservedObject var viewModel: ProjectViewModel
    @StateObject private var captureVM = CaptureViewModel()
    @State private var showExportOptions: Bool = false

    public init(viewModel: ProjectViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header: capture status
            captureStatusHeader

            Divider()

            // Main content
            HStack(spacing: 0) {
                // Left: capture controls and timeline
                VStack(spacing: 16) {
                    // Input level meter
                    inputLevelMeter

                    // Save buttons
                    saveButtonsRow

                    // Buffer timeline visualization
                    CaptureTimelineView(
                        bufferDuration: captureVM.bufferDuration,
                        maxDuration: 300,
                        isCapturing: captureVM.isCapturing
                    )
                    .frame(height: 60)
                    .padding(.horizontal)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                Divider()

                // Right: recent saves
                RecentSavesListView(seeds: captureVM.recentSeeds)
                    .frame(width: 300)
            }

            // Feedback bar
            if let message = captureVM.feedbackMessage {
                feedbackBar(message)
            }

            if let error = captureVM.errorMessage {
                errorBar(error)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            setupCaptureBuffer()
        }
        .onDisappear {
            captureVM.stopLevelMonitoring()
        }
    }

    // MARK: - Capture Status Header

    private var captureStatusHeader: some View {
        HStack(spacing: 12) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(captureVM.isCapturing ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                    .overlay(
                        captureVM.isCapturing ?
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(captureVM.isCapturing ? 0.5 : 0)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: captureVM.isCapturing)
                        : nil
                    )

                Text(captureVM.isCapturing ? "CAPTURING" : "PAUSED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(captureVM.isCapturing ? .red : .secondary)
            }

            Divider().frame(height: 16)

            // Buffer status
            Text("Buffer: \(formatDuration(captureVM.bufferDuration)) / 5:00")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Capture toggle button
            Button {
                captureVM.toggleCapture()
            } label: {
                Text(captureVM.isCapturing ? "Pause Capture" : "Start Capture")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Input Level Meter

    private var inputLevelMeter: some View {
        VStack(spacing: 4) {
            Text("INPUT LEVEL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                // Left channel
                LevelMeterBar(level: captureVM.inputLevel.left, label: "L")
                // Right channel
                LevelMeterBar(level: captureVM.inputLevel.right, label: "R")
            }
            .frame(height: 20)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Save Buttons

    private var saveButtonsRow: some View {
        HStack(spacing: 12) {
            SaveButton(label: "30s", shortcutHint: "1", duration: 30) {
                Task { await captureVM.saveLast(seconds: 30) }
            }

            SaveButton(label: "1m", shortcutHint: "2", duration: 60) {
                Task { await captureVM.saveLast(seconds: 60) }
            }

            SaveButton(label: "2m", shortcutHint: "3", duration: 120) {
                Task { await captureVM.saveLast(seconds: 120) }
            }

            Divider().frame(height: 30)

            // Star/mark button
            Button {
                Task { await captureVM.markAndSave() }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.yellow)
                    Text("MARK")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(width: 56, height: 48)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    // MARK: - Feedback Bars

    private func feedbackBar(_ message: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func errorBar(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Dismiss") {
                captureVM.errorMessage = nil
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Helpers

    private func setupCaptureBuffer() {
        // Create capture buffer if not already configured
        let buffer = RollingCaptureBuffer(
            maxDuration: 300,
            sampleRate: viewModel.project.sampleRate,
            channelCount: 2
        )
        let seedLibrary = SeedLibrary()
        captureVM.configure(captureBuffer: buffer, seedLibrary: seedLibrary)

        // Auto-start capture
        captureVM.startCapture()

        // Load seed library
        Task {
            await seedLibrary.load()
            captureVM.recentSeeds = Array(seedLibrary.seeds.prefix(20))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Save Button

struct SaveButton: View {
    let label: String
    let shortcutHint: String
    let duration: TimeInterval
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("SAVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text(shortcutHint)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .frame(width: 56, height: 48)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Level Meter Bar

struct LevelMeterBar: View {
    let level: Float
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 10)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    // Level fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(levelColor)
                        .frame(width: geometry.size.width * CGFloat(min(level, 1.0)))
                }
            }

            // dB label
            Text(dbString)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var levelColor: Color {
        if level > 0.9 { return .red }
        if level > 0.7 { return .yellow }
        return .green
    }

    private var dbString: String {
        if level <= 0 { return "-inf" }
        let db = 20 * log10(level)
        return String(format: "%.0f", db)
    }
}
