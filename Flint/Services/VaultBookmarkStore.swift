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
        let action = DebugLog.shared.begin(.bookmarkLoad)
        defer { action.finish(.success) }
        return userDefaults.data(forKey: key)
    }

    func saveBookmarkData(_ data: Data) {
        userDefaults.set(data, forKey: key)
    }

    func clearBookmarkData() {
        userDefaults.removeObject(forKey: key)
    }

    func makeBookmark(for url: URL) throws -> Data {
        return try DebugLog.shared.measure(.bookmarkCreate, file: url) {
            try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    func resolveBookmarkData(_ data: Data) throws -> URL {
        return try DebugLog.shared.measure(.bookmarkResolve) {
            var isStale = false
            return try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }
}
