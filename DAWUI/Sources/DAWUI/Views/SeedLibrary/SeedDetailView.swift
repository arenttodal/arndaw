import SwiftUI
import DAWCore

// MARK: - Seed Detail View

/// Detail panel showing full information about a selected seed
public struct SeedDetailView: View {
    let seed: Seed
    let seedLibrary: SeedLibrary
    @State private var editedNotes: String
    @State private var editedTags: String

    public init(seed: Seed, seedLibrary: SeedLibrary) {
        self.seed = seed
        self.seedLibrary = seedLibrary
        self._editedNotes = State(initialValue: seed.notes)
        self._editedTags = State(initialValue: seed.tags.joined(separator: ", "))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(seed.name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))

                    Text(seed.createdAt, style: .date)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Waveform
                if let waveform = seed.waveformSamples {
                    WaveformPreviewView(samples: waveform)
                        .frame(height: 60)
                        .padding(.vertical, 4)
                }

                // Metadata grid
                VStack(spacing: 8) {
                    metadataRow("Duration", value: seed.formattedDuration)
                    if let bpm = seed.formattedBPM {
                        metadataRow("Tempo", value: bpm)
                    }
                    if let key = seed.detectedKey {
                        metadataRow("Key", value: key)
                    }
                    metadataRow("Source", value: seed.captureSource.rawValue)
                    metadataRow("Rating", value: "\(seed.rating)/5")
                }

                Divider()

                // Tags
                VStack(alignment: .leading, spacing: 4) {
                    Text("TAGS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("Add tags (comma separated)", text: $editedTags)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit {
                            saveTags()
                        }
                }

                // Notes
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextEditor(text: $editedNotes)
                        .font(.system(size: 11))
                        .frame(minHeight: 60)
                        .border(Color.gray.opacity(0.2))
                        .onChange(of: editedNotes) { _, newValue in
                            saveNotes(newValue)
                        }
                }

                Divider()

                // Actions
                VStack(spacing: 8) {
                    Button {
                        // Export action
                    } label: {
                        Label("Export as WAV", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        // Load into session
                    } label: {
                        Label("Load into Session", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Spacer()
        }
    }

    private func saveTags() {
        var updated = seed
        updated.tags = editedTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Task { await seedLibrary.updateSeed(updated) }
    }

    private func saveNotes(_ notes: String) {
        var updated = seed
        updated.notes = notes
        Task { await seedLibrary.updateSeed(updated) }
    }
}
