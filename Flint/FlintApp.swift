import SwiftUI

@main
struct FlintApp: App {
    @StateObject private var model = AppModel(
        bookmarkStore: VaultBookmarkStore(),
        fileService: VaultFileService()
    )

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
