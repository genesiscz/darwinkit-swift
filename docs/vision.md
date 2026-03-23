# Vision Namespace

The `Vision` namespace exposes Apple's [Vision framework](https://developer.apple.com/documentation/vision) through a typed TypeScript API. Every method runs **on-device** -- no network calls, no API keys, no data leaving the machine.

## Table of Contents

- [Quick Start](#quick-start)
- [Methods](#methods)
  - [ocr](#visionocr) -- Extract text from images
  - [classify](#visionclassify) -- Classify image content
  - [featurePrint](#visionfeatureprint) -- Generate image feature vectors
  - [similarity](#visionsimilarity) -- Compare two images
  - [detectFaces](#visiondetectfaces) -- Detect faces with optional landmarks
  - [detectBarcodes](#visiondetectbarcodes) -- Read barcodes and QR codes
  - [saliency](#visionsaliency) -- Find attention/objectness regions
- [Batch API](#batch-api)
- [Error Handling](#error-handling)
- [Supported Image Formats](#supported-image-formats)
- [Practical Examples](#practical-examples)

---

## Quick Start

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// Classify a photo
const result = await dk.vision.classify({ path: "/path/to/photo.jpg" })
for (const item of result.classifications) {
  console.log(`${item.identifier}: ${(item.confidence * 100).toFixed(1)}%`)
}

dk.close()
```

---

## Methods

### `vision.ocr`

Extract text from an image using Apple's on-device text recognition engine.

```ts
const result = await dk.vision.ocr({
  path: "/path/to/document.png",
  languages: ["en-US"],
  level: "accurate",
})

console.log(result.text)

for (const block of result.blocks) {
  console.log(`"${block.text}" (${(block.confidence * 100).toFixed(1)}%)`)
  console.log(`  at (${block.bounds.x}, ${block.bounds.y}) ${block.bounds.width}x${block.bounds.height}`)
}
```

#### Parameters -- `OCRParams`

| Parameter   | Type               | Default       | Description                                       |
| ----------- | ------------------ | ------------- | ------------------------------------------------- |
| `path`      | `string`           | **required**  | Absolute path to the image file.                  |
| `languages` | `string[]`         | `["en-US"]`   | BCP 47 language codes for recognition priority.   |
| `level`     | `RecognitionLevel` | `"accurate"`  | `"accurate"` for best quality, `"fast"` for speed.|

#### Return Type -- `OCRResult`

| Field    | Type         | Description                             |
| -------- | ------------ | --------------------------------------- |
| `text`   | `string`     | Full concatenated text from the image.  |
| `blocks` | `OCRBlock[]` | Individual text regions with positions. |

**`OCRBlock`:**

| Field        | Type        | Description                                    |
| ------------ | ----------- | ---------------------------------------------- |
| `text`       | `string`    | Text content of this block.                    |
| `confidence` | `number`    | Recognition confidence, 0.0 to 1.0.           |
| `bounds`     | `OCRBounds` | Bounding rectangle `{ x, y, width, height }`. |

---

### `vision.classify`

Classify the content of an image using Apple's built-in image classification model. Returns labels ranked by confidence (e.g. "dog", "outdoor", "grass").

```ts
const result = await dk.vision.classify({
  path: "/path/to/photo.jpg",
  max_results: 5,
})

for (const item of result.classifications) {
  console.log(`${item.identifier}: ${(item.confidence * 100).toFixed(1)}%`)
}
// Example output:
//   golden_retriever: 92.3%
//   dog: 88.1%
//   outdoor: 76.5%
//   grass: 61.2%
//   animal: 58.9%
```

#### Parameters -- `ClassifyParams`

| Parameter     | Type     | Default      | Description                                   |
| ------------- | -------- | ------------ | --------------------------------------------- |
| `path`        | `string` | **required** | Absolute path to the image file.              |
| `max_results` | `number` | `10`         | Maximum number of classifications to return.  |

#### Return Type -- `ClassifyResult`

| Field             | Type                   | Description                       |
| ----------------- | ---------------------- | --------------------------------- |
| `classifications` | `ClassificationItem[]` | Labels sorted by confidence desc. |

**`ClassificationItem`:**

| Field        | Type     | Description                                      |
| ------------ | -------- | ------------------------------------------------ |
| `identifier` | `string` | Classification label (Apple's taxonomy).         |
| `confidence` | `number` | Confidence score, 0.0 to 1.0.                   |

---

### `vision.featurePrint`

Generate a numerical feature vector (embedding) for an image. Feature prints capture the visual "essence" of an image and can be compared to measure visual similarity. This is the building block for visual search, deduplication, and clustering.

```ts
const result = await dk.vision.featurePrint({
  path: "/path/to/photo.jpg",
})

console.log(`Dimensions: ${result.dimensions}`)
console.log(`Vector: [${result.vector.slice(0, 5).join(", ")}, ...]`)
```

#### Parameters -- `FeaturePrintParams`

| Parameter | Type     | Default      | Description                      |
| --------- | -------- | ------------ | -------------------------------- |
| `path`    | `string` | **required** | Absolute path to the image file. |

#### Return Type -- `FeaturePrintResult`

| Field        | Type       | Description                          |
| ------------ | ---------- | ------------------------------------ |
| `vector`     | `number[]` | Feature embedding vector.            |
| `dimensions` | `number`   | Number of dimensions in the vector.  |

---

### `vision.similarity`

Compare two images and return a distance score. Lower values mean the images are more similar. Uses Apple's VNFeaturePrintObservation distance computation internally.

```ts
const result = await dk.vision.similarity({
  path1: "/path/to/photo_a.jpg",
  path2: "/path/to/photo_b.jpg",
})

console.log(`Distance: ${result.distance}`)

if (result.distance < 5.0) {
  console.log("Very similar images")
} else if (result.distance < 15.0) {
  console.log("Somewhat similar")
} else {
  console.log("Different images")
}
```

#### Parameters -- `SimilarityParams`

| Parameter | Type     | Default      | Description                             |
| --------- | -------- | ------------ | --------------------------------------- |
| `path1`   | `string` | **required** | Absolute path to the first image file.  |
| `path2`   | `string` | **required** | Absolute path to the second image file. |

#### Return Type -- `SimilarityResult`

| Field      | Type     | Description                                                         |
| ---------- | -------- | ------------------------------------------------------------------- |
| `distance` | `number` | Feature-print distance. 0 = identical. Lower = more similar.       |

---

### `vision.detectFaces`

Detect faces in an image. Optionally returns facial landmarks (eyes, nose, mouth, face contour).

```ts
const result = await dk.vision.detectFaces({
  path: "/path/to/group_photo.jpg",
  landmarks: true,
})

console.log(`Found ${result.faces.length} face(s)`)

for (const face of result.faces) {
  console.log(`  Confidence: ${(face.confidence * 100).toFixed(1)}%`)
  console.log(`  Bounds: (${face.bounds.x}, ${face.bounds.y}) ${face.bounds.width}x${face.bounds.height}`)

  if (face.landmarks) {
    if (face.landmarks.left_eye) {
      console.log(`  Left eye: ${face.landmarks.left_eye.points.length} points`)
    }
    if (face.landmarks.mouth) {
      console.log(`  Mouth: ${face.landmarks.mouth.points.length} points`)
    }
  }
}
```

#### Parameters -- `DetectFacesParams`

| Parameter   | Type      | Default      | Description                               |
| ----------- | --------- | ------------ | ----------------------------------------- |
| `path`      | `string`  | **required** | Absolute path to the image file.          |
| `landmarks` | `boolean` | `false`      | When `true`, include facial landmark data.|

#### Return Type -- `DetectFacesResult`

| Field   | Type                | Description              |
| ------- | ------------------- | ------------------------ |
| `faces` | `FaceObservation[]` | Detected face objects.   |

**`FaceObservation`:**

| Field        | Type              | Description                                                  |
| ------------ | ----------------- | ------------------------------------------------------------ |
| `bounds`     | `FaceBounds`      | Bounding rectangle `{ x, y, width, height }`.               |
| `confidence` | `number`          | Detection confidence, 0.0 to 1.0.                           |
| `landmarks`  | `FaceLandmarks?`  | Present only when `landmarks: true` was set in the request.  |

**`FaceLandmarks`:**

| Field          | Type                   | Description                                     |
| -------------- | ---------------------- | ----------------------------------------------- |
| `left_eye`     | `FaceLandmarkPoints?`  | Points tracing the left eye contour.            |
| `right_eye`    | `FaceLandmarkPoints?`  | Points tracing the right eye contour.           |
| `nose`         | `FaceLandmarkPoints?`  | Points along the nose ridge and tip.            |
| `mouth`        | `FaceLandmarkPoints?`  | Points around the mouth/lips.                   |
| `face_contour` | `FaceLandmarkPoints?`  | Points along the jaw and face outline.          |

Each `FaceLandmarkPoints` contains a `points` field: an array of `[x, y]` coordinate pairs in normalized image coordinates (0.0 to 1.0).

---

### `vision.detectBarcodes`

Detect and decode barcodes, QR codes, and other symbologies in an image.

```ts
const result = await dk.vision.detectBarcodes({
  path: "/path/to/label.png",
})

for (const barcode of result.barcodes) {
  console.log(`Type: ${barcode.symbology}`)
  console.log(`Data: ${barcode.payload}`)
  console.log(`Bounds: (${barcode.bounds.x}, ${barcode.bounds.y})`)
}
```

#### Parameters -- `DetectBarcodesParams`

| Parameter     | Type       | Default      | Description                                                      |
| ------------- | ---------- | ------------ | ---------------------------------------------------------------- |
| `path`        | `string`   | **required** | Absolute path to the image file.                                 |
| `symbologies` | `string[]` | all types    | Restrict detection to specific symbology types (see list below). |

**Common symbology values:**

| Value        | Description        |
| ------------ | ------------------ |
| `"QR"`       | QR Code            |
| `"Aztec"`    | Aztec code         |
| `"Code128"`  | Code 128 barcode   |
| `"Code39"`   | Code 39 barcode    |
| `"EAN8"`     | EAN-8 barcode      |
| `"EAN13"`    | EAN-13 barcode     |
| `"UPCE"`     | UPC-E barcode      |
| `"PDF417"`   | PDF417 barcode     |
| `"DataMatrix"` | Data Matrix code |
| `"ITF14"`    | ITF-14 barcode     |

#### Return Type -- `DetectBarcodesResult`

| Field      | Type                   | Description             |
| ---------- | ---------------------- | ----------------------- |
| `barcodes` | `BarcodeObservation[]` | Detected barcode items. |

**`BarcodeObservation`:**

| Field       | Type             | Description                                          |
| ----------- | ---------------- | ---------------------------------------------------- |
| `payload`   | `string \| null` | Decoded content. `null` if the barcode is unreadable. |
| `symbology` | `string`         | Barcode type (e.g. `"QR"`, `"EAN13"`).               |
| `bounds`    | `FaceBounds`     | Bounding rectangle `{ x, y, width, height }`.       |

---

### `vision.saliency`

Generate a saliency map that highlights the most visually important regions of an image. Two modes are available:

- **`"attention"`** -- Where a human viewer's eye would naturally be drawn (good for smart cropping and thumbnails).
- **`"objectness"`** -- Regions that likely contain distinct objects (good for object proposals).

```ts
// Attention-based saliency (default)
const attention = await dk.vision.saliency({
  path: "/path/to/photo.jpg",
  type: "attention",
})

console.log(`Found ${attention.regions.length} salient region(s)`)
for (const region of attention.regions) {
  console.log(`  Confidence: ${(region.confidence * 100).toFixed(1)}%`)
  console.log(`  Bounds: (${region.bounds.x}, ${region.bounds.y}) ${region.bounds.width}x${region.bounds.height}`)
}

// Object-based saliency
const objectness = await dk.vision.saliency({
  path: "/path/to/photo.jpg",
  type: "objectness",
})

for (const region of objectness.regions) {
  console.log(`Object region at (${region.bounds.x}, ${region.bounds.y})`)
}
```

#### Parameters -- `SaliencyParams`

| Parameter | Type           | Default       | Description                                             |
| --------- | -------------- | ------------- | ------------------------------------------------------- |
| `path`    | `string`       | **required**  | Absolute path to the image file.                        |
| `type`    | `SaliencyType` | `"attention"` | `"attention"` for eye-tracking, `"objectness"` for objects. |

#### Return Type -- `SaliencyResultData`

| Field     | Type               | Description                                       |
| --------- | ------------------ | ------------------------------------------------- |
| `type`    | `SaliencyType`     | The saliency mode that was used.                  |
| `regions` | `SaliencyRegion[]` | Salient regions sorted by confidence descending.  |

**`SaliencyRegion`:**

| Field        | Type         | Description                                    |
| ------------ | ------------ | ---------------------------------------------- |
| `bounds`     | `FaceBounds` | Bounding rectangle `{ x, y, width, height }`. |
| `confidence` | `number`     | Saliency confidence, 0.0 to 1.0.              |

---

## Batch API

All Vision methods support `.prepare()` to create deferred calls that can be executed together with `dk.batch()`. This is useful when you need to run multiple independent analyses on one or more images.

```ts
const result = await dk.batch(
  dk.vision.classify.prepare({ path: "/path/to/photo.jpg" }),
  dk.vision.detectFaces.prepare({ path: "/path/to/photo.jpg", landmarks: true }),
  dk.vision.saliency.prepare({ path: "/path/to/photo.jpg" }),
)

// result is a typed tuple:
const [classifyResult, facesResult, saliencyResult] = result
// classifyResult: ClassifyResult
// facesResult:    DetectFacesResult
// saliencyResult: SaliencyResultData
```

You can mix Vision calls with other namespace calls in the same batch:

```ts
const [text, labels] = await dk.batch(
  dk.vision.ocr.prepare({ path: "/path/to/receipt.png" }),
  dk.vision.classify.prepare({ path: "/path/to/receipt.png" }),
)
```

---

## Error Handling

All Vision methods throw `DarwinKitError` on failure. Use the built-in error code helpers for common conditions.

```ts
import { DarwinKit, DarwinKitError, ErrorCodes } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

try {
  const result = await dk.vision.classify({ path: "/nonexistent/photo.jpg" })
} catch (err) {
  if (err instanceof DarwinKitError) {
    console.error(`Error ${err.code}: ${err.message}`)

    if (err.isFrameworkUnavailable) {
      // Vision framework not available on this system
      console.error("Vision framework is not available")
    }
    if (err.isOSVersionTooOld) {
      // Feature requires a newer macOS version
      console.error("Please update macOS to use this feature")
    }
    if (err.isPermissionDenied) {
      // Missing permissions (e.g. file access)
      console.error("Permission denied -- check file access")
    }
    if (err.isCancelled) {
      // Operation was cancelled (e.g. timeout)
      console.error("Operation cancelled")
    }
  }
}
```

### Error Codes

| Code     | Constant                | Meaning                                       |
| -------- | ----------------------- | --------------------------------------------- |
| `-32700` | `PARSE_ERROR`           | Invalid JSON received by the server.          |
| `-32600` | `INVALID_REQUEST`       | Malformed JSON-RPC request.                   |
| `-32601` | `METHOD_NOT_FOUND`      | Unknown method name.                          |
| `-32602` | `INVALID_PARAMS`        | Invalid parameters (e.g. missing `path`).     |
| `-32603` | `INTERNAL_ERROR`        | Internal server error or request timeout.     |
| `-32001` | `FRAMEWORK_UNAVAILABLE` | Vision framework not available.               |
| `-32002` | `PERMISSION_DENIED`     | File access or system permission denied.      |
| `-32003` | `OS_VERSION_TOO_OLD`    | Feature requires a newer macOS version.       |
| `-32004` | `OPERATION_CANCELLED`   | Request cancelled (typically via timeout).     |

### Custom Timeouts

All methods accept an optional `timeout` (in milliseconds) as a second argument. This overrides the client-level default of 30 seconds.

```ts
// Allow up to 60 seconds for a large image
const result = await dk.vision.ocr(
  { path: "/path/to/huge_scan.tiff", level: "accurate" },
  { timeout: 60_000 },
)
```

---

## Supported Image Formats

The Vision framework accepts any image type supported by macOS, including:

| Format | Extensions                   |
| ------ | ---------------------------- |
| JPEG   | `.jpg`, `.jpeg`              |
| PNG    | `.png`                       |
| TIFF   | `.tif`, `.tiff`              |
| HEIF   | `.heic`, `.heif`             |
| BMP    | `.bmp`                       |
| GIF    | `.gif`                       |
| WebP   | `.webp`                      |
| PDF    | `.pdf` (first page)          |
| RAW    | `.cr2`, `.nef`, `.arw`, etc. |

All paths must be **absolute**. Use `path.resolve()` or template literals with `process.cwd()` if needed.

---

## Practical Examples

### Photo Tagging System

Automatically tag photos with descriptive labels for organization.

```ts
import { DarwinKit } from "@genesiscz/darwinkit"
import { readdir } from "node:fs/promises"
import { join, extname } from "node:path"

const dk = new DarwinKit()
const IMAGE_EXTS = new Set([".jpg", ".jpeg", ".png", ".heic", ".webp"])

async function tagPhotos(directory: string) {
  const files = await readdir(directory)
  const images = files.filter((f) => IMAGE_EXTS.has(extname(f).toLowerCase()))

  const tags = new Map<string, string[]>()

  for (const file of images) {
    const filePath = join(directory, file)
    const result = await dk.vision.classify({ path: filePath, max_results: 5 })

    const labels = result.classifications
      .filter((c) => c.confidence > 0.3)
      .map((c) => c.identifier)

    tags.set(file, labels)
    console.log(`${file}: ${labels.join(", ")}`)
  }

  return tags
}

await tagPhotos("/Users/me/Photos")
dk.close()
```

### Visual Search (Find Similar Images)

Find visually similar images by comparing feature prints.

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function findSimilar(
  queryImage: string,
  candidateImages: string[],
  threshold = 10.0,
) {
  const matches: Array<{ path: string; distance: number }> = []

  for (const candidate of candidateImages) {
    const result = await dk.vision.similarity({
      path1: queryImage,
      path2: candidate,
    })

    if (result.distance < threshold) {
      matches.push({ path: candidate, distance: result.distance })
    }
  }

  // Sort by similarity (lowest distance first)
  return matches.sort((a, b) => a.distance - b.distance)
}

const similar = await findSimilar("/path/to/query.jpg", [
  "/path/to/photo1.jpg",
  "/path/to/photo2.jpg",
  "/path/to/photo3.jpg",
])

for (const match of similar) {
  console.log(`${match.path} (distance: ${match.distance.toFixed(2)})`)
}

dk.close()
```

### Document Scanner (OCR + Barcode)

Extract both text and machine-readable codes from scanned documents using the batch API.

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function scanDocument(imagePath: string) {
  const [textResult, barcodeResult] = await dk.batch(
    dk.vision.ocr.prepare({
      path: imagePath,
      languages: ["en-US"],
      level: "accurate",
    }),
    dk.vision.detectBarcodes.prepare({
      path: imagePath,
    }),
  )

  return {
    text: textResult.text,
    textBlocks: textResult.blocks.map((b) => ({
      text: b.text,
      confidence: b.confidence,
    })),
    barcodes: barcodeResult.barcodes.map((b) => ({
      type: b.symbology,
      data: b.payload,
    })),
  }
}

const doc = await scanDocument("/path/to/shipping_label.png")
console.log("Extracted text:", doc.text)
console.log("Barcodes found:", doc.barcodes)

dk.close()
```

### Content Moderation Check

Use classification to flag potentially sensitive content and detect faces for privacy considerations.

```ts
import { DarwinKit, type ClassificationItem } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

interface ModerationResult {
  hasFaces: boolean
  faceCount: number
  labels: ClassificationItem[]
  flagged: string[]
}

const SENSITIVE_LABELS = new Set([
  "weapon",
  "gun",
  "knife",
  "blood",
  "violence",
])

async function moderateImage(imagePath: string): Promise<ModerationResult> {
  const [classifyResult, facesResult] = await dk.batch(
    dk.vision.classify.prepare({ path: imagePath, max_results: 20 }),
    dk.vision.detectFaces.prepare({ path: imagePath }),
  )

  const flagged = classifyResult.classifications
    .filter((c) => SENSITIVE_LABELS.has(c.identifier) && c.confidence > 0.5)
    .map((c) => c.identifier)

  return {
    hasFaces: facesResult.faces.length > 0,
    faceCount: facesResult.faces.length,
    labels: classifyResult.classifications,
    flagged,
  }
}

const check = await moderateImage("/path/to/uploaded_image.jpg")

if (check.flagged.length > 0) {
  console.log("Content flagged:", check.flagged.join(", "))
}
if (check.hasFaces) {
  console.log(`Contains ${check.faceCount} face(s) -- consider privacy review`)
}

dk.close()
```

### Face Counting in Group Photos

Count attendees in event photos by detecting and counting faces.

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function countFaces(imagePath: string) {
  const result = await dk.vision.detectFaces({
    path: imagePath,
    landmarks: false, // skip landmarks for faster detection
  })

  const highConfidence = result.faces.filter((f) => f.confidence > 0.7)

  console.log(`Total detections: ${result.faces.length}`)
  console.log(`High-confidence faces: ${highConfidence.length}`)

  // Report face positions (normalized coordinates)
  for (const [i, face] of highConfidence.entries()) {
    const { x, y, width, height } = face.bounds
    console.log(
      `  Face ${i + 1}: center=(${(x + width / 2).toFixed(2)}, ${(y + height / 2).toFixed(2)}) ` +
        `size=${(width * 100).toFixed(0)}%x${(height * 100).toFixed(0)}% ` +
        `confidence=${(face.confidence * 100).toFixed(1)}%`,
    )
  }

  return highConfidence.length
}

await countFaces("/path/to/group_photo.jpg")
dk.close()
```

### Smart Thumbnail Cropping

Use saliency to determine where to crop an image for thumbnails.

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

interface CropRegion {
  x: number
  y: number
  width: number
  height: number
}

async function suggestCrop(
  imagePath: string,
  targetAspectRatio = 1.0, // 1:1 square by default
): Promise<CropRegion> {
  const result = await dk.vision.saliency({
    path: imagePath,
    type: "attention",
  })

  if (result.regions.length === 0) {
    // No salient region found -- center crop
    return {
      x: 0.25,
      y: 0.25,
      width: 0.5,
      height: 0.5,
    }
  }

  // Use the most salient region as the crop center
  const primary = result.regions[0]
  const centerX = primary.bounds.x + primary.bounds.width / 2
  const centerY = primary.bounds.y + primary.bounds.height / 2

  // Expand to target aspect ratio while keeping the salient area centered
  const cropSize = Math.max(primary.bounds.width, primary.bounds.height)
  const cropWidth = Math.min(1, targetAspectRatio >= 1 ? cropSize : cropSize * targetAspectRatio)
  const cropHeight = Math.min(1, targetAspectRatio >= 1 ? cropSize / targetAspectRatio : cropSize)

  // Clamp origin so the crop box stays within [0, 1] bounds
  const x = Math.max(0, Math.min(1 - cropWidth, centerX - cropWidth / 2))
  const y = Math.max(0, Math.min(1 - cropHeight, centerY - cropHeight / 2))

  return { x, y, width: cropWidth, height: cropHeight }
}

const crop = await suggestCrop("/path/to/landscape.jpg")
console.log(`Suggested crop: x=${crop.x.toFixed(2)} y=${crop.y.toFixed(2)} ` +
  `w=${crop.width.toFixed(2)} h=${crop.height.toFixed(2)}`)

dk.close()
```

---

## Type Exports

All types are exported from the main package for use in your own type annotations:

```ts
import type {
  // OCR
  RecognitionLevel,
  OCRParams,
  OCRBounds,
  OCRBlock,
  OCRResult,
  // Classification
  ClassifyParams,
  ClassificationItem,
  ClassifyResult,
  // Feature Print
  FeaturePrintParams,
  FeaturePrintResult,
  // Similarity
  SimilarityParams,
  SimilarityResult,
  // Face Detection
  FaceBounds,
  FaceLandmarkPoints,
  FaceLandmarks,
  FaceObservation,
  DetectFacesParams,
  DetectFacesResult,
  // Barcode Detection
  BarcodeObservation,
  DetectBarcodesParams,
  DetectBarcodesResult,
  // Saliency
  SaliencyType,
  SaliencyRegion,
  SaliencyParams,
  SaliencyResultData,
} from "@genesiscz/darwinkit"
```
