# SoundAnalysis (`sound.*`) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose Apple's SoundAnalysis framework via the `sound.*` JSON-RPC namespace, enabling classification of sounds from audio files using Apple's built-in classifier (300+ categories).

**Architecture:** Provider protocol (`SoundProvider`) with Apple implementation (`AppleSoundProvider`) backed by `SNAudioFileAnalyzer` + `SNClassifySoundRequest`. Handler (`SoundHandler`) routes 4 methods. TS SDK gets types, `MethodMap` entries, and a `Sound` namespace class. The `SNResultsObserving` callback protocol is bridged to synchronous returns using `DispatchSemaphore` + a `ResultsObserver` helper class.

**Tech Stack:** Swift (SoundAnalysis, AVFoundation), TypeScript (TS SDK namespace), Swift Testing framework.

---

## File Map

### Swift (create)
- `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SoundProvider.swift`
- `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SoundHandler.swift`
- `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundHandlerTests.swift`
- `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundIntegrationTests.swift`

### Swift (modify)
- `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` (register handler)

### TypeScript (create)
- `packages/darwinkit/src/namespaces/sound.ts`

### TypeScript (modify)
- `packages/darwinkit/src/types.ts` (add Sound types + MethodMap entries)
- `packages/darwinkit/src/client.ts` (add `sound` namespace)
- `packages/darwinkit/src/index.ts` (export Sound class + types)

---

## Task 1: SoundProvider Protocol + Data Types

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SoundProvider.swift`

### Step 1: Create the provider protocol with data types

Write the file with all types and the protocol. The `AppleSoundProvider` implementation will come in Task 3.

```swift
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
```

### Step 2: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SoundProvider.swift
git commit -m "feat(sound): add SoundProvider protocol and data types"
```

---

## Task 2: MockSoundProvider + SoundHandler Tests

