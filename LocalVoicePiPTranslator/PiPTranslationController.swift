import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UIKit

@MainActor
final class PiPTranslationController: NSObject, ObservableObject {
    @Published var isPictureInPictureActive = false
    @Published var isPictureInPicturePossible = false

    let displayLayer = AVSampleBufferDisplayLayer()

    private var pipController: AVPictureInPictureController?
    private var frameTimer: Timer?
    private var currentText = "คำแปลจะแสดงที่นี่"
    private var frameIndex: Int64 = 0
    private let frameDuration = CMTime(value: 1, timescale: 2)
    private let renderSize = CGSize(width: 1280, height: 720)

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        configurePictureInPicture()
        startRendering()
    }

    func update(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = trimmed.isEmpty ? "กำลังรอคำแปล..." : trimmed
        enqueueFrame()
    }

    func togglePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let pipController = pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    private func configurePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        pipController = AVPictureInPictureController(contentSource: source)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        isPictureInPicturePossible = pipController?.isPictureInPicturePossible ?? false
    }

    private func startRendering() {
        enqueueFrame()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.enqueueFrame()
            }
        }
    }

    private func enqueueFrame() {
        guard let sampleBuffer = makeSampleBuffer(text: currentText) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
        frameIndex += 1
    }

    private func makeSampleBuffer(text: String) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let rect = CGRect(origin: .zero, size: renderSize)
        UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1).setFill()
        UIRectFill(rect)

        let gradientColors = [UIColor.systemIndigo.withAlphaComponent(0.95).cgColor, UIColor.systemTeal.withAlphaComponent(0.65).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: renderSize.width, y: renderSize.height), options: [])
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ]
        NSString(string: "Live Translation").draw(at: CGPoint(x: 64, y: 56), withAttributes: titleAttributes)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]
        let textRect = CGRect(x: 96, y: 190, width: renderSize.width - 192, height: 380)
        NSString(string: text).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttributes, context: nil)

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        guard let formatDescription = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex)),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

extension PiPTranslationController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPictureInPictureActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPictureInPictureActive = false }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.isPictureInPictureActive = false }
    }
}

extension PiPTranslationController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        true
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

struct PiPPreviewView: UIViewRepresentable {
    let controller: PiPTranslationController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.displayLayer.frame = view.bounds
        view.layer.addSublayer(controller.displayLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.displayLayer.frame = uiView.bounds
    }
}
