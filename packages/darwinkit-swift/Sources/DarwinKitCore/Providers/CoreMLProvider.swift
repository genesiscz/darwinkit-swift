import Accelerate
import CoreML
import Embeddings
import Foundation
import NaturalLanguage

// MARK: - Compute Units

public enum CoreMLComputeUnits: String, CaseIterable {
    case all
    case cpuAndGPU
    case cpuOnly
    case cpuAndNeuralEngine
}

// MARK: - Model Info

public struct CoreMLModelInfo {
    public let id: String
    public let path: String
    public let dimensions: Int
    public let computeUnits: String
    public let sizeBytes: Int64
    public let modelType: String  // "coreml" | "contextual"

    public init(
        id: String, path: String, dimensions: Int,
        computeUnits: String, sizeBytes: Int64, modelType: String
    ) {
        self.id = id
        self.path = path
        self.dimensions = dimensions
        self.computeUnits = computeUnits
        self.sizeBytes = sizeBytes
        self.modelType = modelType
    }

    public func toDict() -> [String: Any] {
        [
            "id": id,
            "path": path,
            "dimensions": dimensions,
            "compute_units": computeUnits,
            "size_bytes": sizeBytes,
            "model_type": modelType,
        ]
    }
}

// MARK: - Load Options

public struct CoreMLLoadOptions {
    public let path: String
    public let computeUnits: CoreMLComputeUnits
    public let warmUp: Bool

    public init(path: String, computeUnits: CoreMLComputeUnits = .all, warmUp: Bool = true) {
        self.path = path
        self.computeUnits = computeUnits
        self.warmUp = warmUp
    }
}

// MARK: - Provider Protocol

public protocol CoreMLProvider {
    /// Load a CoreML model from disk. Returns model info.
    func loadModel(id: String, options: CoreMLLoadOptions) throws -> CoreMLModelInfo

    /// Unload a previously loaded model, freeing memory.
    func unloadModel(id: String) throws

    /// Get info about a loaded model.
    func modelInfo(id: String) throws -> CoreMLModelInfo

    /// List all currently loaded models.
    func listModels() -> [CoreMLModelInfo]

    /// Embed a single text using a loaded model. Returns Float array (GPU-native precision).
    func embed(modelId: String, text: String) throws -> [Float]

    /// Embed multiple texts in batch. Returns array of Float arrays.
    func embedBatch(modelId: String, texts: [String]) throws -> [[Float]]

    /// Load NLContextualEmbedding (macOS 14+). Returns model info with 768 dimensions.
    func loadContextualEmbedding(id: String, language: String) throws -> CoreMLModelInfo

    /// Embed text using NLContextualEmbedding with vDSP-optimized mean pooling.
    func contextualEmbed(modelId: String, text: String) throws -> [Float]
}

// MARK: - Apple Implementation

public final class AppleCoreMLProvider: CoreMLProvider {
    /// Idle TTL for loaded models. Models not accessed for this long are evicted.
    /// A single NLContextualEmbedding can be 100s of MB; without eviction a long-
    /// lived consumer that loads many languages accumulates multi-GB heap.
    private static let modelIdleTTL: TimeInterval = 600 // 10 min

    /// How often to sweep for stale models. Each sweep is O(models), cheap.
    private static let evictionInterval: TimeInterval = 60

    /// Loaded CoreML model bundles: id -> (MLModel, optional swift-embeddings bundle, dimensions)
    private var models: [String: LoadedModel] = [:]

    /// Loaded NLContextualEmbedding instances
    private var contextualModels: [String: Any] = [:]

    /// Per-id last-access timestamps for idle TTL eviction. Kept separate per
    /// store so that loadModel/loadContextualEmbedding using the same id (which
    /// the existing API allows — see loadModel's guard only checks `models`)
    /// don't conflate two different resources during eviction.
    private var modelLastAccess: [String: Date] = [:]
    private var contextualLastAccess: [String: Date] = [:]

    /// Synchronizes access to `models`, `contextualModels`, and the two
    /// `*LastAccess` dictionaries. The eviction timer runs on a utility queue;
    /// public load/embed/unload methods run on the stdin thread. Without a
    /// lock these would race — Swift's Dictionary is documented as unsafe
    /// for concurrent mutation. NSLock is plenty: contention is low and the
    /// critical sections are short bookkeeping ops (heavy work like CoreML
    /// model loading happens OUTSIDE the lock).
    private let stateLock = NSLock()

    /// Compiled model cache directory
    private let cacheDir: URL

