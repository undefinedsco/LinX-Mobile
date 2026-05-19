import SwiftUI

struct SpeechInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: SpeechRecognitionViewModel

    private let onTranscript: (String) -> Void

    init(
        viewModel: SpeechRecognitionViewModel = SpeechRecognitionViewModel(),
        onTranscript: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onTranscript = onTranscript
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                statusMark
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(LinxChatPalette.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                transcriptView

                Spacer(minLength: 8)

                controls
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close voice input")
                }
            }
            .task {
                if viewModel.state == .idle {
                    await viewModel.startRecording()
                }
            }
            .background {
                LinxChatPalette.background(for: colorScheme)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var transcriptView: some View {
        if case .completed(let result) = viewModel.state {
            ScrollView {
                Text(result.text.isEmpty ? "No speech was detected." : result.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 100, maxHeight: 180)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinxChatPalette.surface(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LinxChatPalette.stroke(for: colorScheme), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.state {
        case .idle:
            primaryButton(title: "Start Recording", systemImage: "mic.fill") {
                Task {
                    await viewModel.startRecording()
                }
            }
        case .requestingPermission, .preparingAudio, .loadingModel, .transcribing:
            Button(role: .cancel) {
                viewModel.cancel()
                dismiss()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .recording:
            primaryButton(title: "Stop", systemImage: "stop.fill", tint: LinxChatPalette.warning) {
                Task {
                    await viewModel.stopRecording()
                }
            }
        case .completed:
            VStack(spacing: 10) {
                primaryButton(title: "Use Transcript", systemImage: "text.badge.checkmark") {
                    onTranscript(viewModel.transcribedText)
                    dismiss()
                }
                .disabled(viewModel.transcribedText.isEmpty)

                Button {
                    Task {
                        await viewModel.startRecording()
                    }
                } label: {
                    Label("Record Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .failed:
            VStack(spacing: 10) {
                primaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.startRecording()
                    }
                }

                Button(role: .cancel) {
                    viewModel.cancel()
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var statusMark: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.16))
                .frame(width: 96, height: 96)

            Circle()
                .stroke(statusColor.opacity(0.24), lineWidth: 1)
                .frame(width: 96, height: 96)

            Group {
                switch viewModel.state {
                case .requestingPermission, .preparingAudio, .loadingModel, .transcribing:
                    ProgressView()
                        .controlSize(.large)
                        .tint(statusColor)
                default:
                    Image(systemName: statusIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func primaryButton(
        title: String,
        systemImage: String,
        tint: Color = LinxChatPalette.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
    }

    private var title: String {
        switch viewModel.state {
        case .idle:
            return "Ready"
        case .requestingPermission:
            return "Requesting microphone"
        case .recording:
            return "Recording"
        case .preparingAudio:
            return "Preparing audio"
        case .loadingModel:
            return "Loading speech model"
        case .transcribing:
            return "Transcribing"
        case .completed:
            return "Transcript ready"
        case .failed:
            return "Voice input failed"
        }
    }

    private var detail: String {
        switch viewModel.state {
        case .idle:
            return "Tap start to begin a local transcription session."
        case .requestingPermission:
            return "LinX needs microphone access before recording."
        case .recording:
            return "Speak naturally, then stop when finished."
        case .preparingAudio:
            return "Converting the recording for local speech recognition."
        case .loadingModel:
            return "Checking the bundled whisper model."
        case .transcribing:
            return "Running local speech-to-text on this device."
        case .completed(let result):
            let seconds = Int(result.audioDuration.rounded())
            return "Captured \(seconds) seconds. Review the text before sending."
        case .failed(let message):
            return message
        }
    }

    private var statusIcon: String {
        switch viewModel.state {
        case .idle:
            return "mic"
        case .recording:
            return "waveform"
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        case .requestingPermission, .preparingAudio, .loadingModel, .transcribing:
            return "hourglass"
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .failed:
            return LinxChatPalette.warning
        case .completed:
            return LinxChatPalette.accent
        case .recording:
            return LinxChatPalette.blue
        case .idle, .requestingPermission, .preparingAudio, .loadingModel, .transcribing:
            return LinxChatPalette.accent
        }
    }
}
