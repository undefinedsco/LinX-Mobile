import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme

    let isBusy: Bool
    let errorMessage: String?
    let onLogin: () -> Void

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.14, green: 0.11, blue: 0.08),
                    Color(red: 0.07, green: 0.17, blue: 0.18),
                    Color(red: 0.04, green: 0.07, blue: 0.13),
                ]
                : [
                    Color(red: 0.96, green: 0.90, blue: 0.78),
                    Color(red: 0.80, green: 0.89, blue: 0.84),
                    Color(red: 0.90, green: 0.94, blue: 0.97),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headingColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.primary
    }

    private var supportingTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.78) : Color.secondary
    }

    private var featureCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.42)
    }

    private var featureCardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.24)
    }

    var body: some View {
        ZStack {
            backgroundGradient
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("LinX")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(headingColor)
                    Text("Official cloud login, Pod-backed chat history, and one native iOS surface.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(supportingTextColor)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("OIDC authorization code + PKCE", systemImage: "lock.shield")
                    Label("Chat history synced through your Pod", systemImage: "tray.full")
                    Label("OpenAI-compatible LinX cloud runtime", systemImage: "bolt.horizontal")
                }
                .font(.subheadline.weight(.medium))
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(featureCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(featureCardStroke, lineWidth: 1)
                )

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
