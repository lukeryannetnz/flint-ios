import Foundation

protocol VaultBookmarkStoring {
    func loadBookmarkData() -> Data?
    func saveBookmarkData(_ data: Data)
    func clearBookmarkData()
    func makeBookmark(for url: URL, request: ProviderRequest) async throws -> Data
    func resolveBookmarkData(_ data: Data, request: ProviderRequest) async throws -> URL
}

final class VaultBookmarkStore: VaultBookmarkStoring {
    private let userDefaults: UserDefaults
    private let executor: ProviderExecutor
    private let key = "flint.vaultBookmark"

    init(userDefaults: UserDefaults = .standard, executor: ProviderExecutor = .shared) {
        self.userDefaults = userDefaults
        self.executor = executor
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

    func makeBookmark(for url: URL, request: ProviderRequest) async throws -> Data {
        return try await executor.execute(request, step: .bookmarkCreate) { _ in
            try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    func resolveBookmarkData(_ data: Data, request: ProviderRequest) async throws -> URL {
        return try await executor.execute(request, step: .bookmarkResolve) { _ in
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
