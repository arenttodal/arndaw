import SwiftUI
import DAWCore

// MARK: - Seed Row View

/// A single row in the seed library list
public struct SeedRowView: View {
    let seed: Seed
    let onToggleStar: () -> Void
    let onDelete: () -> Void

    public init(seed: Seed, onToggleStar: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.seed = seed
        self.onToggleStar = onToggleStar
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Star button
            Button(action: onToggleStar) {
                Image(systemName: seed.isStarred ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(seed.isStarred ? .yellow : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)

            // Waveform preview
            if let waveform = seed.waveformSamples {
                WaveformPreviewView(samples: waveform)
                    .frame(width: 60, height: 24)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 60, height: 24)
            }

            // Name and metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(seed.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Duration
                    Label(seed.formattedDuration, systemImage: "clock")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)

                    // BPM
                    if let bpm = seed.formattedBPM {
                        Text(bpm)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                    }

                    // Key
                    if let key = seed.detectedKey {
                        Text(key)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }
            }

            Spacer()

            // Tags
            HStack(spacing: 3) {
                ForEach(seed.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                }
            }

            // Date
            Text(seed.formattedDate)
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 50, alignment: .trailing)

            // Delete button (hidden until hover — handled by list context menu)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
