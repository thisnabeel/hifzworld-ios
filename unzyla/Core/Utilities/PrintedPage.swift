import Foundation

/// The 13-line IndoPak data numbers its pages one lower than the printed Taj mushaf
/// (data page 1 is printed page 2). Page numbers shown to people use the printed numbering;
/// everything stored or sent to the API keeps the data numbering.
@MainActor
enum PrintedPage {
    nonisolated static func offset(mushafID: Int) -> Int {
        mushafID == MushafID.indoPak.rawValue ? 1 : 0
    }

    /// Data page → the number printed on that page.
    nonisolated static func display(_ page: Int, mushafID: Int) -> Int {
        page + offset(mushafID: mushafID)
    }

    /// Data page → printed number, for the mushaf currently selected.
    static func display(_ page: Int) -> Int {
        display(page, mushafID: PreferencesStore.shared.mushafID)
    }

    /// A printed page number someone typed → data page.
    nonisolated static func dataPage(fromDisplay page: Int, mushafID: Int) -> Int {
        page - offset(mushafID: mushafID)
    }
}
