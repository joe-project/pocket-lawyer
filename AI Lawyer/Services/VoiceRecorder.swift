import Foundation
import Combine
import AVFoundation
import Speech

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var permissionGranted = false
    @Published var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    func requestPermissions() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            if #available(iOS 17.0, *) {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    AVAudioApplication.requestRecordPermission { _ in cont.resume() }
                }
            } else {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    session.requestRecordPermission { _ in cont.resume() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
            }
        }
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            micGranted = session.recordPermission == .granted
        }
        permissionGranted = micGranted && SFSpeechRecognizer.authorizationStatus() == .authorized
        if !permissionGranted {
            errorMessage = "Microphone and speech recognition access are needed. Enable them in Settings."
        }
    }

    func startRecording() async -> Bool {
        await requestPermissions()
        guard permissionGranted else { return false }
        let dir = FileManager.default.temporaryDirectory
        recordingURL = dir.appendingPathComponent(UUID().uuidString + ".m4a")
        guard let url = recordingURL else { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Stops recording and returns the transcript as text (empty string if nothing was said or recognition failed).
    func stopRecordingAndTranscribe() async -> String {
        guard let recorder = audioRecorder, let url = recordingURL else {
            isRecording = false
            return ""
        }
        recorder.stop()
        audioRecorder = nil
        let urlToUse = url
        recordingURL = nil
        isRecording = false
        let transcript = await transcribe(url: urlToUse)
        return transcript
    }

    private func transcribe(url: URL) async -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            return ""
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { cont in
            var resolved = false
            let lock = NSLock()
            func resumeOnce(_ text: String) {
                lock.lock()
                defer { lock.unlock() }
                guard !resolved else { return }
                resolved = true
                cont.resume(returning: text)
            }
            recognizer.recognitionTask(with: request) { result, _ in
                guard result?.isFinal == true else { return }
                resumeOnce(result?.bestTranscription.formattedString ?? "")
            }
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                resumeOnce("")
            }
        }
    }
}
