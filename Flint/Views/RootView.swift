import SwiftUI
import UIKit

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingScreenView(model: model)
            case .onboarding:
                VaultOnboardingView(model: model)
                    .onAppear { DebugLog.shared.observe(.firstUsableScreen) }
            case .restorationRecovery, .providerRecovery:
                VStack(spacing: 20) {
                    Text("Vault recovery")
                        .font(.title2.bold())
                    Text(model.recoveryMessage)
                        .multilineTextAlignment(.center)
                    Button("Retry previous vault") { Task { await model.retryRestoration() } }
                        .disabled(model.isBusy)
                    Button("Choose another vault") { Task { await model.chooseAnotherVault() } }
                    Button("Export diagnostics") { Task { await model.exportDiagnostics() } }
                        .disabled(model.isExportingDiagnostics)
                }
                .padding(24)
                .onAppear { DebugLog.shared.observe(.firstUsableScreen) }
            case .ready:
                VaultBrowserView(model: model)
                    .onAppear { DebugLog.shared.observe(.firstUsableScreen) }
            }
        }
        .sheet(item: $model.diagnosticShare, onDismiss: { model.finishDiagnosticShare() }) { item in
            DiagnosticActivityView(url: item.url)
        }
        .safeAreaInset(edge: .bottom) {
            #if DEBUG
            if ImageWorkflowTestSupport.active {
                VStack {
                    Text(ImageWorkflowTestSupport.snapshot(model: model))
                        .font(.system(size: 1))
                        .accessibilityIdentifier("test.persistence")
                    Button("Remove import source") {
                        if let source = ImageWorkflowTestSupport.sourceURL {
                            do { try FileManager.default.removeItem(at: source); model.objectWillChange.send() }
                            catch { model.alertMessage = error.localizedDescription }
                        }
                    }
                    .accessibilityIdentifier("test.remove-source")
                }
            }
            #endif
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
            #if DEBUG
            if ImageWorkflowSaveFailure.enabled {
                Button("Retry save") {
                    ImageWorkflowSaveFailure.removed = true
                    model.clearAlert()
                    Task { await model.saveCurrentNoteIfNeeded() }
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

private struct LoadingScreenView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.05, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 1.0, green: 0.42, blue: 0.18).opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: -240)

            Circle()
                .fill(Color(red: 0.14, green: 0.77, blue: 0.92).opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 100)
                .offset(x: -130, y: 250)

            VStack(spacing: 22) {
                Spacer()

                Image("FlintBrandBoard")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.32), radius: 28, y: 18)

                VStack(spacing: 10) {
                    Text("flint")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Opening your markdown vault")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.82))

                    Text("Restoring your last workspace and preparing your notes.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text(model.isSlow ? "The provider is taking longer than usual…" : "Loading Flint…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial.opacity(0.35), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }

                Text(model.loadingStage.loadingLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Cancel loading") { model.cancelLoading() }
                    .accessibilityIdentifier("vault.loading.cancel")
                Button("Export diagnostics") { Task { await model.exportDiagnostics() } }
                    .disabled(model.isExportingDiagnostics)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DiagnosticActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private extension DebugLogStep {
    var loadingLabel: String {
        switch self {
        case .bookmarkLoad, .bookmarkResolve: return "Checking saved vault"
        case .bookmarkCreate: return "Saving vault selection"
        case .securityScope: return "Preparing vault access"
        case .coordinationRead, .coordinationWrite: return "Waiting for file access"
        case .enumeration, .metadata, .preview: return "Discovering notes"
        case .noteRead, .fileRead: return "Reading note content"
        case .noteCreate, .vaultCreate, .fileWrite: return "Creating files"
        default: return "Opening vault"
        }
    }
}
