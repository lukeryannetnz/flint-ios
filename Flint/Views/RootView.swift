import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingScreenView()
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

private struct LoadingScreenView: View {
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

                    Text("Loading Flint…")
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

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
