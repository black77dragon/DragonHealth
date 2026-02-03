import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechCaptureService: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var sessionPrefix: String = ""
    private var suppressNextCancellationError: Bool = false

    func start(localeIdentifier: String) {
        Task {
            await startRecording(localeIdentifier: localeIdentifier)
        }
    }

    func stop() {
        errorMessage = nil
        suppressNextCancellationError = true
        stopRecording()
    }

    func restart(localeIdentifier: String) {
        transcript = ""
        start(localeIdentifier: localeIdentifier)
    }

    private func startRecording(localeIdentifier: String) async {
        suppressNextCancellationError = true
        stopRecording()
        errorMessage = nil

        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            errorMessage = "Speech recognition permission not granted."
            return
        }

        let microphoneAuthorized = await requestMicrophoneAuthorization()
        guard microphoneAuthorized else {
            errorMessage = "Microphone permission not granted."
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            errorMessage = "Selected language is not supported on this device."
            return
        }

        guard recognizer.isAvailable else {
            errorMessage = "Speech recognizer is currently unavailable."
            return
        }

        speechRecognizer = recognizer
        let trimmedPrefix = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionPrefix = trimmedPrefix.isEmpty ? "" : "\(trimmedPrefix) "

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    let updated = self.sessionPrefix + result.bestTranscription.formattedString
                    self.transcript = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if result.isFinal {
                    Task { @MainActor in
                        self.stopRecording()
                    }
                }
            }
            if let error {
                Task { @MainActor in
                    let isCancellation = self.isCancellationError(error)
                    if self.suppressNextCancellationError && isCancellation {
                        self.suppressNextCancellationError = false
                        return
                    }
                    self.suppressNextCancellationError = false
                    self.errorMessage = error.localizedDescription
                    self.stopRecording()
                }
            }
        }

        isRecording = true
    }

    private func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "SFSpeechRecognizerErrorDomain", nsError.code == 216 {
            return true
        }
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 209 {
            return true
        }
        let description = nsError.localizedDescription.lowercased()
        return description.contains("cancel") || description.contains("cancell")
    }

    private func requestSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        if #available(iOS 17.0, *) {
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            let audioSession = AVAudioSession.sharedInstance()
            switch audioSession.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    audioSession.requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }
            @unknown default:
                return false
            }
        }
    }
}
