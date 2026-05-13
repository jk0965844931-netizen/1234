import AVFoundation
import Foundation
import Speech
import SwiftUI
#if canImport(Translation)
import Translation
#endif

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case thai = "th-TH"
    case englishUS = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chinese = "zh-CN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thai: "ไทย"
        case .englishUS: "English (US)"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chinese: "中文"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var translationLanguageCode: String {
        switch self {
        case .thai: "th"
        case .englishUS: "en"
        case .japanese: "ja"
        case .korean: "ko"
        case .chinese: "zh"
        }
    }
}

@MainActor
final class SpeechTranslationCoordinator: ObservableObject {
    @Published var sourceLanguage: SupportedLanguage = .englishUS
    @Published var targetLanguage: SupportedLanguage = .thai
    @Published var partialTranscript = ""
    @Published var translatedText = ""
    @Published var statusMessage = "กดเริ่มเพื่อฟังเสียงจากไมโครโฟน"
    @Published var errorMessage: String?
    @Published var isListening = false

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var translationTask: Task<Void, Never>?

    func startListening() async {
        errorMessage = nil
        translatedText = ""
        partialTranscript = ""

        guard await requestPermissions() else { return }

        speechRecognizer = SFSpeechRecognizer(locale: sourceLanguage.locale)
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer สำหรับภาษานี้ยังไม่พร้อมใช้งาน"
            return
        }

        do {
            try configureAudioSession()
            try startRecognition(with: speechRecognizer)
            isListening = true
            statusMessage = "กำลังฟังและแปลจาก \(sourceLanguage.title) เป็น \(targetLanguage.title)"
        } catch {
            errorMessage = "เริ่มฟังเสียงไม่ได้: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        translationTask?.cancel()
        translationTask = nil
        isListening = false
        statusMessage = "หยุดฟังแล้ว"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechGranted else {
            errorMessage = "กรุณาอนุญาต Speech Recognition ใน Settings"
            return false
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard microphoneGranted else {
            errorMessage = "กรุณาอนุญาต Microphone ใน Settings"
            return false
        }

        return true
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition(with recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw TranslatorError.unableToCreateRecognitionRequest }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    self.scheduleTranslation(for: self.partialTranscript)
                }
                if let error {
                    self.errorMessage = "Speech recognition error: \(error.localizedDescription)"
                    self.stopListening()
                }
            }
        }
    }

    private func scheduleTranslation(for text: String) {
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self?.translate(text)
        }
    }

    private func translate(_ text: String) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            translatedText = ""
            return
        }

        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            do {
                let session = TranslationSession(
                    installedSource: Locale.Language(identifier: sourceLanguage.translationLanguageCode),
                    target: Locale.Language(identifier: targetLanguage.translationLanguageCode)
                )
                let response = try await session.translate(cleanText)
                translatedText = response.targetText
                statusMessage = "แปลภายในเครื่องสำเร็จ"
                return
            } catch {
                errorMessage = "แปลด้วย Translation framework ไม่สำเร็จ: \(error.localizedDescription)"
            }
        }
        #endif

        translatedText = cleanText
        statusMessage = "อุปกรณ์นี้ยังไม่รองรับ Translation framework จึงแสดงข้อความต้นฉบับแทน"
    }
}

enum TranslatorError: LocalizedError {
    case unableToCreateRecognitionRequest

    var errorDescription: String? {
        switch self {
        case .unableToCreateRecognitionRequest:
            "ไม่สามารถสร้าง speech recognition request ได้"
        }
    }
}
