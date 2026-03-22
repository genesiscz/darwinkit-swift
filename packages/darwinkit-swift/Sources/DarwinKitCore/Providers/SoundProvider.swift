import Foundation

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
