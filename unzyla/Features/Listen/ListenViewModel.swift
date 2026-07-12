import Foundation
import Observation

@MainActor
@Observable
final class ListenViewModel {
    private let api = APIClient.shared

    var reciters: [Reciter] = []
    var recitations: [Recitation] = []
    var isLoading = false
    var errorMessage: String?

    var selectedReciterSlug = "all"
    var selectedRiwayah = "all"
    var searchText = ""

    var filteredRecitations: [Recitation] {
        recitations.filter { rec in
            let matchesRiwayah = selectedRiwayah == "all" || rec.riwayahSlug == selectedRiwayah
            let matchesSearch: Bool = {
                guard !searchText.isEmpty else { return true }
                let q = searchText.lowercased()
                return (rec.surahName?.lowercased().contains(q) ?? false) ||
                    String(rec.surahPosition ?? 0).contains(q)
            }()
            return matchesRiwayah && matchesSearch
        }
    }

    var riwayahOptions: [String] {
        var set = Set<String>()
        for r in recitations {
            if let slug = r.riwayahSlug { set.insert(slug) }
        }
        return ["all"] + set.sorted()
    }

    func bootstrap() async {
        await loadReciters()
        await loadRecitations()
    }

    func loadReciters() async {
        do {
            reciters = try await api.fetchReciters()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecitations() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if selectedReciterSlug == "all", let first = reciters.first {
                recitations = try await api.fetchRecitations(reciterSlug: first.slug)
            } else if selectedReciterSlug != "all" {
                recitations = try await api.fetchRecitations(reciterSlug: selectedReciterSlug)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func play(_ recitation: Recitation) async {
        guard let urlString = recitation.audioURL, let url = URL(string: urlString) else { return }
        AudioPlayerService.shared.playFullTrack(
            url: url,
            title: recitation.surahName ?? "Recitation",
            artist: recitation.riwayahTitle,
            artworkURL: nil
        )
        _ = try? await api.fetchVerseSegments(recitationID: recitation.recitationID)
    }

    func selectReciter(_ slug: String) async {
        selectedReciterSlug = slug
        await loadRecitations()
    }
}
