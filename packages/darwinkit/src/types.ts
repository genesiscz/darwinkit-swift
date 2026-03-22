// ---------------------------------------------------------------------------
// NLP
// ---------------------------------------------------------------------------

export type EmbedType = "word" | "sentence"
export type NLPLanguage = "en" | "es" | "fr" | "de" | "it" | "pt" | "zh-Hans"

export interface EmbedParams {
  text: string
  language: string
  type?: EmbedType // default: "sentence"
}
export interface EmbedResult {
  vector: number[]
  dimension: number
}

export interface DistanceParams {
  text1: string
  text2: string
  language: string
  type?: EmbedType // default: "word"
}
export interface DistanceResult {
  distance: number
  type: "cosine"
}

export interface NeighborsParams {
  text: string
  language: string
  type?: EmbedType // default: "word"
  count?: number // default: 5
}
export interface Neighbor {
  text: string
  distance: number
}
export interface NeighborsResult {
  neighbors: Neighbor[]
}

export type TagScheme =
  | "lexicalClass"
  | "nameType"
  | "lemma"
  | "sentimentScore"
  | "language"

export interface TagParams {
  text: string
  language?: string
  schemes?: TagScheme[] // default: ["lexicalClass"]
}
export interface TagToken {
  text: string
  tags: Partial<Record<TagScheme, string>>
}
export interface TagResult {
  tokens: TagToken[]
}

export interface SentimentParams {
  text: string
}
export interface SentimentResult {
  score: number
  label: "positive" | "negative" | "neutral"
}

export interface LanguageParams {
  text: string
}
export interface LanguageResult {
  language: string
  confidence: number
}

// ---------------------------------------------------------------------------
// Vision
// ---------------------------------------------------------------------------

export type RecognitionLevel = "accurate" | "fast"

export interface OCRParams {
  path: string
  languages?: string[] // default: ["en-US"]
  level?: RecognitionLevel // default: "accurate"
}
export interface OCRBounds {
  x: number
  y: number
  width: number
  height: number
}
export interface OCRBlock {
  text: string
  confidence: number
  bounds: OCRBounds
}
export interface OCRResult {
  text: string
  blocks: OCRBlock[]
}

// Classification
export interface ClassifyParams {
  path: string
  max_results?: number // default: 10
}
export interface ClassificationItem {
  identifier: string
  confidence: number
}
export interface ClassifyResult {
  classifications: ClassificationItem[]
}

// Feature Print
export interface FeaturePrintParams {
  path: string
}
export interface FeaturePrintResult {
  vector: number[]
  dimensions: number
}

// Similarity
export interface SimilarityParams {
  path1: string
  path2: string
}
export interface SimilarityResult {
  distance: number
}

// Face Detection
export interface FaceBounds {
  x: number
  y: number
  width: number
  height: number
}
export interface FaceLandmarkPoints {
  points: number[][] // Array of [x, y] pairs
}
export interface FaceLandmarks {
  left_eye?: FaceLandmarkPoints
  right_eye?: FaceLandmarkPoints
  nose?: FaceLandmarkPoints
  mouth?: FaceLandmarkPoints
  face_contour?: FaceLandmarkPoints
}
export interface FaceObservation {
  bounds: FaceBounds
  confidence: number
  landmarks?: FaceLandmarks
}
export interface DetectFacesParams {
  path: string
  landmarks?: boolean // default: false
}
export interface DetectFacesResult {
  faces: FaceObservation[]
}

// Barcode Detection
export interface BarcodeObservation {
  payload: string | null
  symbology: string
  bounds: FaceBounds
}
export interface DetectBarcodesParams {
  path: string
  symbologies?: string[]
}
export interface DetectBarcodesResult {
  barcodes: BarcodeObservation[]
}