**Files:**
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundHandlerTests.swift`

### Step 1: Write all handler tests with mock provider

This test file follows the exact pattern from `CoreMLHandlerTests.swift`. The `MockSoundProvider` is defined inside the test file. The `SoundHandler` does not exist yet, so these tests will not compile until Task 4.

```swift
import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockSoundProvider: SoundProvider {
    var classifyResult = SoundClassifyResult(
        classifications: [
            SoundClassification(identifier: "speech", confidence: 0.92),
            SoundClassification(identifier: "music", confidence: 0.05),
            SoundClassification(identifier: "silence", confidence: 0.03),
        ]
    )
    var classifyAtResult = SoundClassifyResult(
        classifications: [
            SoundClassification(identifier: "laughter", confidence: 0.85),
            SoundClassification(identifier: "speech", confidence: 0.10),
        ],
        timeRange: SoundTimeRange(start: 2.0, duration: 1.5)
    )
    var categoriesResult: [String] = ["speech", "music", "laughter", "applause", "siren"]
    var available: Bool = true
    var shouldThrow: JsonRpcError? = nil

    func classify(path: String, topN: Int) throws -> SoundClassifyResult {
        if let err = shouldThrow { throw err }
        if path.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }
        let limited = Array(classifyResult.classifications.prefix(topN))
        return SoundClassifyResult(classifications: limited)
    }

    func classifyAt(path: String, start: Double, duration: Double, topN: Int) throws -> SoundClassifyResult {
        if let err = shouldThrow { throw err }
        if path.contains("nonexistent") {
            throw JsonRpcError.invalidParams("File not found: \(path)")
        }
        let limited = Array(classifyAtResult.classifications.prefix(topN))
        return SoundClassifyResult(
            classifications: limited,
            timeRange: SoundTimeRange(start: start, duration: duration)
        )
    }

    func categories() throws -> [String] {
        if let err = shouldThrow { throw err }
        return categoriesResult
    }

    func isAvailable() -> Bool {
        available
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("Sound Handler")
struct SoundHandlerTests {

    // MARK: - sound.classify

    @Test("classify returns classifications array")
    func classifySuccess() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav"
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 3)
        #expect(classifications[0]["identifier"] as? String == "speech")
        #expect(classifications[0]["confidence"] as? Double == 0.92)
    }

    @Test("classify respects top_n parameter")
    func classifyTopN() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav", "top_n": 1
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 1)
    }

    @Test("classify defaults top_n to 5")
    func classifyDefaultTopN() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav"
        ])
        // Should succeed with default top_n=5 (mock has 3, so all 3 returned)
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]
        #expect(classifications.count == 3)
    }

    @Test("classify throws on missing path")
    func classifyMissingPath() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify throws on file not found")
    func classifyFileNotFound() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/nonexistent.wav"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - sound.classify_at

    @Test("classify_at returns classifications with time_range")
    func classifyAtSuccess() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "start": 2.0, "duration": 1.5
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]
        let timeRange = result["time_range"] as! [String: Any]

        #expect(classifications.count == 2)
        #expect(classifications[0]["identifier"] as? String == "laughter")
        #expect(timeRange["start"] as? Double == 2.0)
        #expect(timeRange["duration"] as? Double == 1.5)
    }

    @Test("classify_at respects top_n parameter")
    func classifyAtTopN() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "start": 0.0, "duration": 1.0, "top_n": 1
        ])
        let result = try handler.handle(request) as! [String: Any]
        let classifications = result["classifications"] as! [[String: Any]]

        #expect(classifications.count == 1)
    }

    @Test("classify_at throws on missing path")
    func classifyAtMissingPath() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "start": 0.0, "duration": 1.0
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify_at throws on missing start")
    func classifyAtMissingStart() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "duration": 1.0
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("classify_at throws on missing duration")
    func classifyAtMissingDuration() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.classify_at", params: [
            "path": "/tmp/test.wav", "start": 0.0
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - sound.categories

    @Test("categories returns list of category strings")
    func categoriesSuccess() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.categories")
        let result = try handler.handle(request) as! [String: Any]
        let categories = result["categories"] as! [String]

        #expect(categories.count == 5)
        #expect(categories.contains("speech"))
        #expect(categories.contains("music"))
    }

    // MARK: - sound.available

    @Test("available returns true when framework is available")
    func availableTrue() throws {
        let handler = SoundHandler(provider: MockSoundProvider())
        let request = makeRequest(method: "sound.available")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == true)
    }

    @Test("available returns false when framework is unavailable")
    func availableFalse() throws {
        var mock = MockSoundProvider()
        mock.available = false
        let handler = SoundHandler(provider: mock)
        let request = makeRequest(method: "sound.available")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["available"] as? Bool == false)
    }

    // MARK: - Method registration

    @Test("handler registers all 4 sound methods")
    func methodRegistration() {
        let handler = SoundHandler(provider: MockSoundProvider())
        let expected: Set<String> = [
            "sound.classify", "sound.classify_at",
            "sound.categories", "sound.available"
        ]

        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = SoundHandler(provider: MockSoundProvider())
        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockSoundProvider()
        mock.shouldThrow = .frameworkUnavailable("SoundAnalysis not available")
        let handler = SoundHandler(provider: mock)
        let request = makeRequest(method: "sound.classify", params: [
            "path": "/tmp/test.wav"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
```

### Step 2: Verify the tests do NOT compile yet (SoundHandler does not exist)

Run:
```bash
cd packages/darwinkit-swift && swift test 2>&1 | head -20
```
Expected: Compilation error mentioning `SoundHandler` is not defined.

### Step 3: Commit

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundHandlerTests.swift
git commit -m "test(sound): add SoundHandler unit tests with MockSoundProvider"
```

---

## Task 3: AppleSoundProvider Implementation

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SoundProvider.swift`

### Step 1: Add the Apple implementation to SoundProvider.swift

Append the `AppleSoundProvider` class and `ResultsObserver` helper to the existing file. Key design: `ResultsObserver` implements `SNResultsObserving` and uses a `DispatchSemaphore` to bridge the async callback to synchronous return.

Replace the existing import at the top:

**old_string (line 1):**
```
import Foundation
```

**new_string:**
```
import AVFoundation
import Foundation
import SoundAnalysis
```

Then append the full implementation at the end of the file (after the closing brace of the protocol):

```swift

// MARK: - Results Observer (bridges SNResultsObserving callback to sync)

private final class ResultsObserver: NSObject, SNResultsObserving {
    private let semaphore = DispatchSemaphore(value: 0)
    private(set) var classifications: [SoundClassification] = []
    private(set) var error: Error?
    private let topN: Int
    private let targetTimeRange: CMTimeRange?

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
            // Check overlap: result must intersect with target
            let resultStart = CMTimeGetSeconds(resultTime.start)
            let resultEnd = resultStart + CMTimeGetSeconds(resultTime.duration)
            let targetStart = CMTimeGetSeconds(target.start)
            let targetEnd = targetStart + CMTimeGetSeconds(target.duration)

            guard resultEnd > targetStart && resultStart < targetEnd else { return }
        }

        let items = classification.classifications.prefix(topN).map { item in
            SoundClassification(identifier: item.identifier, confidence: Double(item.confidence))
        }

        // Keep the latest (most confident) result — SoundAnalysis sends multiple windows
        if !items.isEmpty {
            self.classifications = Array(items)
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
```

### Step 2: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SoundProvider.swift
git commit -m "feat(sound): implement AppleSoundProvider with SNAudioFileAnalyzer"
```

---

## Task 4: SoundHandler

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SoundHandler.swift`

### Step 1: Write the handler

```swift
import Foundation

/// Handles all sound.* methods: classify, classify_at, categories, available.
public final class SoundHandler: MethodHandler {
    private let provider: SoundProvider

    public var methods: [String] {
        ["sound.classify", "sound.classify_at", "sound.categories", "sound.available"]
    }

    public init(provider: SoundProvider = AppleSoundProvider()) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "sound.classify":
            return try handleClassify(request)
        case "sound.classify_at":
            return try handleClassifyAt(request)
        case "sound.categories":
            return try handleCategories(request)
        case "sound.available":
            return handleAvailable(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        switch method {
        case "sound.classify", "sound.classify_at", "sound.categories":
            return MethodCapability(available: true, note: "Requires macOS 12+")
        default:
            return MethodCapability(available: true)
        }
    }

    // MARK: - Method Implementations

    private func handleClassify(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let topN = request.int("top_n") ?? 5

        let result = try provider.classify(path: path, topN: topN)
        return result.toDict()
    }

    private func handleClassifyAt(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")

        guard let start = request.double("start") else {
            throw JsonRpcError.invalidParams("Missing required param: start")
        }
        guard let duration = request.double("duration") else {
            throw JsonRpcError.invalidParams("Missing required param: duration")
        }

        let topN = request.int("top_n") ?? 5

        let result = try provider.classifyAt(path: path, start: start, duration: duration, topN: topN)
        return result.toDict()
    }

    private func handleCategories(_ request: JsonRpcRequest) throws -> Any {
        let categories = try provider.categories()
        return ["categories": categories] as [String: Any]
    }

    private func handleAvailable(_ request: JsonRpcRequest) -> Any {
        return ["available": provider.isAvailable()] as [String: Any]
    }
}
```

### Step 2: Run the tests to verify they pass

```bash
cd packages/darwinkit-swift && swift test --filter SoundHandlerTests 2>&1
```

Expected: All 14 tests pass (the ones from Task 2).

### Step 3: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SoundHandler.swift
git commit -m "feat(sound): implement SoundHandler routing 4 methods"
```

---

## Task 5: Register SoundHandler in DarwinKit.swift

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift`

### Step 1: Add SoundHandler registration to both builder functions

In `buildServerWithRouter()`, add after the `CoreMLHandler` line:

**old_string:**
```swift
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(CloudHandler(notificationSink: server))
```

**new_string:**
```swift
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(SoundHandler())
    router.register(CloudHandler(notificationSink: server))
```

In `buildRouter()`, add after the `CoreMLHandler` line:

**old_string:**
```swift
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(CloudHandler())
```

**new_string:**
```swift
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(SoundHandler())
    router.register(CloudHandler())
```

### Step 2: Build to verify it compiles

```bash
cd packages/darwinkit-swift && swift build 2>&1 | tail -5
```

Expected: Build succeeds.

### Step 3: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift
git commit -m "feat(sound): register SoundHandler in DarwinKit server"
```

---

## Task 6: Integration Tests

**Files:**
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundIntegrationTests.swift`

### Step 1: Write integration tests

These tests use `AppleSoundProvider` directly (no mock) and require macOS 12+. They test real SoundAnalysis framework behavior. They need a real audio file, so we generate one using AVFoundation in the test setup.

```swift
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
        let duration: Double = 2.0
        let frequency: Double = 440.0  // A4 note
        let totalSamples = Int(sampleRate * duration)

        var audioFile: AVAudioFile?
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples))!
        buffer.frameLength = AVAudioFrameCount(totalSamples)

        let data = buffer.floatChannelData![0]
        for i in 0..<totalSamples {
            data[i] = Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }

        try audioFile?.write(from: buffer)

        return url
    }

    @Test("classify returns non-empty classifications for audio file")
    func classifyAudioFile() throws {
        let url = try generateTestAudio()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = AppleSoundProvider()
        let result = try provider.classify(path: url.path, topN: 5)

        #expect(!result.classifications.isEmpty)
        #expect(result.classifications[0].confidence > 0)
        #expect(!result.classifications[0].identifier.isEmpty)
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
```

### Step 2: Run the integration tests

```bash
cd packages/darwinkit-swift && swift test --filter SoundIntegrationTests 2>&1
```

Expected: All 8 tests pass. Some may be slow (1-3 seconds for audio analysis).

### Step 3: Commit

```bash
git add packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundIntegrationTests.swift
git commit -m "test(sound): add integration tests with real SoundAnalysis framework"
```

---

## Task 7: TypeScript SDK Types + MethodMap

**Files:**
- Modify: `packages/darwinkit/src/types.ts`

### Step 1: Add Sound types before the MethodMap section

Insert this block between the `CoreMLOkResult` interface and the `// MethodMap` comment:

**old_string:**
```typescript
// ---------------------------------------------------------------------------
// MethodMap
// ---------------------------------------------------------------------------
```

**new_string:**
```typescript
// ---------------------------------------------------------------------------
// Sound Analysis
// ---------------------------------------------------------------------------

export interface SoundClassification {
  identifier: string
  confidence: number
}

export interface SoundClassifyParams {
  path: string
  top_n?: number // default: 5
}

export interface SoundTimeRange {
  start: number
  duration: number
}

export interface SoundClassifyResult {
  classifications: SoundClassification[]
  time_range?: SoundTimeRange
}

export interface SoundClassifyAtParams {
  path: string
  start: number
  duration: number
  top_n?: number // default: 5
}

export interface SoundCategoriesResult {
  categories: string[]
}

export interface SoundAvailableResult {
  available: boolean
}

// ---------------------------------------------------------------------------
// MethodMap
// ---------------------------------------------------------------------------
```

### Step 2: Add MethodMap entries for sound methods

Insert these 4 entries into the `MethodMap` interface, after the last `coreml.*` entry and before the closing `}`:

**old_string:**
```typescript
  "coreml.embed_contextual_batch": {
    params: CoreMLContextualEmbedBatchParams
    result: CoreMLEmbedBatchResult
  }
}
```

**new_string:**
```typescript
  "coreml.embed_contextual_batch": {
    params: CoreMLContextualEmbedBatchParams
    result: CoreMLEmbedBatchResult
  }
  "sound.classify": {
    params: SoundClassifyParams
    result: SoundClassifyResult
  }
  "sound.classify_at": {
    params: SoundClassifyAtParams
    result: SoundClassifyResult
  }
  "sound.categories": {
    params: Record<string, never>
    result: SoundCategoriesResult
  }
  "sound.available": {
    params: Record<string, never>
    result: SoundAvailableResult
  }
}
```

### Step 3: Commit

```bash
git add packages/darwinkit/src/types.ts
git commit -m "feat(sound): add Sound Analysis types and MethodMap entries to TS SDK"
```

---

## Task 8: TypeScript SDK Sound Namespace

**Files:**
- Create: `packages/darwinkit/src/namespaces/sound.ts`

### Step 1: Create the Sound namespace class

Follow the exact pattern from `packages/darwinkit/src/namespaces/coreml.ts` (with private client field for no-param methods like `categories()` and `available()`):

```typescript
import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  SoundClassifyParams,
  SoundClassifyResult,
  SoundClassifyAtParams,
  SoundCategoriesResult,
  SoundAvailableResult,
} from "../types.js"

// helper to create callable+preparable methods
function method<M extends MethodName>(client: DarwinKitClient, name: M) {
  const fn = (
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  })
  return fn
}

export class Sound {
  readonly classify: {
    (
      params: SoundClassifyParams,
      options?: { timeout?: number },
    ): Promise<SoundClassifyResult>
    prepare(
      params: SoundClassifyParams,
    ): PreparedCall<"sound.classify">
  }
  readonly classifyAt: {
    (
      params: SoundClassifyAtParams,
      options?: { timeout?: number },
    ): Promise<SoundClassifyResult>
    prepare(
      params: SoundClassifyAtParams,
    ): PreparedCall<"sound.classify_at">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.classify = method(client, "sound.classify") as Sound["classify"]
    this.classifyAt = method(
      client,
      "sound.classify_at",
    ) as Sound["classifyAt"]
  }

  /** List all available sound categories (no params needed) */
  categories(options?: { timeout?: number }): Promise<SoundCategoriesResult> {
    return this.client.call(
      "sound.categories",
      {} as Record<string, never>,
      options,
    )
  }

  /** Check if SoundAnalysis is available (no params needed) */
  available(options?: { timeout?: number }): Promise<SoundAvailableResult> {
    return this.client.call(
      "sound.available",
      {} as Record<string, never>,
      options,
    )
  }
}
```

### Step 2: Commit

```bash
git add packages/darwinkit/src/namespaces/sound.ts
git commit -m "feat(sound): add Sound namespace class to TS SDK"
```

---

## Task 9: Wire Sound Namespace into TS Client + Exports

**Files:**
- Modify: `packages/darwinkit/src/client.ts`
- Modify: `packages/darwinkit/src/index.ts`

### Step 1: Add Sound import and namespace to client.ts

Add the import (after the CoreML import):

**old_string:**
```typescript
import { CoreML } from "./namespaces/coreml.js"
```

**new_string:**
```typescript
import { CoreML } from "./namespaces/coreml.js"
import { Sound } from "./namespaces/sound.js"
```

Add the namespace property (after the `coreml` declaration):

**old_string:**
```typescript
  readonly coreml: CoreML

  private transport = new Transport()
```

**new_string:**
```typescript
  readonly coreml: CoreML
  readonly sound: Sound

  private transport = new Transport()
```

Add the constructor initialization (after the `this.coreml` line):

**old_string:**
```typescript
    this.coreml = new CoreML(this)
  }
```

**new_string:**
```typescript
    this.coreml = new CoreML(this)
    this.sound = new Sound(this)
  }
```

### Step 2: Add Sound export to index.ts

Add the namespace export (after CoreML line):

**old_string:**
```typescript
export { CoreML } from "./namespaces/coreml.js"
```

**new_string:**
```typescript
export { CoreML } from "./namespaces/coreml.js"
export { Sound } from "./namespaces/sound.js"
```

Add the type exports. Append the Sound types to the re-export block (after the `CoreMLOkResult` line and before the `// Notifications` comment):

**old_string:**
```typescript
  CoreMLOkResult,
  // Notifications
```

**new_string:**
```typescript
  CoreMLOkResult,
  // Sound Analysis
  SoundClassification,
  SoundClassifyParams,
  SoundTimeRange,
  SoundClassifyResult,
  SoundClassifyAtParams,
  SoundCategoriesResult,
  SoundAvailableResult,
  // Notifications
```

### Step 3: Type-check the TS SDK

```bash
tsgo --noEmit
```

Expected: No type errors.

### Step 4: Commit

```bash
git add packages/darwinkit/src/client.ts packages/darwinkit/src/index.ts
git commit -m "feat(sound): wire Sound namespace into TS SDK client and exports"
```

---

## Task 10: Run Full Test Suite + Final Verification

### Step 1: Run all Swift tests

```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift test 2>&1
```

Expected: All existing tests pass + new SoundHandlerTests (14 tests) + SoundIntegrationTests (8 tests).

### Step 2: Run Swift build

```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && swift build 2>&1
```

Expected: Build succeeds.

### Step 3: Quick smoke test via CLI

```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && \
  swift run darwinkit query '{"jsonrpc":"2.0","id":"1","method":"sound.available","params":{}}' 2>&1
```

Expected: `{"available": true}` in the result.

```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && \
  swift run darwinkit query '{"jsonrpc":"2.0","id":"2","method":"sound.categories","params":{}}' 2>&1
```

Expected: A JSON result with a `categories` array containing 300+ sound category strings.

### Step 4: Verify system.capabilities includes sound methods

```bash
cd /Users/Martin/Tresors/Projects/darwinkit-swift/packages/darwinkit-swift && \
  swift run darwinkit query '{"jsonrpc":"2.0","id":"3","method":"system.capabilities","params":{}}' 2>&1
```

Expected: The `methods` object in the result includes `sound.classify`, `sound.classify_at`, `sound.categories`, and `sound.available`.

---

## Summary of Files Created/Modified

| Action | File | Description |
|--------|------|-------------|
| Create | `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/SoundProvider.swift` | Protocol + data types + AppleSoundProvider implementation |
| Create | `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/SoundHandler.swift` | JSON-RPC handler routing 4 methods |
| Create | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundHandlerTests.swift` | Unit tests with MockSoundProvider (14 tests) |
| Create | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/SoundIntegrationTests.swift` | Integration tests with real framework (8 tests) |
| Modify | `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` | Register SoundHandler in both builder functions |
| Create | `packages/darwinkit/src/namespaces/sound.ts` | TS SDK Sound namespace class |
| Modify | `packages/darwinkit/src/types.ts` | Sound types + 4 MethodMap entries |
| Modify | `packages/darwinkit/src/client.ts` | Add `sound` namespace property |
| Modify | `packages/darwinkit/src/index.ts` | Export Sound class + types |

## JSON-RPC Method Reference

| Method | Params | Result |
|--------|--------|--------|
| `sound.classify` | `{path: string, top_n?: number}` | `{classifications: [{identifier, confidence}]}` |
| `sound.classify_at` | `{path: string, start: number, duration: number, top_n?: number}` | `{classifications: [...], time_range: {start, duration}}` |
| `sound.categories` | `{}` | `{categories: string[]}` |
| `sound.available` | `{}` | `{available: boolean}` |