    /// Periodic eviction timer (lifetime-tied to this provider).
    private var evictionTimer: DispatchSourceTimer?

    struct LoadedModel {
        let model: MLModel
        let info: CoreMLModelInfo
        let modelBundle: Any?  // Bert.ModelBundle when available (macOS 15+)
    }

    public init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = base.appendingPathComponent("darwinkit/coreml", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Start the idle-eviction timer. It runs on a utility queue so we don't
        // contend with the main-thread / stdin-thread request dispatch.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + Self.evictionInterval,
            repeating: Self.evictionInterval
        )
        timer.setEventHandler { [weak self] in
            self?.evictStaleModels()
        }
        timer.resume()
        self.evictionTimer = timer
    }

    /// Run a closure with the state lock held. Use for every dict access.
    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    /// Mark a custom CoreML model id as freshly accessed.
    private func touchModel(_ id: String) {
        withStateLock { modelLastAccess[id] = Date() }
    }

    /// Mark a contextual-embedding id as freshly accessed.
    private func touchContextual(_ id: String) {
        withStateLock { contextualLastAccess[id] = Date() }
    }

    /// Drop entries whose `lastAccess` is older than `modelIdleTTL` from both
    /// stores. Held under `stateLock` so it can't race with concurrent
    /// loadModel / embed / unload calls.
    private func evictStaleModels() {
        let cutoff = Date().addingTimeInterval(-Self.modelIdleTTL)
        withStateLock {
            let staleModels = modelLastAccess.filter { $0.value < cutoff }.map { $0.key }
            for id in staleModels {
                models.removeValue(forKey: id)
                modelLastAccess.removeValue(forKey: id)
            }
            let staleContextual = contextualLastAccess.filter { $0.value < cutoff }.map { $0.key }
            for id in staleContextual {
                contextualModels.removeValue(forKey: id)
                contextualLastAccess.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Custom CoreML Models

    public func loadModel(id: String, options: CoreMLLoadOptions) throws -> CoreMLModelInfo {
        // Check duplicates under the lock — but a quick check first so we
        // don't do filesystem work on an obvious dup.
        try withStateLock {
            if models[id] != nil {
                throw JsonRpcError.invalidParams("Model already loaded with id: \(id)")
            }
        }

        let modelURL = URL(fileURLWithPath: options.path)

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw JsonRpcError.invalidParams("Model file not found: \(options.path)")
        }

        let config = MLModelConfiguration()
        config.computeUnits = mapComputeUnits(options.computeUnits)

        let mlModel: MLModel
        let ext = modelURL.pathExtension

        if ext == "mlmodelc" {
            mlModel = try MLModel(contentsOf: modelURL, configuration: config)
        } else if ext == "mlpackage" {
            let compiledURL = try compileAndCache(sourceURL: modelURL)
            mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
        } else {
            throw JsonRpcError.invalidParams("Unsupported model format: .\(ext). Use .mlpackage or .mlmodelc")
        }

        let dimensions = inferDimensions(from: mlModel)

        let attrs = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let sizeBytes = (attrs[.size] as? Int64) ?? 0

        if options.warmUp {
            warmUp(model: mlModel)
        }

        // Try to load as swift-embeddings model bundle for text embedding (macOS 15+)
        let modelBundle = loadEmbeddingBundle(path: options.path)

        let info = CoreMLModelInfo(
            id: id, path: options.path, dimensions: dimensions,
            computeUnits: options.computeUnits.rawValue,
            sizeBytes: sizeBytes, modelType: "coreml"
        )

        // Final check + insert under the lock — handles the (rare) TOCTOU
        // window between the early check above and now.
        try withStateLock {
            if models[id] != nil {
                throw JsonRpcError.invalidParams("Model already loaded with id: \(id)")
            }
            models[id] = LoadedModel(model: mlModel, info: info, modelBundle: modelBundle)
            modelLastAccess[id] = Date()
        }
        return info
    }

    public func unloadModel(id: String) throws {
        try withStateLock {
            if models.removeValue(forKey: id) != nil {
                modelLastAccess.removeValue(forKey: id)
                return
            }
            if contextualModels.removeValue(forKey: id) != nil {
                contextualLastAccess.removeValue(forKey: id)
                return
            }
            throw JsonRpcError.invalidParams("No model loaded with id: \(id)")
        }
    }

    public func modelInfo(id: String) throws -> CoreMLModelInfo {
        // Snapshot under the lock, then build the response outside.
        enum Snapshot {
            case model(CoreMLModelInfo)
            case contextual(Any)
            case missing
        }
        let snap: Snapshot = withStateLock {
            if let loaded = models[id] {
                modelLastAccess[id] = Date()
                return .model(loaded.info)
            }
            if let model = contextualModels[id] {
                contextualLastAccess[id] = Date()
                return .contextual(model)
            }
            return .missing
        }
        switch snap {
        case .model(let info):
            return info
        case .contextual(let model):
            return contextualModelInfo(id: id, model: model)
        case .missing:
            throw JsonRpcError.invalidParams("No model loaded with id: \(id)")
        }
    }

    public func listModels() -> [CoreMLModelInfo] {
        // Snapshot the dictionary entries under the lock; build the info list
        // outside so we don't hold the lock during contextualModelInfo() work.
        struct Snapshot {
            let coreml: [LoadedModel]
            let contextual: [(String, Any)]
        }
        let snap: Snapshot = withStateLock {
            Snapshot(coreml: Array(models.values), contextual: Array(contextualModels))
        }
        let coremlInfos = snap.coreml.map(\.info)
        let contextualInfos: [CoreMLModelInfo] = snap.contextual.map { (id, model) in
            contextualModelInfo(id: id, model: model)
        }
        return coremlInfos + contextualInfos
    }

    public func embed(modelId: String, text: String) throws -> [Float] {
        // Snapshot the LoadedModel reference under the lock, then do the
        // (potentially heavy) embedding work outside.
        let loaded: LoadedModel? = withStateLock {
            if let m = models[modelId] {
                modelLastAccess[modelId] = Date()
                return m
            }
            return nil
        }
        guard let loaded = loaded else {
            throw JsonRpcError.invalidParams("No model loaded with id: \(modelId)")
        }

        // If swift-embeddings bundle is available (macOS 15+), use it
        if let bundle = loaded.modelBundle {
            return try embedWithBundle(bundle: bundle, text: text)
        }

        // Fallback: no tokenizer available
        throw JsonRpcError.internalError(
            "Model \(modelId) has no tokenizer. Requires macOS 15+ for swift-embeddings, or use load_contextual for Apple's built-in model."
        )
    }

    public func embedBatch(modelId: String, texts: [String]) throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            let vector = try embed(modelId: modelId, text: text)
            results.append(vector)
        }
        return results
    }

    // MARK: - NLContextualEmbedding (macOS 14+)

    public func loadContextualEmbedding(id: String, language: String) throws -> CoreMLModelInfo {
        let nlLang = NLLanguage(rawValue: language)

        guard let embedding = NLContextualEmbedding(language: nlLang) else {
            throw JsonRpcError.frameworkUnavailable(
                "No contextual embedding available for language: \(language)"
            )
        }

        if !embedding.hasAvailableAssets {
            let semaphore = DispatchSemaphore(value: 0)
            var downloadResult: NLContextualEmbedding.AssetsResult = .notAvailable
            embedding.requestAssets { result, _ in
                downloadResult = result
                semaphore.signal()
            }
            semaphore.wait()

            guard downloadResult == .available else {
                throw JsonRpcError.frameworkUnavailable(
                    "Contextual embedding assets not available for language: \(language)"
                )
            }
        }

        try embedding.load()
        withStateLock {
            contextualModels[id] = embedding
            contextualLastAccess[id] = Date()
        }

        return CoreMLModelInfo(
            id: id, path: "system://\(language)",
            dimensions: embedding.dimension, computeUnits: "all",
            sizeBytes: 0, modelType: "contextual"
        )
    }

    public func contextualEmbed(modelId: String, text: String) throws -> [Float] {
        // Snapshot under the lock, then run the embedding outside.
        let embedding: NLContextualEmbedding? = withStateLock {
            guard let e = contextualModels[modelId] as? NLContextualEmbedding else { return nil }
            contextualLastAccess[modelId] = Date()
            return e
        }
        guard let embedding = embedding else {
            throw JsonRpcError.invalidParams("No contextual model loaded with id: \(modelId)")
        }

        let result = try embedding.embeddingResult(for: text, language: embedding.languages.first ?? .english)

        // Mean pooling over token vectors using vDSP for performance
        let dimension = embedding.dimension
        var sum = [Float](repeating: 0, count: dimension)
        var count: Float = 0

        result.enumerateTokenVectors(
            in: result.string.startIndex..<result.string.endIndex
        ) { vector, _ in
            let floatVector = vector.map { Float($0) }
            vDSP_vadd(sum, 1, floatVector, 1, &sum, 1, vDSP_Length(dimension))
            count += 1
            return true
        }

        guard count > 0 else {
            return [Float](repeating: 0, count: dimension)
        }

        // Divide by count (mean)
        vDSP_vsdiv(sum, 1, &count, &sum, 1, vDSP_Length(dimension))

        // L2 normalize
        var norm: Float = 0
        vDSP_svesq(sum, 1, &norm, vDSP_Length(dimension))
        norm = sqrt(norm)

        if norm > 0 {
            vDSP_vsdiv(sum, 1, &norm, &sum, 1, vDSP_Length(dimension))
        }

        return sum
    }

    // MARK: - Private Helpers

    private func mapComputeUnits(_ units: CoreMLComputeUnits) -> MLComputeUnits {
        switch units {
        case .all: return .all
        case .cpuAndGPU: return .cpuAndGPU
        case .cpuOnly: return .cpuOnly
        case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
        }
    }

    private func compileAndCache(sourceURL: URL) throws -> URL {
        let compiledName = sourceURL.deletingPathExtension().lastPathComponent + ".mlmodelc"
        let cachedURL = cacheDir.appendingPathComponent(compiledName)

        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        let compiledURL = try MLModel.compileModel(at: sourceURL)
        try FileManager.default.moveItem(at: compiledURL, to: cachedURL)
        return cachedURL
    }

    private func inferDimensions(from model: MLModel) -> Int {
        for (_, desc) in model.modelDescription.outputDescriptionsByName {
            if let constraint = desc.multiArrayConstraint {
                let shape = constraint.shape.map(\.intValue)
                if let last = shape.last, last > 1 {
                    return last
                }
            }
        }
        return 0
    }

    private func warmUp(model: MLModel) {
        do {
            let desc = model.modelDescription
            var inputs: [String: MLFeatureValue] = [:]

            for (name, inputDesc) in desc.inputDescriptionsByName {
                if let constraint = inputDesc.multiArrayConstraint {
                    let shape = constraint.shape
                    let array = try MLMultiArray(shape: shape, dataType: constraint.dataType)
                    inputs[name] = MLFeatureValue(multiArray: array)
                }
            }

            if !inputs.isEmpty {
                let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
                _ = try model.prediction(from: provider)
            }
        } catch {
            // Warm-up failure is non-fatal
        }
    }

    private func contextualModelInfo(id: String, model: Any) -> CoreMLModelInfo {
        let dim: Int
        if let emb = model as? NLContextualEmbedding {
            dim = emb.dimension
        } else {
            dim = 768
        }
        return CoreMLModelInfo(
            id: id, path: "system://contextual",
            dimensions: dim, computeUnits: "all",
            sizeBytes: 0, modelType: "contextual"
        )
    }

    /// Try to load as a swift-embeddings model bundle for automatic tokenization (macOS 15+)
    private func loadEmbeddingBundle(path: String) -> Any? {
        guard #available(macOS 15, *) else { return nil }

        let modelDir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let tokenizerPath = modelDir.appendingPathComponent("tokenizer.json")

        guard FileManager.default.fileExists(atPath: tokenizerPath.path) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var bundle: Any? = nil

        Task {
            do {
                let loaded = try await Bert.loadModelBundle(from: modelDir)
                bundle = loaded
            } catch {
                // Not a compatible model — that's OK
            }
            semaphore.signal()
        }

        semaphore.wait()
        return bundle
    }

    private func embedWithBundle(bundle: Any, text: String) throws -> [Float] {
        guard #available(macOS 15, *) else {
            throw JsonRpcError.osVersionTooOld("swift-embeddings requires macOS 15+")
        }
        return try embedWithBundleImpl(bundle: bundle, text: text)
    }

    @available(macOS 15, *)
    private func embedWithBundleImpl(bundle: Any, text: String) throws -> [Float] {
        guard let bertBundle = bundle as? Bert.ModelBundle else {
            throw JsonRpcError.internalError("Invalid model bundle type")
        }

        let tensor = try bertBundle.encode(text)

        let semaphore = DispatchSemaphore(value: 0)
        var result: [Float]? = nil

        Task {
            let shaped = await tensor.cast(to: Float.self).shapedArray(of: Float.self)
            result = shaped.scalars
            semaphore.signal()
        }

        semaphore.wait()

        guard let vector = result else {
            throw JsonRpcError.internalError("Embedding returned nil")
        }
        return vector
    }
}