// Saliency
export type SaliencyType = "attention" | "objectness"
export interface SaliencyRegion {
  bounds: FaceBounds
  confidence: number
}
export interface SaliencyParams {
  path: string
  type?: SaliencyType // default: "attention"
}
export interface SaliencyResultData {
  type: SaliencyType
  regions: SaliencyRegion[]
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export type BiometryType = "touchID" | "opticID" | "none"

export interface AuthAvailableResult {
  available: boolean
  biometry_type: BiometryType
}
export interface AuthenticateParams {
  reason?: string
}
export interface AuthenticateResult {
  success: boolean
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

export interface MethodCapability {
  available: boolean
  note?: string
}
export interface CapabilitiesResult {
  version: string
  os: string
  arch: "arm64" | "x86_64" | "unknown"
  methods: Record<string, MethodCapability>
}

// ---------------------------------------------------------------------------
// iCloud
// ---------------------------------------------------------------------------

export interface ICloudStatusResult {
  available: boolean
  container_url: string
}

export interface ICloudReadParams {
  path: string
}
export interface ICloudReadResult {
  content: string
}

export interface ICloudWriteParams {
  path: string
  content: string
}
export interface ICloudWriteBytesParams {
  path: string
  data: string // base64
}

export interface ICloudDeleteParams {
  path: string
}
export interface ICloudMoveParams {
  source: string
  destination: string
}
export interface ICloudCopyFileParams {
  source: string
  destination: string
}

export interface ICloudListDirParams {
  path: string
}
export interface ICloudDirEntry {
  name: string
  is_directory: boolean
  size: number
  modified?: string // ISO8601
}
export interface ICloudListDirResult {
  entries: ICloudDirEntry[]
}

export interface ICloudEnsureDirParams {
  path: string
}
export interface ICloudOkResult {
  ok: true
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

export interface FilesChangedNotification {
  paths: string[]
}
export interface ReadyNotification {
  version: string
  capabilities: string[]
}

// ---------------------------------------------------------------------------
// CoreML
// ---------------------------------------------------------------------------

export type CoreMLComputeUnits =
  | "all"
  | "cpuAndGPU"
  | "cpuOnly"
  | "cpuAndNeuralEngine"

export interface CoreMLLoadModelParams {
  id: string
  path: string
  compute_units?: CoreMLComputeUnits
  warm_up?: boolean
}
export interface CoreMLModelInfo {
  id: string
  path: string
  dimensions: number
  compute_units: string
  size_bytes: number
  model_type: "coreml" | "contextual"
}

export interface CoreMLUnloadModelParams {
  id: string
}
export interface CoreMLModelInfoParams {
  id: string
}
export interface CoreMLModelsResult {
  models: CoreMLModelInfo[]
}

export interface CoreMLEmbedParams {
  model_id: string
  text: string
}
export interface CoreMLEmbedResult {
  vector: number[]
  dimensions: number
}

export interface CoreMLEmbedBatchParams {
  model_id: string
  texts: string[]
}
export interface CoreMLEmbedBatchResult {
  vectors: number[][]
  dimensions: number
  count: number
}

export interface CoreMLLoadContextualParams {
  id: string
  language: string
}
export interface CoreMLContextualEmbedParams {
  model_id: string
  text: string
}
export interface CoreMLContextualEmbedBatchParams {
  model_id: string
  texts: string[]
}
export interface CoreMLOkResult {
  ok: true
}

// ---------------------------------------------------------------------------
// MethodMap
// ---------------------------------------------------------------------------

export interface MethodMap {
  "nlp.embed": { params: EmbedParams; result: EmbedResult }
  "nlp.distance": { params: DistanceParams; result: DistanceResult }
  "nlp.neighbors": { params: NeighborsParams; result: NeighborsResult }
  "nlp.tag": { params: TagParams; result: TagResult }
  "nlp.sentiment": { params: SentimentParams; result: SentimentResult }
  "nlp.language": { params: LanguageParams; result: LanguageResult }
  "vision.ocr": { params: OCRParams; result: OCRResult }
  "vision.classify": { params: ClassifyParams; result: ClassifyResult }
  "vision.feature_print": {
    params: FeaturePrintParams
    result: FeaturePrintResult
  }
  "vision.similarity": { params: SimilarityParams; result: SimilarityResult }
  "vision.detect_faces": {
    params: DetectFacesParams
    result: DetectFacesResult
  }
  "vision.detect_barcodes": {
    params: DetectBarcodesParams
    result: DetectBarcodesResult
  }
  "vision.saliency": { params: SaliencyParams; result: SaliencyResultData }
  "auth.available": {
    params: Record<string, never>
    result: AuthAvailableResult
  }
  "auth.authenticate": {
    params: AuthenticateParams
    result: AuthenticateResult
  }
  "system.capabilities": {
    params: Record<string, never>
    result: CapabilitiesResult
  }
  "icloud.status": {
    params: Record<string, never>
    result: ICloudStatusResult
  }
  "icloud.read": { params: ICloudReadParams; result: ICloudReadResult }
  "icloud.write": { params: ICloudWriteParams; result: ICloudOkResult }
  "icloud.write_bytes": {
    params: ICloudWriteBytesParams
    result: ICloudOkResult
  }
  "icloud.delete": { params: ICloudDeleteParams; result: ICloudOkResult }
  "icloud.move": { params: ICloudMoveParams; result: ICloudOkResult }
  "icloud.copy_file": { params: ICloudCopyFileParams; result: ICloudOkResult }
  "icloud.list_dir": {
    params: ICloudListDirParams
    result: ICloudListDirResult
  }
  "icloud.ensure_dir": {
    params: ICloudEnsureDirParams
    result: ICloudOkResult
  }
  "icloud.start_monitoring": {
    params: Record<string, never>
    result: ICloudOkResult
  }
  "icloud.stop_monitoring": {
    params: Record<string, never>
    result: ICloudOkResult
  }
  "coreml.load_model": {
    params: CoreMLLoadModelParams
    result: CoreMLModelInfo
  }
  "coreml.unload_model": {
    params: CoreMLUnloadModelParams
    result: CoreMLOkResult
  }
  "coreml.model_info": {
    params: CoreMLModelInfoParams
    result: CoreMLModelInfo
  }
  "coreml.models": {
    params: Record<string, never>
    result: CoreMLModelsResult
  }
  "coreml.embed": {
    params: CoreMLEmbedParams
    result: CoreMLEmbedResult
  }
  "coreml.embed_batch": {
    params: CoreMLEmbedBatchParams
    result: CoreMLEmbedBatchResult
  }
  "coreml.load_contextual": {
    params: CoreMLLoadContextualParams
    result: CoreMLModelInfo
  }
  "coreml.contextual_embed": {
    params: CoreMLContextualEmbedParams
    result: CoreMLEmbedResult
  }
  "coreml.embed_contextual_batch": {
    params: CoreMLContextualEmbedBatchParams
    result: CoreMLEmbedBatchResult
  }
}

export type MethodName = keyof MethodMap

// ---------------------------------------------------------------------------
// PreparedCall (for batch API)
// ---------------------------------------------------------------------------

export interface PreparedCall<M extends MethodName> {
  readonly method: M
  readonly params: MethodMap[M]["params"]
  readonly __brand: MethodMap[M]["result"] // phantom type for inference
}

// Helper type to extract results from a tuple of PreparedCalls
export type BatchResult<T extends ReadonlyArray<PreparedCall<MethodName>>> = {
  [K in keyof T]: T[K] extends PreparedCall<infer M>
    ? MethodMap[M]["result"]
    : never
}
