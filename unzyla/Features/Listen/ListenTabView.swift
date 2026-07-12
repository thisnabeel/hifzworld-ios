import SwiftUI

struct FloatingPlayerView: View {
    @Bindable var audio: AudioPlayerService

    var body: some View {
        if audio.duration > 0 || !audio.title.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audio.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if !audio.artist.isEmpty {
                            Text(audio.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        audio.togglePlayPause()
                    } label: {
                        Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                }
                Slider(
                    value: Binding(
                        get: { audio.position },
                        set: { audio.seek(to: $0) }
                    ),
                    in: 0...max(audio.duration, 1)
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 8)
            .padding(.horizontal)
        }
    }
}

struct ListenTabView: View {
    @Bindable var viewModel: ListenViewModel
    @Bindable var audio = AudioPlayerService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else {
                    List(viewModel.filteredRecitations) { recitation in
                        Button {
                            Task { await viewModel.play(recitation) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(recitation.surahName ?? "Surah \(recitation.surahPosition ?? 0)")
                                        .foregroundStyle(.primary)
                                    Text(recitation.riwayahTitle ?? recitation.riwayahSlug ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                FloatingPlayerView(audio: audio)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Recitation")
            .searchable(text: $viewModel.searchText, prompt: "Search surah")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All reciters") {
                            Task { await viewModel.selectReciter("all") }
                        }
                        ForEach(viewModel.reciters) { reciter in
                            Button(reciter.name) {
                                Task { await viewModel.selectReciter(reciter.slug) }
                            }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(viewModel.riwayahOptions, id: \.self) { riwayah in
                            Button(riwayah == "all" ? "All riwayat" : riwayah) {
                                viewModel.selectedRiwayah = riwayah
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .task { await viewModel.bootstrap() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
