import AVFoundation
import Foundation
import Speech
import SwiftUI

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case thai = "th-TH"
    case englishUS = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case chinese = "zh-CN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thai:
            return "ไทย"
        case .englishUS:
            return "English (US)"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .chinese:
            return "中文"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var languageCode: String {
        switch self {
        case .thai:
            return "th"
        case .englishUS:
            return "en"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .chinese:
            return "zh"
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
    private let localTranslator = LocalPhraseTranslator()

    func startListening() async {
        errorMessage = nil
        translatedText = ""
        partialTranscript = ""

        guard await requestPermissions() else { return }

        speechRecognizer = SFSpeechRecognizer(locale: sourceLanguage.locale)
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
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

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

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
        guard let recognitionRequest = recognitionRequest else { throw TranslatorError.unableToCreateRecognitionRequest }
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
            guard let self = self else { return }
            Task { @MainActor in
                if let result = result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    self.scheduleTranslation(for: self.partialTranscript)
                }
                if let error = error {
                    self.errorMessage = "Speech recognition error: \(error.localizedDescription)"
                    self.stopListening()
                }
            }
        }
    }

    private func scheduleTranslation(for text: String) {
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
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

        translatedText = localTranslator.translate(cleanText, from: sourceLanguage, to: targetLanguage)
        statusMessage = "แปลภายในเครื่องด้วยพจนานุกรมตัวอย่างแล้ว"
    }
}

struct LocalPhraseTranslator {
    private let phraseMap: [String: [String: String]] = [
        "en:th": [
            "hello": "สวัสดี",
            "hello world": "สวัสดีชาวโลก",
            "thank you": "ขอบคุณ",
            "good morning": "อรุณสวัสดิ์",
            "how are you": "คุณสบายดีไหม",
            "where are you": "คุณอยู่ที่ไหน"
        ],
        "th:en": [
            "สวัสดี": "Hello",
            "ขอบคุณ": "Thank you",
            "อรุณสวัสดิ์": "Good morning",
            "คุณสบายดีไหม": "How are you?",
            "คุณอยู่ที่ไหน": "Where are you?"
        ],
        "en:ja": [
            "hello": "こんにちは",
            "thank you": "ありがとうございます",
            "good morning": "おはようございます"
        ],
        "en:ko": [
            "hello": "안녕하세요",
            "thank you": "감사합니다",
            "good morning": "좋은 아침입니다"
        ],
        "en:zh": [
            "hello": "你好",
            "thank you": "谢谢",
            "good morning": "早上好"
        ]
    ]

    func translate(_ text: String, from source: SupportedLanguage, to target: SupportedLanguage) -> String {
        guard source != target else { return text }

        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(source.languageCode):\(target.languageCode)"

        if let phrase = phraseMap[key]?[normalized] {
            return phrase
        }

        return "[\(source.languageCode)→\(target.languageCode)] \(text)"
    }
}

enum TranslatorError: LocalizedError {
    case unableToCreateRecognitionRequest

    var errorDescription: String? {
        switch self {
        case .unableToCreateRecognitionRequest:
            return "ไม่สามารถสร้าง speech recognition request ได้"
        }
    }
}
