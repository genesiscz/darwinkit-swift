import AVFoundation
import Foundation
import SoundAnalysis

// MARK: - Data Types

/// A single sound classification result.
public struct SoundClassification {
    public let identifier: String
    public let confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }

    public func toDict() -> [String: Any] {
        [
            "identifier": identifier,
            "confidence": confidence,
        ]
    }
}

/// Result of classifying sounds in an audio file.
public struct SoundClassifyResult {
    public let classifications: [SoundClassification]
    public let timeRange: SoundTimeRange?

    public init(classifications: [SoundClassification], timeRange: SoundTimeRange? = nil) {
        self.classifications = classifications
        self.timeRange = timeRange
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "classifications": classifications.map { $0.toDict() },
        ]
        if let tr = timeRange {
            dict["time_range"] = tr.toDict()
        }
        return dict
    }
}

/// A time range within an audio file (seconds).
public struct SoundTimeRange {
    public let start: Double
    public let duration: Double

    public init(start: Double, duration: Double) {
        self.start = start
        self.duration = duration
    }

    public func toDict() -> [String: Any] {
        [
            "start": start,
            "duration": duration,
        ]
    }
}

// MARK: - Provider Protocol

public protocol SoundProvider {
    /// Classify sounds in an entire audio file. Returns top N classifications.
    func classify(path: String, topN: Int) throws -> SoundClassifyResult

    /// Classify sounds at a specific time range in an audio file.
    func classifyAt(path: String, start: Double, duration: Double, topN: Int) throws -> SoundClassifyResult

    /// List all available sound categories from the built-in classifier.
    func categories() throws -> [String]

    /// Check if SoundAnalysis is available on this system.
    func isAvailable() -> Bool
}

// MARK: - Results Observer (bridges SNResultsObserving callback to sync)

private final class ResultsObserver: NSObject, SNResultsObserving {
    private let semaphore = DispatchSemaphore(value: 0)
    private(set) var classifications: [SoundClassification] = []
    private(set) var error: Error?
    private let topN: Int
    private let targetTimeRange: CMTimeRange?
    private var highestConfidence: Double = 0.0

    init(topN: Int, targetTimeRange: CMTimeRange? = nil) {
        self.topN = topN
        self.targetTimeRange = targetTimeRange
        super.init()
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }

        // If we have a target time range, only collect results within it
        if let target = targetTimeRange {
            let resultTime = classification.timeRange
            let resultStart = CMTimeGetSeconds(resultTime.start)
            let resultEnd = resultStart + CMTimeGetSeconds(resultTime.duration)
            let targetStart = CMTimeGetSeconds(target.start)
            let targetEnd = targetStart + CMTimeGetSeconds(target.duration)

            guard resultEnd > targetStart && resultStart < targetEnd else { return }
        }

        let items = classification.classifications.prefix(topN).map { item in
            SoundClassification(identifier: item.identifier, confidence: Double(item.confidence))
        }

        // Keep the classification window with the highest confidence
        if let topResult = items.first, topResult.confidence > highestConfidence {
            self.classifications = Array(items)
            self.highestConfidence = topResult.confidence
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        self.error = error
        semaphore.signal()
    }

    func requestDidComplete(_ request: SNRequest) {
        semaphore.signal()
    }

    func waitForCompletion() {
        semaphore.wait()
    }
}

// MARK: - Apple Implementation

public final class AppleSoundProvider: SoundProvider {

    public init() {}

    public func classify(path: String, topN: Int) throws -> SoundClassifyResult {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let observer = ResultsObserver(topN: topN)

        try analyzer.add(request, withObserver: observer)
        analyzer.analyze()
        observer.waitForCompletion()

        if let error = observer.error {
            throw JsonRpcError.internalError("Sound classification failed: \(error.localizedDescription)")
        }

        return SoundClassifyResult(classifications: observer.classifications)
    }

    public func classifyAt(path: String, start: Double, duration: Double, topN: Int) throws -> SoundClassifyResult {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }

        guard start >= 0 else {
            throw JsonRpcError.invalidParams("start must be >= 0")
        }

        guard duration > 0 else {
            throw JsonRpcError.invalidParams("duration must be > 0")
        }

        let targetRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 44100),
            duration: CMTime(seconds: duration, preferredTimescale: 44100)
        )

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let observer = ResultsObserver(topN: topN, targetTimeRange: targetRange)

        try analyzer.add(request, withObserver: observer)
        analyzer.analyze()
        observer.waitForCompletion()

        if let error = observer.error {
            throw JsonRpcError.internalError("Sound classification failed: \(error.localizedDescription)")
        }

        return SoundClassifyResult(
            classifications: observer.classifications,
            timeRange: SoundTimeRange(start: start, duration: duration)
        )
    }

    public func categories() throws -> [String] {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        return request.knownClassifications.sorted()
    }

    public func isAvailable() -> Bool {
        // SoundAnalysis with version1 classifier requires macOS 12+
        if #available(macOS 12, *) {
            return true
        }
        return false
    }
}
