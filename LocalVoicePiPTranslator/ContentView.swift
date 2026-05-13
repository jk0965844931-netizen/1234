import AVKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: SpeechTranslationCoordinator
    @StateObject private var pipController = PiPTranslationController()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusCard
                    languageCard
                    transcriptCard
                    pipCard
                }
                .padding()
            }
            .navigationTitle("Local Voice PiP")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(coordinator.isListening ? "หยุด" : "เริ่ม") {
                        Task { await toggleListening() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onChange(of: coordinator.translatedText) { _, newValue in
                pipController.update(text: newValue.isEmpty ? coordinator.partialTranscript : newValue)
            }
            .onChange(of: coordinator.partialTranscript) { _, newValue in
                guard coordinator.translatedText.isEmpty else { return }
                pipController.update(text: newValue)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(coordinator.isListening ? "กำลังฟังเสียง" : "พร้อมใช้งาน", systemImage: coordinator.isListening ? "waveform" : "mic")
                .font(.headline)
            Text(coordinator.statusMessage)
                .foregroundStyle(.secondary)
            if let error = coordinator.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ภาษา")
                .font(.headline)
            Picker("ต้นทาง", selection: $coordinator.sourceLanguage) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Picker("ปลายทาง", selection: $coordinator.targetLanguage) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Text("ใช้ Speech framework สำหรับถอดเสียง และ Translation framework ของ iOS สำหรับแปลแบบ on-device เมื่อระบบรองรับ")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ผลลัพธ์")
                .font(.headline)
            Text("เสียงที่ได้ยิน")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(coordinator.partialTranscript.isEmpty ? "ยังไม่มีข้อความ" : coordinator.partialTranscript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            Text("คำแปล")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(coordinator.translatedText.isEmpty ? "รอคำแปล" : coordinator.translatedText)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var pipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Picture in Picture")
                .font(.headline)
            PiPPreviewView(controller: pipController)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottomTrailing) {
                    Button(pipController.isPictureInPictureActive ? "ปิด PiP" : "เปิด PiP") {
                        pipController.togglePictureInPicture()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            Text("PiP บน iOS ต้องอาศัยคอนเทนต์วิดีโอ แอพนี้จึงเรนเดอร์ข้อความแปลเป็นเฟรมวิดีโอสำหรับหน้าต่างลอย")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggleListening() async {
        if coordinator.isListening {
            coordinator.stopListening()
        } else {
            await coordinator.startListening()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SpeechTranslationCoordinator())
}
