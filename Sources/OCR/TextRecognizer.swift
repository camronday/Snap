import CoreGraphics
import Vision

/// Recognises text in an image via Vision, returning the lines joined in
/// reading order.
enum TextRecognizer {
    @concurrent
    static func recognize(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            let results = try await request.perform(on: image)
            return results
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        } catch {
            return ""
        }
    }
}
