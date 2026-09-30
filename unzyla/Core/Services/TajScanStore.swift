import Foundation
import Observation
import UIKit

/// One tile on a scanned page, in 0…1 coordinates of the page's frame (the printed mushaf border),
/// so re-cropping the page image never moves saved tiles. Tiles meet edge to edge.
nonisolated struct TajScanTile: Decodable, Sendable {
    /// App word IDs (IndoPak, mushaf 2) this tile covers; the first is the word itself, the rest attached marks.
    /// Empty for a surah header box.
    let ids: [Int]
    /// Surah number when this tile is a surah header box (title + bismillah).
    let surah: Int?
    /// When the scan prints a word across a page break (the two editions break pages a word apart),
    /// the word's own digital page and the word itself, so taps land on the right page.
    let page: Int?
    let words: [TajScanWord]?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// A word carried by a tile whose word lives on a neighbouring digital page.
nonisolated struct TajScanWord: Decodable, Sendable {
    let id: Int
    let position: Int
    let content: String
    let ayah: String?

    var mushafWord: MushafWord {
        MushafWord(id: id, position: position, content: content, ayah: ayah, layout: nil)
    }
}

/// Where the mushaf frame sits inside a page image, in 0…1 image coordinates.
nonisolated struct TajScanFrame: Decodable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct TajScanPage {
    let image: UIImage
    let frame: TajScanFrame
    let tiles: [TajScanTile]
}

/// Developer preview: the scanned Taj Company 13-line mushaf, mapped word by word onto the IndoPak data.
///
/// Page images and tiles ship only in Debug builds (`tajscan-*` files are excluded from Release and
/// gitignored — the scans are not ours to distribute).
@MainActor
@Observable
final class TajScanStore {
    static let shared = TajScanStore()

    private static let enabledKey = "tajScanPreviewEnabled"

    /// App page numbers that have a mapped scan in this build.
    let availablePages: Set<Int>

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var isAvailable: Bool { !availablePages.isEmpty }

    /// Hand-corrected tiles saved from the web editor (hifzworld-api), preferred over the bundled ones.
    private var savedTiles: [Int: [TajScanTile]] = [:]
    @ObservationIgnored private var cache: [Int: TajScanPage] = [:]
    @ObservationIgnored private var fetchedPages: Set<Int> = []
    private static let mushafKey = "taj13"

    private struct PageFile: Decodable {
        let frame: TajScanFrame
        let words: [TajScanTile]
    }

    private struct SavedLayout: Decodable {
        let tiles: [TajScanTile]
    }

    private init() {
        let jsons = Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
        availablePages = Set(jsons.compactMap { path in
            let name = (path as NSString).lastPathComponent
            guard name.hasPrefix("tajscan-") else { return nil }
            return Int(name.dropFirst("tajscan-".count).dropLast(".json".count))
        })
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// The scan for an IndoPak page, when the preview is on and the page is mapped.
    func page(_ number: Int, mushafID: Int) -> TajScanPage? {
        guard isEnabled, mushafID == MushafID.indoPak.rawValue, availablePages.contains(number) else { return nil }
        if let cached = cache[number] {
            if let saved = savedTiles[number] {
                return TajScanPage(image: cached.image, frame: cached.frame, tiles: merged(saved, bundled: cached.tiles))
            }
            return cached
        }
        guard let jsonURL = Bundle.main.url(forResource: "tajscan-\(number)", withExtension: "json"),
              let imageURL = Bundle.main.url(forResource: "tajscan-\(number)", withExtension: "jpg"),
              let data = try? Data(contentsOf: jsonURL),
              let file = try? JSONDecoder().decode(PageFile.self, from: data),
              let image = UIImage(contentsOfFile: imageURL.path)
        else { return nil }
        let page = TajScanPage(image: image, frame: file.frame, tiles: file.words)
        cache[number] = page
        return savedTiles[number].map {
            TajScanPage(image: image, frame: file.frame, tiles: merged($0, bundled: file.words))
        } ?? page
    }

    /// Saved layouts store positions and word IDs only: take a spilled word's page + text from the bundled
    /// tile with the same word, and keep the bundled surah headers if the saved layout predates them.
    private func merged(_ saved: [TajScanTile], bundled: [TajScanTile]) -> [TajScanTile] {
        let spilled = Dictionary(
            bundled.compactMap { tile in tile.page != nil ? tile.ids.first.map { ($0, tile) } : nil },
            uniquingKeysWith: { first, _ in first }
        )
        var tiles = saved.map { tile -> TajScanTile in
            guard tile.page == nil, let id = tile.ids.first, let source = spilled[id] else { return tile }
            return TajScanTile(ids: tile.ids, surah: tile.surah, page: source.page, words: source.words,
                               x: tile.x, y: tile.y, width: tile.width, height: tile.height)
        }
        if !tiles.contains(where: { $0.surah != nil }) {
            tiles += bundled.filter { $0.surah != nil }
        }
        return tiles
    }

    /// Fetch the editor-saved layout for a page once per launch; 404 means keep the bundled tiles.
    func loadSavedLayout(for number: Int) async {
        guard availablePages.contains(number), !fetchedPages.contains(number) else { return }
        fetchedPages.insert(number)
        let url = HifzworldAPIConfig.baseURL
            .appendingPathComponent("api/scan_layouts/\(Self.mushafKey)/\(number)")
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let layout = try? JSONDecoder().decode(SavedLayout.self, from: data),
              !layout.tiles.isEmpty
        else {
            return
        }
        savedTiles[number] = layout.tiles
    }
}
