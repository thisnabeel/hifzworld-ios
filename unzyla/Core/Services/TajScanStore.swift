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

/// Where the scanned page files live online: `tajscan-<page>.jpg` + `tajscan-<page>.json` per page.
nonisolated enum TajScanRemote {
    /// Bump with every re-export of the page files so caches refresh.
    static let version = "v1"
    /// Cloudflare R2 bucket `hifzworld-scans`, public dev URL.
    static let baseURL: URL? = URL(string: "https://pub-dabf8dea9c6a4f26bc94c2a4db97c735.r2.dev/taj13/v1/")
    static let pageCount = 847
}

/// The scanned Taj Company 13-line mushaf, mapped word by word onto the IndoPak data.
///
/// Pages come from the app bundle when present (Debug builds bundle them from DevOnly/), otherwise they
/// are downloaded on demand from `TajScanRemote` and cached, with the neighbouring pages prefetched.
@MainActor
@Observable
final class TajScanStore {
    static let shared = TajScanStore()

    private static let enabledKey = "tajScanPreviewEnabled"

    enum PageState { case ready, loading, failed }

    /// App page numbers that have a mapped scan (bundled or downloadable).
    let availablePages: Set<Int>
    private let bundledPages: Set<Int>

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var isAvailable: Bool { !availablePages.isEmpty }

    /// Hand-corrected tiles saved from the web editor (hifzworld-api), preferred over the shipped ones.
    private var savedTiles: [Int: [TajScanTile]] = [:]
    /// Pages whose files are on disk / being fetched / failed to fetch (drives re-renders).
    private var loadedPages: Set<Int> = []
    private var loadingPages: Set<Int> = []
    private var failedPages: Set<Int> = []
    @ObservationIgnored private var cache: [Int: TajScanPage] = [:]
    @ObservationIgnored private var fetchedLayouts: Set<Int> = []
    private static let mushafKey = "taj13"

    private struct PageFile: Decodable {
        let frame: TajScanFrame
        let words: [TajScanTile]
    }

    private struct SavedLayout: Decodable {
        let tiles: [TajScanTile]
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TajScan/\(TajScanRemote.version)", isDirectory: true)
    }

    private init() {
        let jsons = Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
        bundledPages = Set(jsons.compactMap { path in
            let name = (path as NSString).lastPathComponent
            guard name.hasPrefix("tajscan-") else { return nil }
            return Int(name.dropFirst("tajscan-".count).dropLast(".json".count))
        })
        let remote: Set<Int> = TajScanRemote.baseURL == nil ? [] : Set(1...TajScanRemote.pageCount)
        availablePages = bundledPages.union(remote)
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Whether this IndoPak page should show the scan (it may still be downloading).
    func showsScan(_ number: Int, mushafID: Int) -> Bool {
        isEnabled && mushafID == MushafID.indoPak.rawValue && availablePages.contains(number) && !failedPages.contains(number)
    }

    func state(of number: Int) -> PageState {
        if failedPages.contains(number) { return .failed }
        if cache[number] != nil || loadedPages.contains(number) || bundledPages.contains(number) || filesOnDisk(number) { return .ready }
        return .loading
    }

    /// The scan for an IndoPak page, when it's on and its files are available locally.
    func page(_ number: Int, mushafID: Int) -> TajScanPage? {
        guard showsScan(number, mushafID: mushafID) else { return nil }
        _ = loadedPages      // re-render once a download lands
        if let cached = cache[number] {
            if let saved = savedTiles[number] {
                return TajScanPage(image: cached.image, frame: cached.frame, tiles: merged(saved, bundled: cached.tiles))
            }
            return cached
        }
        guard let (jsonURL, imageURL) = localFiles(number),
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

    /// Make sure a page's files are local, downloading them if needed.
    func ensure(_ number: Int) async {
        guard availablePages.contains(number), localFiles(number) == nil, !loadingPages.contains(number),
              let base = TajScanRemote.baseURL else { return }
        loadingPages.insert(number)
        defer { loadingPages.remove(number) }
        let dir = Self.cacheDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for ext in ["json", "jpg"] {
                let name = "tajscan-\(number).\(ext)"
                let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent(name))
                guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                    throw URLError(.badServerResponse)
                }
                try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            }
            failedPages.remove(number)
            loadedPages.insert(number)
        } catch {
            // offline or missing: show the rendered page for now, try again next launch
            failedPages.insert(number)
        }
    }

    /// Fetch the pages around one being read, so swiping doesn't wait.
    func prefetch(around number: Int) async {
        for offset in [1, -1, 2, -2] {
            let n = number + offset
            guard n >= 1, n <= TajScanRemote.pageCount else { continue }
            await ensure(n)
        }
    }

    private func filesOnDisk(_ number: Int) -> Bool {
        let dir = Self.cacheDirectory
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("tajscan-\(number).jpg").path)
            && FileManager.default.fileExists(atPath: dir.appendingPathComponent("tajscan-\(number).json").path)
    }

    private func localFiles(_ number: Int) -> (URL, URL)? {
        if bundledPages.contains(number),
           let json = Bundle.main.url(forResource: "tajscan-\(number)", withExtension: "json"),
           let jpg = Bundle.main.url(forResource: "tajscan-\(number)", withExtension: "jpg") {
            return (json, jpg)
        }
        guard filesOnDisk(number) else { return nil }
        let dir = Self.cacheDirectory
        return (dir.appendingPathComponent("tajscan-\(number).json"), dir.appendingPathComponent("tajscan-\(number).jpg"))
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
        guard availablePages.contains(number), !fetchedLayouts.contains(number) else { return }
        fetchedLayouts.insert(number)
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
