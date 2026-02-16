import SwiftUI
import DAWCore

// MARK: - Seed Library View

/// Full seed library browser
/// Shows all captured seeds with filtering, sorting, and management
public struct SeedLibraryView: View {
    @StateObject private var seedLibrary = SeedLibrary()
    @State private var filter = SeedFilter()
    @State private var sortOrder: SeedSortOrder = .newestFirst
    @State private var selectedSeedID: UUID?
    @State private var showDeleteConfirmation: Bool = false
    @State private var seedToDelete: UUID?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Filter bar
            filterBar

            Divider()

            // Content
            HStack(spacing: 0) {
                // Seed list
                seedList

                // Detail panel (if a seed is selected)
                if let selectedID = selectedSeedID,
                   let seed = seedLibrary.seeds.first(where: { $0.id == selectedID }) {
                    Divider()
                    SeedDetailView(seed: seed, seedLibrary: seedLibrary)
                        .frame(width: 280)
                }
            }
        }
        .task {
            await seedLibrary.load()
        }
        .alert("Delete Seed?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let id = seedToDelete {
                    Task { await seedLibrary.removeSeed(id: id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the audio file. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "leaf")
                .foregroundColor(.green)
            Text("SEED LIBRARY")
                .font(.system(size: 12, weight: .bold, design: .monospaced))

            Spacer()

            Text("\(filteredSeeds.count) seeds")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search seeds...", text: $filter.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)

            // Starred filter
            Toggle(isOn: $filter.starredOnly) {
                Image(systemName: filter.starredOnly ? "star.fill" : "star")
                    .foregroundColor(filter.starredOnly ? .yellow : .secondary)
            }
            .toggleStyle(.button)

            Spacer()

            // Sort order
            Picker("Sort", selection: $sortOrder) {
                Text("Newest").tag(SeedSortOrder.newestFirst)
                Text("Oldest").tag(SeedSortOrder.oldestFirst)
                Text("Name").tag(SeedSortOrder.nameAZ)
                Text("Longest").tag(SeedSortOrder.longestFirst)
                Text("BPM").tag(SeedSortOrder.bpmLowHigh)
                Text("Rating").tag(SeedSortOrder.ratingHighLow)
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Seed List

    private var filteredSeeds: [Seed] {
        seedLibrary.filteredSeeds(filter, sortedBy: sortOrder)
    }

    private var seedList: some View {
        Group {
            if filteredSeeds.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "leaf")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.3))

                    if filter.isActive {
                        Text("No seeds match your filters")
                            .foregroundColor(.secondary)
                        Button("Clear Filters") {
                            filter = SeedFilter()
                        }
                    } else {
                        Text("No seeds yet")
                            .foregroundColor(.secondary)
                        Text("Switch to Capture Mode to start collecting ideas")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredSeeds, selection: $selectedSeedID) { seed in
                    SeedRowView(seed: seed) {
                        Task { await seedLibrary.toggleStar(id: seed.id) }
                    } onDelete: {
                        seedToDelete = seed.id
                        showDeleteConfirmation = true
                    }
                    .tag(seed.id)
                }
                .listStyle(.plain)
            }
        }
    }
}
