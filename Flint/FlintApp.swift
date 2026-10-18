import SwiftUI

@main
struct FlintApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PlatformEvidence.shared.start()
        RuntimeMonitoring.start()
    }

    @StateObject private var model = AppModel(
        bookmarkStore: VaultBookmarkStore(),
        fileService: VaultFileService()
    )

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    RuntimeMonitoring.monitor.setActive(phase == .active)
                    ForegroundClock.shared.setActive(phase == .active)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    DebugLog.shared.observe(.memoryWarning)
                }
        }
    }
}
