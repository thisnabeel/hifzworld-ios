import Foundation
import Observation
import UIKit

/// One tile on a scanned page, in 0…1 coordinates of the page's frame (the printed mushaf border),
/// so re-cropping the page image never moves saved tiles. Tiles meet edge to edge.
nonisolated struct ScanTile: Decodable, Sendable {
    /// App word IDs (of the edition's digital mushaf) this tile covers; the first is the word itself, the rest attached marks.
    /// Empty for a surah header box.
    let ids: [Int]
    /// Surah number when this tile is a surah header box (title + bismillah).
    let surah: Int?
    /// When the scan prints a word across a page break (the two editions break pages a word apart),
    /// the word's own digital page and the word itself, so taps land on the right page.
    let page: Int?
    let words: [ScanWord]?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// A word carried by a tile whose word lives on a neighbouring digital page.
nonisolated struct ScanWord: Decodable, Sendable {
    let id: Int
    let position: Int
    let content: String
    let ayah: String?

    var mushafWord: MushafWord {
        MushafWord(id: id, position: position, content: content, ayah: ayah, layout: nil)
    }
}

/// Where the mushaf frame sits inside a page image, in 0…1 image coordinates.
nonisolated struct ScanFrame: Decodable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct ScanPage {
    let image: UIImage
    let frame: ScanFrame
    let tiles: [ScanTile]
}

/// A printed mushaf whose page images are mapped word by word onto one of the app's digital mushafs.
/// Page files are `<filePrefix>-<page>.jpg` + `<filePrefix>-<page>.json`, bundled (Debug, from DevOnly/)
/// or online in the Cloudflare R2 bucket `hifzworld-scans`.
nonisolated struct ScanEdition: Sendable {
    /// Layouts key on hifzworld-api (`/api/scan_layouts/<key>`) and the R2 folder.
    let key: String
    let filePrefix: String
    /// The digital mushaf the scan's tiles carry word IDs of.
    let mushafID: Int
    let pageCount: Int
    /// Bump with every re-export of the page files so caches refresh.
    let version: String
    /// Folder of page files online; nil until they're uploaded (bundled pages still work).
    let baseURL: URL?
    let title: String
    let shortName: String
    /// Average size of one page (jpg + json), for the download estimate.
    let approximateBytesPerPage: Int64
    let enabledKey: String
    let fullDownloadKey: String
    let cacheFolder: String

    static let taj13 = ScanEdition(
        key: "taj13", filePrefix: "tajscan", mushafID: MushafID.indoPak.rawValue, pageCount: 847, version: "v1",
        baseURL: URL(string: "https://pub-dabf8dea9c6a4f26bc94c2a4db97c735.r2.dev/taj13/v1/"),
        title: "13 Liner Taj (scanned)", shortName: "Taj", approximateBytesPerPage: 240_000,
        enabledKey: "tajScanPreviewEnabled", fullDownloadKey: "tajScanFullDownloadRequested", cacheFolder: "TajScan"
    )

    /// The green King Fahd Complex Madinah print, line for line the same layout as the Uthmani data.
    static let madinah15 = ScanEdition(
        key: "madinah15", filePrefix: "madinahscan", mushafID: MushafID.uthmani.rawValue, pageCount: 604, version: "v1",
        baseURL: URL(string: "https://pub-dabf8dea9c6a4f26bc94c2a4db97c735.r2.dev/madinah15/v1/"),
        title: "15 Liner Madinah (scanned)", shortName: "Madinah", approximateBytesPerPage: 330_000,
        enabledKey: "madinahScanEnabled", fullDownloadKey: "madinahScanFullDownloadRequested", cacheFolder: "MadinahScan"
    )
}

/// One scanned mushaf edition's pages: which are local, downloading them, and the reader's choice to show it.
///
/// Pages come from the app bundle when present, otherwise they are downloaded from the edition's
/// `baseURL`: on demand with the neighbouring pages prefetched, or all at once when the reader opts into
/// the whole-mushaf download.
@MainActor
@Observable
final class ScanStore {
    static let taj = ScanStore(edition: .taj13)
    static let madinah = ScanStore(edition: .madinah15)
    static let all = [taj, madinah]

    /// The scan edition drawn over a digital mushaf, if any.
    static func forMushaf(_ mushafID: Int) -> ScanStore? {
        all.first { $0.edition.mushafID == mushafID }
    }

    let edition: ScanEdition

    enum PageState { case ready, loading, failed }

    /// App page numbers that have a mapped scan (bundled or downloadable).
    let availablePages: Set<Int>
    private let bundledPages: Set<Int>

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: edition.enabledKey) }
    }

    var isAvailable: Bool { !availablePages.isEmpty }

    /// Hand-corrected tiles saved from the web editor (hifzworld-api), preferred over the shipped ones.
    private var savedTiles: [Int: [ScanTile]] = [:]
    /// Pages whose files are on disk / being fetched / failed to fetch (drives re-renders).
    private var loadedPages: Set<Int> = []
    /// When each page last failed to download; the rendered page shows until `retryDelay` passes.
    private var failedPages: [Int: Date] = [:]
    /// Downloads in flight, owned by the store so a page view going away (swiping on, jumping pages)
    /// doesn't cancel them.
    @ObservationIgnored private var downloads: [Int: Task<Bool, Never>] = [:]
    private static let retryDelay: TimeInterval = 20
    @ObservationIgnored private var cache: [Int: ScanPage] = [:]
    @ObservationIgnored private var fetchedLayouts: Set<Int> = []

    private struct PageFile: Decodable {
        let frame: ScanFrame
        let words: [ScanTile]
    }

    private struct SavedLayout: Decodable {
        let tiles: [ScanTile]
    }

    /// Pages with their files local (bundled or downloaded), out of `edition.pageCount`.
    private(set) var downloadedPageCount = 0
    /// The whole-mushaf download is running.
    private(set) var isDownloadingAll = false
    /// Pages the last whole-mushaf run couldn't fetch (offline, app suspended).
    private(set) var fullDownloadFailedCount = 0
    /// The reader asked for the whole mushaf; an interrupted download resumes on its own.
    private(set) var isFullDownloadRequested: Bool {
        didSet { UserDefaults.standard.set(isFullDownloadRequested, forKey: edition.fullDownloadKey) }
    }
    @ObservationIgnored private var fullDownloadTask: Task<Void, Never>?

    var isFullyDownloaded: Bool { downloadedPageCount >= edition.pageCount }
    var remainingPageCount: Int { max(edition.pageCount - downloadedPageCount, 0) }

    /// Application Support rather than Caches: a downloaded mushaf shouldn't vanish when iOS frees space.
    private let cacheDirectory: URL

    private init(edition: ScanEdition) {
        self.edition = edition
        let prefix = edition.filePrefix + "-"
        let jsons = Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
        bundledPages = Set(jsons.compactMap { path in
            let name = (path as NSString).lastPathComponent
            guard name.hasPrefix(prefix) else { return nil }
            return Int(name.dropFirst(prefix.count).dropLast(".json".count))
        })
        let remote: Set<Int> = edition.baseURL == nil ? [] : Set(1...edition.pageCount)
        availablePages = bundledPages.union(remote)
        cacheDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(edition.cacheFolder)/\(edition.version)", isDirectory: true)
        isEnabled = UserDefaults.standard.bool(forKey: edition.enabledKey)
        isFullDownloadRequested = UserDefaults.standard.bool(forKey: edition.fullDownloadKey)
        let bundled = bundledPages
        let dir = cacheDirectory
        downloadedPageCount = (1...edition.pageCount).count {
            bundled.contains($0) || Self.filesOnDisk($0, prefix: edition.filePrefix, in: dir)
        }
        // pages cached before the move to Application Support
        try? FileManager.default.removeItem(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(edition.cacheFolder, isDirectory: true))
    }

    /// Whether this page of the digital mushaf should show the scan (it may still be downloading).
    func showsScan(_ number: Int, mushafID: Int) -> Bool {
        isEnabled && mushafID == edition.mushafID && availablePages.contains(number) && !isFailed(number)
    }

    func state(of number: Int) -> PageState {
        if isFailed(number) { return .failed }
        if cache[number] != nil || loadedPages.contains(number) || bundledPages.contains(number) || filesOnDisk(number) { return .ready }
        return .loading
    }

    /// The scan for a page, when it's on and its files are available locally.
    func page(_ number: Int, mushafID: Int) -> ScanPage? {
        guard showsScan(number, mushafID: mushafID) else { return nil }
        _ = loadedPages      // re-render once a download lands
        if let cached = cache[number] {
            if let saved = savedTiles[number] {
                return ScanPage(image: cached.image, frame: cached.frame, tiles: merged(saved, bundled: cached.tiles))
            }
            return cached
        }
        guard let (jsonURL, imageURL) = localFiles(number),
              let data = try? Data(contentsOf: jsonURL),
              let file = try? JSONDecoder().decode(PageFile.self, from: data),
              let image = UIImage(contentsOfFile: imageURL.path)
        else { return nil }
        let page = ScanPage(image: image, frame: file.frame, tiles: file.words)
        cache[number] = page
        return savedTiles[number].map {
            ScanPage(image: image, frame: file.frame, tiles: merged($0, bundled: file.words))
        } ?? page
    }

    /// Make sure a page's files are local, downloading them if needed.
    func ensure(_ number: Int) async {
        _ = await download(number)?.value
    }

    /// A page's printed image for the mushaf chooser, whether or not the scan is switched on.
    func previewImage(_ number: Int) async -> UIImage? {
        await ensure(number)
        guard let (_, imageURL) = localFiles(number) else { return nil }
        return UIImage(contentsOfFile: imageURL.path)
    }

    /// Fetch the pages around one being read, so swiping doesn't wait.
    func prefetch(around number: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for offset in [1, -1, 2, -2, 3, 4] {
                let n = number + offset
                guard n >= 1, n <= edition.pageCount, let task = download(n) else { continue }
                group.addTask { _ = await task.value }
            }
        }
    }

    // MARK: Whole mushaf

    /// Download every page not yet local, a few at a time. Keeps going while the reader reads on;
    /// pages being read still jump the queue through `ensure`.
    func downloadAll() {
        isFullDownloadRequested = true
        guard !isDownloadingAll, !isFullyDownloaded, edition.baseURL != nil else { return }
        isDownloadingAll = true
        fullDownloadFailedCount = 0
        let background = UIApplication.shared.beginBackgroundTask(withName: "ScanDownload-\(edition.key)")
        fullDownloadTask = Task {
            let missing = (1...edition.pageCount).filter { localFiles($0) == nil }
            var queue = missing[...]
            var failed = 0
            await withTaskGroup(of: Bool.self) { group in
                var inFlight = 0
                while true {
                    while inFlight < 6, !Task.isCancelled, let number = queue.popFirst() {
                        let task = download(number, retryingFailed: true)
                        group.addTask { await task?.value ?? true }
                        inFlight += 1
                    }
                    guard let ok = await group.next() else { break }
                    inFlight -= 1
                    if !ok { failed += 1 }
                }
            }
            if !Task.isCancelled { fullDownloadFailedCount = failed }
            isDownloadingAll = false
            fullDownloadTask = nil
            UIApplication.shared.endBackgroundTask(background)
        }
    }

    /// Stop the whole-mushaf download; pages already fetched stay, and reading falls back to on demand.
    func cancelDownloadAll() {
        isFullDownloadRequested = false
        fullDownloadFailedCount = 0
        fullDownloadTask?.cancel()
    }

    /// Pick an interrupted whole-mushaf download back up (app relaunched or back from the background).
    func resumeDownloadAllIfNeeded() {
        guard isEnabled, isFullDownloadRequested, !isDownloadingAll, !isFullyDownloaded else { return }
        downloadAll()
    }

    /// Whether the device has room for the rest of the mushaf, with some headroom.
    func hasRoomForFullDownload() -> Bool {
        let needed = Int64(remainingPageCount) * edition.approximateBytesPerPage + 100_000_000
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let free = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return true }
        return free >= needed
    }

    private func isFailed(_ number: Int) -> Bool {
        guard let failedAt = failedPages[number] else { return false }
        return Date().timeIntervalSince(failedAt) < Self.retryDelay
    }

    /// The download for a page, started if it isn't local or already coming; nil when there's nothing to fetch.
    private func download(_ number: Int, retryingFailed: Bool = false) -> Task<Bool, Never>? {
        guard availablePages.contains(number), localFiles(number) == nil, retryingFailed || !isFailed(number),
              let base = edition.baseURL else { return nil }
        if let running = downloads[number] { return running }
        let task = Task { [weak self] in
            let ok = await Self.fetchFiles(number, prefix: edition.filePrefix, from: base, into: cacheDirectory)
            guard let self else { return ok }
            downloads[number] = nil
            if ok {
                // the network is back: give pages that failed meanwhile another go straight away
                failedPages.removeAll()
                loadedPages.insert(number)
                downloadedPageCount += 1
            } else {
                // offline or missing: show the rendered page for now, try again after `retryDelay`
                failedPages[number] = Date()
            }
            return ok
        }
        downloads[number] = task
        return task
    }

    /// Download a page's json + jpg into the cache, retrying briefly so a blip doesn't drop to the rendered page.
    nonisolated private static func fetchFiles(_ number: Int, prefix: String, from base: URL, into dir: URL) async -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var backup = URLResourceValues()
                backup.isExcludedFromBackup = true
                var excluded = dir
                try? excluded.setResourceValues(backup)
                // jpg first: the page counts as on disk once its json lands
                for ext in ["jpg", "json"] {
                    let name = "\(prefix)-\(number).\(ext)"
                    let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent(name))
                    guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                        throw URLError(.badServerResponse)
                    }
                    try data.write(to: dir.appendingPathComponent(name), options: .atomic)
                }
                return true
            } catch {
                continue
            }
        }
        return false
    }

    private func filesOnDisk(_ number: Int) -> Bool {
        Self.filesOnDisk(number, prefix: edition.filePrefix, in: cacheDirectory)
    }

    nonisolated private static func filesOnDisk(_ number: Int, prefix: String, in dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(prefix)-\(number).jpg").path)
            && FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(prefix)-\(number).json").path)
    }

    private func localFiles(_ number: Int) -> (URL, URL)? {
        let name = "\(edition.filePrefix)-\(number)"
        if bundledPages.contains(number),
           let json = Bundle.main.url(forResource: name, withExtension: "json"),
           let jpg = Bundle.main.url(forResource: name, withExtension: "jpg") {
            return (json, jpg)
        }
        guard filesOnDisk(number) else { return nil }
        return (cacheDirectory.appendingPathComponent("\(name).json"), cacheDirectory.appendingPathComponent("\(name).jpg"))
    }

    /// Saved layouts store positions and word IDs only: take a spilled word's page + text from the bundled
    /// tile with the same word, and keep the bundled surah headers if the saved layout predates them.
    private func merged(_ saved: [ScanTile], bundled: [ScanTile]) -> [ScanTile] {
        let spilled = Dictionary(
            bundled.compactMap { tile in tile.page != nil ? tile.ids.first.map { ($0, tile) } : nil },
            uniquingKeysWith: { first, _ in first }
        )
        var tiles = saved.map { tile -> ScanTile in
            guard tile.page == nil, let id = tile.ids.first, let source = spilled[id] else { return tile }
            return ScanTile(ids: tile.ids, surah: tile.surah, page: source.page, words: source.words,
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
            .appendingPathComponent("api/scan_layouts/\(edition.key)/\(number)")
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
