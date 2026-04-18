import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView("Loading Flint…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .onboarding:
                VaultOnboardingView(model: model)
            case .ready:
                VaultBrowserView(model: model)
            }
        }
        .task {
            await model.bootstrap()
        }
        .alert(
            "Flint",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearAlert()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}
