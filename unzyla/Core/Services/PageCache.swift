import Foundation

actor PageCache {
    private var pages: [Int: MushafPage] = [:]
    private var mushafID: Int?

    func setMushaf(_ id: Int) {
        if mushafID != id {
            pages.removeAll()
            mushafID = id
        }
    }

    func page(_ position: Int) -> MushafPage? {
        pages[position]
    }

    func store(_ page: MushafPage) {
        pages[page.position] = page
    }

    func removeAll() {
        pages.removeAll()
    }
}
