import Foundation

protocol VaultBookmarkStoring {
    func loadBookmarkData() -> Data?
    func saveBookmarkData(_ data: Data)
    func clearBookmarkData()
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmarkData(_ data: Data) throws -> URL
}

final class VaultBookmarkStore: VaultBookmarkStoring {
    private let userDefaults: UserDefaults
    private let key = "flint.vaultBookmark"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadBookmarkData() -> Data? {
        userDefaults.data(forKey: key)
    }

    func saveBookmarkData(_ data: Data) {
        userDefaults.set(data, forKey: key)
    }

    func clearBookmarkData() {
        userDefaults.removeObject(forKey: key)
    }

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmarkData(_ data: Data) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
