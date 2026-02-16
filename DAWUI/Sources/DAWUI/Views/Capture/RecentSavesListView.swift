import SwiftUI
import DAWCore

// MARK: - Recent Saves List View

/// Shows the most recently saved seeds from Capture Mode
public struct RecentSavesListView: View {
    let seeds: [Seed]

    public init(seeds: [Seed]) {
        self.seeds = seeds
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("RECENT CAPTURES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(seeds.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if seeds.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No captures yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Press 1, 2, or 3 to save")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.3))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(seeds) { seed in
                            RecentSaveRow(seed: seed)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Recent Save Row

struct RecentSaveRow: View {
    let seed: Seed
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Star indicator
            if seed.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "star")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.2))
            }

            // Name and metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(seed.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(seed.formattedDuration)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let bpm = seed.formattedBPM {
                        Text(bpm)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    if let key = seed.detectedKey {
                        Text(key)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Mini waveform preview
            if let waveform = seed.waveformSamples {
                MiniWaveformView(samples: waveform)
                    .frame(width: 48, height: 20)
            }

            // Time ago
            Text(seed.formattedDate)
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Mini Waveform View

struct MiniWaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width / CGFloat(max(samples.count, 1))
            let midY = geometry.size.height / 2

            Canvas { context, size in
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let height = CGFloat(sample) * size.height * 0.9
                    let rect = CGRect(
                        x: x,
                        y: midY - height / 2,
                        width: max(barWidth - 0.5, 0.5),
                        height: max(height, 0.5)
                    )
                    context.fill(Path(rect), with: .color(.accentColor.opacity(0.5)))
                }
            }
        }
    }
}
