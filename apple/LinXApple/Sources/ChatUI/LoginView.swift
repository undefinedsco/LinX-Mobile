import SwiftUI

struct LoginView: View {
    let isBusy: Bool
    let errorMessage: String?
    let onLogin: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.90, blue: 0.78),
                    Color(red: 0.80, green: 0.89, blue: 0.84),
                    Color(red: 0.90, green: 0.94, blue: 0.97),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("LinX")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("Official cloud login, Pod-backed chat history, and one native iOS surface.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("OIDC authorization code + PKCE", systemImage: "lock.shield")
                    Label("Chat history synced through your Pod", systemImage: "tray.full")
                    Label("Streaming chat on LinX cloud runtime", systemImage: "bolt.horizontal")
                }
                .font(.subheadline.weight(.medium))
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if let errorMessage, errorMessage.isEmpty == false {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: onLogin) {
                    HStack {
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isBusy ? "Connecting…" : "Continue with LinX Cloud")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.07, green: 0.46, blue: 0.41))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .disabled(isBusy)

                Spacer()
            }
            .padding(24)
        }
    }
}
