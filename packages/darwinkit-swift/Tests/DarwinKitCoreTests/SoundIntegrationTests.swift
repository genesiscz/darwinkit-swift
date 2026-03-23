import AVFoundation
import Foundation
import Testing
@testable import DarwinKitCore

@Suite("Sound Analysis Integration")
struct SoundIntegrationTests {

    /// Generate a short WAV file with a sine wave tone for testing.
    private func generateTestAudio() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("darwinkit_test_\(UUID().uuidString).wav")

        let sampleRate: Double = 44100
        let duration: Double = 5.0
        let frequency: Double = 440.0  // A4 note
        let totalSamples = Int(sampleRate * duration)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples))!
        buffer.frameLength = AVAudioFrameCount(totalSamples)

        let data = buffer.floatChannelData![0]
        for i in 0..<totalSamples {
            data[i] = Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }

        try audioFile.write(from: buffer)

        return url
    }

    @Test("classify returns classifications for audio file")
    func classifyAudioFile() throws {
        let url = try generateTestAudio()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = AppleSoundProvider()
        let result = try provider.classify(path: url.path, topN: 10)

        // SoundAnalysis should produce results for a 5-second sine wave tone
        #expect(!result.classifications.isEmpty)
        if let first = result.classifications.first {
            #expect(first.confidence > 0)
            #expect(!first.identifier.isEmpty)
        }
    }

    @Test("classifyAt returns results with time_range")
    func classifyAtTimeRange() throws {
        let url = try generateTestAudio()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = AppleSoundProvider()
        let result = try provider.classifyAt(path: url.path, start: 0.0, duration: 1.0, topN: 3)

        #expect(result.timeRange?.start == 0.0)
        #expect(result.timeRange?.duration == 1.0)
    }

    @Test("categories returns 300+ entries")
    func categoriesCount() throws {
        let provider = AppleSoundProvider()
        let cats = try provider.categories()

        #expect(cats.count > 300)
        #expect(cats.contains("speech"))
        #expect(cats.contains("music"))
    }

    @Test("categories are sorted alphabetically")
    func categoriesSorted() throws {
        let provider = AppleSoundProvider()
        let cats = try provider.categories()

        let sorted = cats.sorted()
        #expect(cats == sorted)
    }

    @Test("isAvailable returns true on macOS 12+")
    func isAvailable() {
        let provider = AppleSoundProvider()
        #expect(provider.isAvailable() == true)
    }

    @Test("classify throws on nonexistent file")
    func classifyNonexistent() {
        let provider = AppleSoundProvider()

        #expect(throws: JsonRpcError.self) {
            try provider.classify(path: "/tmp/nonexistent_audio.wav", topN: 5)
        }
    }

    @Test("classifyAt validates start >= 0")
    func classifyAtNegativeStart() throws {
        let url = try generateTestAudio()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = AppleSoundProvider()

        #expect(throws: JsonRpcError.self) {
            try provider.classifyAt(path: url.path, start: -1.0, duration: 1.0, topN: 5)
        }
    }

    @Test("classifyAt validates duration > 0")
    func classifyAtZeroDuration() throws {
        let url = try generateTestAudio()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = AppleSoundProvider()

        #expect(throws: JsonRpcError.self) {
            try provider.classifyAt(path: url.path, start: 0.0, duration: 0.0, topN: 5)
        }
    }
}
