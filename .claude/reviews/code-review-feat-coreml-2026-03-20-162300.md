# Code Review Report

**Date:** 2026-03-20 16:23:00
**Branch:** feat/coreml
**Reviewed Files:**
- `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift`
- `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CoreMLHandler.swift`
- `packages/darwinkit/src/namespaces/coreml.ts`
- `packages/darwinkit/src/types.ts` (CoreML section)

## Summary

The CoreML implementation adds a well-structured provider/handler pair for loading CoreML models, generating embeddings via swift-embeddings (BERT), and using Apple's NLContextualEmbedding API. The TypeScript SDK surface is clean and follows existing patterns. However, there are several significant issues: critical thread safety gaps in the provider's mutable state, a potential deadlock pattern with semaphores inside Tasks, a stale compiled model cache, and a bug in the `embedWithBundleImpl` method's MLTensor API usage.

---

## Critical Issues

### Issue 1: No thread safety on mutable dictionaries

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:96-99`
**Severity:** HIGH

**Problem:**
`AppleCoreMLProvider` is a `final class` with two mutable dictionaries (`models` and `contextualModels`) that are read and written without any synchronization. The `JsonRpcServer` dispatches requests from a background stdin thread (line 42-50 of `JsonRpcServer.swift`), meaning concurrent `load_model` + `embed` or `load_model` + `unload_model` calls will produce data races. Swift dictionaries are not thread-safe; concurrent mutation causes undefined behavior (crashes, corruption).

**Code:**
```swift
 94: public final class AppleCoreMLProvider: CoreMLProvider {
 95:     /// Loaded CoreML model bundles: id -> (MLModel, optional swift-embeddings bundle, dimensions)
 96:     private var models: [String: LoadedModel] = [:]
 97:
 98:     /// Loaded NLContextualEmbedding instances
 99:     private var contextualModels: [String: Any] = [:]
```

**Recommendation:**
Protect both dictionaries with a serial `DispatchQueue` or an `NSLock`. A queue-based approach is idiomatic:

**Suggested Fix:**
```swift
private let lock = NSLock()
private var models: [String: LoadedModel] = [:]
private var contextualModels: [String: Any] = [:]

// Then wrap all access:
func loadModel(id: String, options: CoreMLLoadOptions) throws -> CoreMLModelInfo {
    lock.lock()
    guard models[id] == nil else {
        lock.unlock()
        throw JsonRpcError.invalidParams("Model already loaded with id: \(id)")
    }
    lock.unlock()

    // ... heavy work (compile, load) outside lock ...

    lock.lock()
    defer { lock.unlock() }
    // double-check after lock re-acquire
    guard models[id] == nil else {
        throw JsonRpcError.invalidParams("Model already loaded with id: \(id)")
    }
    models[id] = LoadedModel(model: mlModel, info: info, modelBundle: modelBundle)
    return info
}
```

Alternatively, make `AppleCoreMLProvider` an `actor` if the project's minimum deployment target allows Swift concurrency.

---

### Issue 2: Semaphore + Task deadlock risk

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:381-395`
**Severity:** HIGH

**Problem:**
The `loadEmbeddingBundle` method creates a `Task` and immediately blocks the current thread with `semaphore.wait()`. If the caller is already on the cooperative thread pool (e.g., if dispatch ever moves to async context), this is a guaranteed deadlock. Even in the current synchronous stdin-thread model, this pattern is fragile -- `Task` inherits the current actor context, and if `Bert.loadModelBundle` needs the main actor or a specific executor, the semaphore blocks the only thread that could complete it.

The same pattern appears in `embedWithBundleImpl` (lines 413-422).

**Code:**
```swift
381:        let semaphore = DispatchSemaphore(value: 0)
382:        var bundle: Any? = nil
383:
384:        Task {
385:            do {
386:                let loaded = try await Bert.loadModelBundle(from: modelDir)
387:                bundle = loaded
388:            } catch {
389:                // Not a compatible model -- that's OK
390:            }
391:            semaphore.signal()
392:        }
393:
394:        semaphore.wait()
395:        return bundle
```

**Recommendation:**
Use `Task` with a completion handler pattern that doesn't block, or better yet, use a detached task to avoid inheriting actor context:

**Suggested Fix:**
```swift
private func loadEmbeddingBundle(path: String) -> Any? {
    guard #available(macOS 15, *) else { return nil }

    let modelDir = URL(fileURLWithPath: path).deletingLastPathComponent()
    let tokenizerPath = modelDir.appendingPathComponent("tokenizer.json")

    guard FileManager.default.fileExists(atPath: tokenizerPath.path) else {
        return nil
    }

    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var bundle: Any? = nil

    // Use detached to avoid inheriting actor context
    Task.detached {
        do {
            let loaded = try await Bert.loadModelBundle(from: modelDir)
            bundle = loaded
        } catch {
            // Not a compatible model
        }
        semaphore.signal()
    }

    semaphore.wait()
    return bundle
}
```

The same fix should apply to `embedWithBundleImpl` at line 416.

---

### Issue 3: embedWithBundleImpl uses incorrect MLTensor API

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:406-428`
**Severity:** HIGH

**Problem:**
The method calls `tensor.cast(to: Float.self).shapedArray(of: Float.self)`. Looking at the `Bert.ModelBundle.encode` return, it returns an `MLTensor`. The `MLTensor.shapedArray(of:)` method is `async` and returns `MLShapedArray<Scalar>`, but the code wraps it in a `Task` and reads `.scalars` -- this should work. However, the real issue is that `MLTensor` does not have a `cast(to:)` method that takes a Swift type like `Float.self`. The correct API is `MLTensor.cast(to: DType)` where `DType` is `MLTensor.DType.float32`. If this compiles, it's likely hitting a different overload or an extension. This needs verification against the actual build.

**Code:**
```swift
406:     private func embedWithBundleImpl(bundle: Any, text: String) throws -> [Float] {
407:         guard let bertBundle = bundle as? Bert.ModelBundle else {
408:             throw JsonRpcError.internalError("Invalid model bundle type")
409:         }
410:
411:         let tensor = try bertBundle.encode(text)
412:
413:         let semaphore = DispatchSemaphore(value: 0)
414:         var result: [Float]? = nil
415:
416:         Task {
417:             let shaped = await tensor.cast(to: Float.self).shapedArray(of: Float.self)
418:             result = shaped.scalars
419:             semaphore.signal()
420:         }
421:
422:         semaphore.wait()
423:
424:         guard let vector = result else {
425:             throw JsonRpcError.internalError("Embedding returned nil")
426:         }
427:         return vector
428:     }
```

**Recommendation:**
Use the correct MLTensor API and consider whether the cast is even necessary (BERT typically outputs Float32 already):

**Suggested Fix:**
```swift
@available(macOS 15, *)
private func embedWithBundleImpl(bundle: Any, text: String) throws -> [Float] {
    guard let bertBundle = bundle as? Bert.ModelBundle else {
        throw JsonRpcError.internalError("Invalid model bundle type")
    }

    let tensor = try bertBundle.encode(text)

    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: [Float]? = nil

    Task.detached {
        let shaped = await tensor.shapedArray(of: Float.self)
        result = Array(shaped.scalars)
        semaphore.signal()
    }

    semaphore.wait()

    guard let vector = result else {
        throw JsonRpcError.internalError("Embedding returned nil")
    }
    return vector
}
```

---

## Important Issues

### Issue 4: Stale compiled model cache -- no invalidation

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:309-319`
**Severity:** MED

**Problem:**
`compileAndCache` caches compiled models by filename only (`model.mlmodelc`). If a user updates the source `.mlpackage` on disk (same name, new weights), the stale cached `.mlmodelc` is returned. There is no hash check, no modification date comparison, and no way for the user to force recompilation.

**Code:**
```swift
309:     private func compileAndCache(sourceURL: URL) throws -> URL {
310:         let compiledName = sourceURL.deletingPathExtension().lastPathComponent + ".mlmodelc"
311:         let cachedURL = cacheDir.appendingPathComponent(compiledName)
312:
313:         if FileManager.default.fileExists(atPath: cachedURL.path) {
314:             return cachedURL
315:         }
316:
317:         let compiledURL = try MLModel.compileModel(at: sourceURL)
318:         try FileManager.default.moveItem(at: compiledURL, to: cachedURL)
319:         return cachedURL
320:     }
```

**Recommendation:**
Compare the source file's modification date against the cached compiled model's date. If the source is newer, recompile:

**Suggested Fix:**
```swift
private func compileAndCache(sourceURL: URL) throws -> URL {
    let compiledName = sourceURL.deletingPathExtension().lastPathComponent + ".mlmodelc"
    let cachedURL = cacheDir.appendingPathComponent(compiledName)

    let fm = FileManager.default
    if fm.fileExists(atPath: cachedURL.path) {
        let sourceAttrs = try fm.attributesOfItem(atPath: sourceURL.path)
        let cachedAttrs = try fm.attributesOfItem(atPath: cachedURL.path)
        let sourceDate = sourceAttrs[.modificationDate] as? Date ?? .distantPast
        let cachedDate = cachedAttrs[.modificationDate] as? Date ?? .distantPast
        if cachedDate >= sourceDate {
            return cachedURL
        }
        // Source is newer -- remove stale cache
        try? fm.removeItem(at: cachedURL)
    }

    let compiledURL = try MLModel.compileModel(at: sourceURL)
    try fm.moveItem(at: compiledURL, to: cachedURL)
    return cachedURL
}
```

---

### Issue 5: File size reports 0 for directories / .mlpackage bundles

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:146-147`
**Severity:** MED

**Problem:**
`.mlpackage` is a directory bundle, not a single file. `attributesOfItem(atPath:)` on a directory returns the directory's metadata size (typically 64-128 bytes), not the total size of its contents. The `sizeBytes` field in `CoreMLModelInfo` will be misleading (near-zero) for `.mlpackage` models.

**Code:**
```swift
145:
146:         let attrs = try FileManager.default.attributesOfItem(atPath: modelURL.path)
147:         let sizeBytes = (attrs[.size] as? Int64) ?? 0
148:
149:         if options.warmUp {
```

**Recommendation:**
Use a recursive directory size calculation for bundles:

**Suggested Fix:**
```swift
private func sizeOfItem(at url: URL) -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

    if !isDir.boolValue {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
        return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        total += Int64(values?.fileSize ?? 0)
    }
    return total
}
```

---

### Issue 6: `contextualModels` stores `Any` -- loses type safety

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:99`
**Severity:** MED

**Problem:**
`contextualModels` is typed as `[String: Any]` even though it only ever stores `NLContextualEmbedding` instances. This forces runtime casts at every access point (lines 181, 259, 358) and obscures the API contract. The `LoadedModel.modelBundle` property has the same issue (line 107) -- it is typed `Any?` but only holds `Bert.ModelBundle`.

**Code:**
```swift
 98:     /// Loaded NLContextualEmbedding instances
 99:     private var contextualModels: [String: Any] = [:]
```

**Recommendation:**
Use the concrete type:

**Suggested Fix:**
```swift
private var contextualModels: [String: NLContextualEmbedding] = [:]
```

This eliminates `as? NLContextualEmbedding` casts in `contextualEmbed`, `modelInfo`, and `contextualModelInfo`. The `contextualModelInfo` helper (line 356) can then drop its `Any` parameter and the fallback `768` default.

For `modelBundle`, while the `@available(macOS 15, *)` constraint makes direct typing harder, you could use a wrapper enum:
```swift
enum ModelBundleWrapper {
    @available(macOS 15, *)
    case bert(Bert.ModelBundle)
}
```

---

### Issue 7: `loadContextualEmbedding` does not check for duplicate ID

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:223-256`
**Severity:** MED

**Problem:**
`loadModel` (line 119) properly guards against duplicate IDs, but `loadContextualEmbedding` does not. Calling `load_contextual` twice with the same ID silently overwrites the previous model and leaks the old `NLContextualEmbedding` instance (which holds loaded assets in memory). This is inconsistent behavior within the same provider.

**Code:**
```swift
223:     public func loadContextualEmbedding(id: String, language: String) throws -> CoreMLModelInfo {
224:         let nlLang = NLLanguage(rawValue: language)
225:
226:         guard let embedding = NLContextualEmbedding(language: nlLang) else {
227:             throw JsonRpcError.frameworkUnavailable(
228:                 "No contextual embedding available for language: \(language)"
229:             )
230:         }
```

**Recommendation:**
Add a duplicate-ID guard matching `loadModel`:

**Suggested Fix:**
```swift
public func loadContextualEmbedding(id: String, language: String) throws -> CoreMLModelInfo {
    guard contextualModels[id] == nil, models[id] == nil else {
        throw JsonRpcError.invalidParams("Model already loaded with id: \(id)")
    }
    // ... rest of method
```

Note the cross-dictionary check -- an ID used in `models` should also be rejected here to prevent `unloadModel` ambiguity.

---

### Issue 8: `models()` in TS SDK lacks `.prepare()` support

**File:** `packages/darwinkit/src/namespaces/coreml.ts:137-143`
**Severity:** MED

**Problem:**
All other methods use the `method()` helper which provides both direct calling and `.prepare()` for batch API usage. The `models()` method is hand-written and only supports direct calls. Users cannot include `models()` in a batch call via `client.batch()`, breaking the consistency of the API surface.

**Code:**
```typescript
136:   /** List all loaded models (no params needed) */
137:   models(options?: { timeout?: number }): Promise<CoreMLModelsResult> {
138:     return this.client.call(
139:       "coreml.models",
140:       {} as Record<string, never>,
141:       options,
142:     )
143:   }
```

**Recommendation:**
Use the same `method()` helper pattern:

**Suggested Fix:**
```typescript
readonly models: {
  (options?: { timeout?: number }): Promise<CoreMLModelsResult>
  prepare(): PreparedCall<"coreml.models">
}

// In constructor:
this.models = method(client, "coreml.models") as CoreML["models"]
```

---

## Minor Issues

### Issue 9: `contextualModelInfo` loses original language in path

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:356-368`
**Severity:** LOW

**Problem:**
When `contextualModelInfo` is called from `listModels()`, it sets the path to `"system://contextual"` (generic) instead of `"system://\(language)"` which was used in `loadContextualEmbedding` (line 252). This means the round-trip `load_contextual` -> `models` -> inspect returns a different path than the one set during load.

**Code:**
```swift
356:     private func contextualModelInfo(id: String, model: Any) -> CoreMLModelInfo {
357:         let dim: Int
358:         if let emb = model as? NLContextualEmbedding {
359:             dim = emb.dimension
360:         } else {
361:             dim = 768
362:         }
363:         return CoreMLModelInfo(
364:             id: id, path: "system://contextual",
365:             dimensions: dim, computeUnits: "all",
366:             sizeBytes: 0, modelType: "contextual"
367:         )
368:     }
```

**Recommendation:**
Store the language in the contextual models dictionary (or change to `NLContextualEmbedding` type and extract language), or store the `CoreMLModelInfo` alongside the embedding to avoid re-deriving it.

---

### Issue 10: `warmUp` only handles MultiArray inputs

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:334-354`
**Severity:** LOW

**Problem:**
The warm-up function only creates dummy `MLMultiArray` inputs. Models with other input types (images, strings, dictionaries) will produce an empty `inputs` dict, skip the prediction, and silently skip warm-up. This is correct but could be documented.

**Code:**
```swift
334:     private func warmUp(model: MLModel) {
335:         do {
336:             let desc = model.modelDescription
337:             var inputs: [String: MLFeatureValue] = [:]
338:
339:             for (name, inputDesc) in desc.inputDescriptionsByName {
340:                 if let constraint = inputDesc.multiArrayConstraint {
341:                     let shape = constraint.shape
342:                     let array = try MLMultiArray(shape: shape, dataType: constraint.dataType)
343:                     inputs[name] = MLFeatureValue(multiArray: array)
344:                 }
345:             }
```

**Recommendation:**
Add a comment noting the limitation, or log a debug message when warm-up is skipped due to unsupported input types.

---

### Issue 11: `client` property should be `private` in CoreML class

**File:** `packages/darwinkit/src/namespaces/coreml.ts:104`
**Severity:** LOW

**Problem:**
The `client` field is declared `private` (correct) but the NLP class (the pattern being followed) does not declare `client` at all -- it only uses it in the constructor. The `CoreML` class stores it as a field because `models()` references it at call time via `this.client`, which is fine. However, if `models()` is refactored to use the `method()` helper (per Issue 8), the `client` field can be removed entirely.

**Code:**
```typescript
104:   private client: DarwinKitClient
```

**Recommendation:**
This is fine as-is. If Issue 8 is addressed, this field becomes unnecessary and should be removed for consistency with the NLP class.

---

### Issue 12: `NLContextualEmbedding.dimension` may return `Int` not matching `Int`

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:251-255`
**Severity:** LOW

**Problem:**
`NLContextualEmbedding.dimension` returns `Int`. The `CoreMLModelInfo.dimensions` field is also `Int`, so this is fine. However, in the TS types, `dimensions` is `number`, which is correct for JSON serialization. No actual bug here -- just noting the type chain is consistent.

---

### Issue 13: `embedBatch` is sequential, not batched

**File:** `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift:212-219`
**Severity:** LOW

**Problem:**
`embedBatch` simply loops and calls `embed` one at a time. The `Bert.ModelBundle` has a `batchEncode` method (seen in the swift-embeddings source at line 393) that processes multiple texts in a single forward pass, which would be significantly faster. The current implementation offers no batch performance benefit over the caller looping themselves.

**Code:**
```swift
212:     public func embedBatch(modelId: String, texts: [String]) throws -> [[Float]] {
213:         var results: [[Float]] = []
214:         for text in texts {
215:             let vector = try embed(modelId: modelId, text: text)
216:             results.append(vector)
217:         }
218:         return results
219:     }
```

**Recommendation:**
Use `Bert.ModelBundle.batchEncode` for true batch processing when the swift-embeddings bundle is available:

**Suggested Fix:**
```swift
public func embedBatch(modelId: String, texts: [String]) throws -> [[Float]] {
    guard let loaded = models[modelId] else {
        throw JsonRpcError.invalidParams("No model loaded with id: \(modelId)")
    }

    if #available(macOS 15, *), let bundle = loaded.modelBundle as? Bert.ModelBundle {
        let tensor = try bundle.batchEncode(texts)
        // Process batch tensor into individual vectors
        // ...
    }

    // Fallback: sequential
    return try texts.map { try embed(modelId: modelId, text: $0) }
}
```

---

## Positive Observations

- Clean separation of concerns: the `CoreMLProvider` protocol abstracts the implementation from the `CoreMLHandler`, making testing straightforward with mock providers.
- The handler's parameter validation is thorough -- empty text checks, compute unit enum validation with helpful error messages listing valid values.
- Good use of vDSP for mean pooling and L2 normalization in contextual embeddings -- this is the correct approach for performance on Apple Silicon.
- The TypeScript types are well-structured and the `MethodMap` integration is complete, enabling full type inference through the batch API.
- Asset download handling for `NLContextualEmbedding` (lines 232-246) correctly blocks until assets are available, with proper error handling for unavailable assets.
- The `toDict()` pattern on `CoreMLModelInfo` keeps serialization concerns local to the model.

---

## Statistics

- **Files reviewed:** 4
- **Critical issues (HIGH):** 3
- **Important issues (MED):** 5
- **Minor issues (LOW):** 5
