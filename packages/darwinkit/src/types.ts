// ---------------------------------------------------------------------------
// NLP
// ---------------------------------------------------------------------------

export type EmbedType = "word" | "sentence";
export type NLPLanguage = "en" | "es" | "fr" | "de" | "it" | "pt" | "zh-Hans";

export interface EmbedParams {
  text: string;
  language: string;
  type?: EmbedType; // default: "sentence"
}
export interface EmbedResult {
  vector: number[];
  dimension: number;
}

export interface DistanceParams {
  text1: string;
  text2: string;
  language: string;
  type?: EmbedType; // default: "word"
}
export interface DistanceResult {
  distance: number;
  type: "cosine";
}

export interface NeighborsParams {
  text: string;
  language: string;
  type?: EmbedType; // default: "word"
  count?: number; // default: 5
}
export interface Neighbor {
  text: string;
  distance: number;
}
export interface NeighborsResult {
  neighbors: Neighbor[];
}

export type TagScheme =
  | "lexicalClass"
  | "nameType"
  | "lemma"
  | "sentimentScore"
  | "language";

export interface TagParams {
  text: string;
  language?: string;
  schemes?: TagScheme[]; // default: ["lexicalClass"]
}
export interface TagToken {
  text: string;
  tags: Partial<Record<TagScheme, string>>;
}
export interface TagResult {
  tokens: TagToken[];
}

export interface SentimentParams {
  text: string;
}
export interface SentimentResult {
  score: number;
  label: "positive" | "negative" | "neutral";
}

export interface LanguageParams {
  text: string;
}
export interface LanguageResult {
  language: string;
  confidence: number;
}

// ---------------------------------------------------------------------------
// Vision
// ---------------------------------------------------------------------------

export type RecognitionLevel = "accurate" | "fast";

export interface OCRParams {
  path: string;
  languages?: string[]; // default: ["en-US"]
  level?: RecognitionLevel; // default: "accurate"
}
export interface OCRBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface OCRBlock {
  text: string;
  confidence: number;
  bounds: OCRBounds;
}
export interface OCRResult {
  text: string;
  blocks: OCRBlock[];
}

// Classification
export interface ClassifyParams {
  path: string;
  max_results?: number; // default: 10
}
export interface ClassificationItem {
  identifier: string;
  confidence: number;
}
export interface ClassifyResult {
  classifications: ClassificationItem[];
}

// Feature Print
export interface FeaturePrintParams {
  path: string;
}
export interface FeaturePrintResult {
  vector: number[];
  dimensions: number;
}

// Similarity
export interface SimilarityParams {
  path1: string;
  path2: string;
}
export interface SimilarityResult {
  distance: number;
}

// Face Detection
export interface FaceBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface FaceLandmarkPoints {
  points: number[][]; // Array of [x, y] pairs
}
export interface FaceLandmarks {
  left_eye?: FaceLandmarkPoints;
  right_eye?: FaceLandmarkPoints;
  nose?: FaceLandmarkPoints;
  mouth?: FaceLandmarkPoints;
  face_contour?: FaceLandmarkPoints;
}
export interface FaceObservation {
  bounds: FaceBounds;
  confidence: number;
  landmarks?: FaceLandmarks;
}
export interface DetectFacesParams {
  path: string;
  landmarks?: boolean; // default: false
}
export interface DetectFacesResult {
  faces: FaceObservation[];
}

// Barcode Detection
export interface BarcodeObservation {
  payload: string | null;
  symbology: string;
  bounds: FaceBounds;
}
export interface DetectBarcodesParams {
  path: string;
  symbologies?: string[];
}
export interface DetectBarcodesResult {
  barcodes: BarcodeObservation[];
}

// Saliency
export type SaliencyType = "attention" | "objectness";
export interface SaliencyRegion {
  bounds: FaceBounds;
  confidence: number;
}
export interface SaliencyParams {
  path: string;
  type?: SaliencyType; // default: "attention"
}
export interface SaliencyResultData {
  type: SaliencyType;
  regions: SaliencyRegion[];
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export type BiometryType = "touchID" | "opticID" | "none";

export interface AuthAvailableResult {
  available: boolean;
  biometry_type: BiometryType;
}
export interface AuthenticateParams {
  reason?: string;
}
export interface AuthenticateResult {
  success: boolean;
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

export interface MethodCapability {
  available: boolean;
  note?: string;
}
export interface CapabilitiesResult {
  version: string;
  os: string;
  arch: "arm64" | "x86_64" | "unknown";
  methods: Record<string, MethodCapability>;
}

// ---------------------------------------------------------------------------
// iCloud
// ---------------------------------------------------------------------------

export interface ICloudStatusResult {
  available: boolean;
  container_url: string;
}

export interface ICloudReadParams {
  path: string;
}
export interface ICloudReadResult {
  content: string;
}

export interface ICloudWriteParams {
  path: string;
  content: string;
}
export interface ICloudWriteBytesParams {
  path: string;
  data: string; // base64
}

export interface ICloudDeleteParams {
  path: string;
}
export interface ICloudMoveParams {
  source: string;
  destination: string;
}
export interface ICloudCopyFileParams {
  source: string;
  destination: string;
}

export interface ICloudListDirParams {
  path: string;
}
export interface ICloudDirEntry {
  name: string;
  is_directory: boolean;
  size: number;
  modified?: string; // ISO8601
}
export interface ICloudListDirResult {
  entries: ICloudDirEntry[];
}

export interface ICloudEnsureDirParams {
  path: string;
}
export interface ICloudOkResult {
  ok: true;
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

export interface FilesChangedNotification {
  paths: string[];
}
export interface ReadyNotification {
  version: string;
  capabilities: string[];
}

// ---------------------------------------------------------------------------
// CoreML
// ---------------------------------------------------------------------------

export type CoreMLComputeUnits =
  | "all"
  | "cpuAndGPU"
  | "cpuOnly"
  | "cpuAndNeuralEngine";

export interface CoreMLLoadModelParams {
  id: string;
  path: string;
  compute_units?: CoreMLComputeUnits;
  warm_up?: boolean;
}
export interface CoreMLModelInfo {
  id: string;
  path: string;
  dimensions: number;
  compute_units: string;
  size_bytes: number;
  model_type: "coreml" | "contextual";
}

export interface CoreMLUnloadModelParams {
  id: string;
}
export interface CoreMLModelInfoParams {
  id: string;
}
export interface CoreMLModelsResult {
  models: CoreMLModelInfo[];
}

export interface CoreMLEmbedParams {
  model_id: string;
  text: string;
}
export interface CoreMLEmbedResult {
  vector: number[];
  dimensions: number;
}

export interface CoreMLEmbedBatchParams {
  model_id: string;
  texts: string[];
}
export interface CoreMLEmbedBatchResult {
  vectors: number[][];
  dimensions: number;
  count: number;
}

export interface CoreMLLoadContextualParams {
  id: string;
  language: string;
}
export interface CoreMLContextualEmbedParams {
  model_id: string;
  text: string;
}
export interface CoreMLContextualEmbedBatchParams {
  model_id: string;
  texts: string[];
}
export interface CoreMLOkResult {
  ok: true;
}

// ---------------------------------------------------------------------------
// Translation
// ---------------------------------------------------------------------------

export interface TranslateTextParams {
  text: string;
  source?: string; // omit for auto-detect
  target: string;
}
export interface TranslateTextResult {
  text: string;
  source: string;
  target: string;
}

export interface TranslateBatchParams {
  texts: string[];
  source?: string; // omit for auto-detect
  target: string;
}
export interface TranslateBatchResult {
  translations: TranslateTextResult[];
}

export interface TranslateLanguagesResult {
  languages: TranslateLanguageInfo[];
}
export interface TranslateLanguageInfo {
  locale: string;
  name: string;
}

export interface TranslateLanguageStatusParams {
  source: string;
  target: string;
}
export type TranslateLanguageStatus = "installed" | "supported" | "unsupported";
export interface TranslateLanguageStatusResult {
  status: TranslateLanguageStatus;
  source: string;
  target: string;
}

export interface TranslatePrepareParams {
  source: string;
  target: string;
}
export interface TranslatePrepareResult {
  ok: true;
  source: string;
  target: string;
}

// ---------------------------------------------------------------------------
// Speech
// ---------------------------------------------------------------------------

export interface SpeechTranscribeParams {
  path: string;
  language?: string; // default: "en-US"
  timestamps?: boolean; // default: true
}
export interface SpeechTranscriptionSegment {
  text: string;
  start_time: number;
  end_time: number;
  is_final: boolean;
}
export interface SpeechTranscribeResult {
  text: string;
  segments: SpeechTranscriptionSegment[];
  language: string;
  duration: number;
}

export interface SpeechLanguageInfo {
  locale: string;
  installed: boolean;
}
export interface SpeechLanguagesResult {
  languages: SpeechLanguageInfo[];
}

export interface SpeechInstallLanguageParams {
  locale: string;
}
export interface SpeechUninstallLanguageParams {
  locale: string;
}
export interface SpeechOkResult {
  ok: true;
}

export interface SpeechCapabilitiesResult {
  available: boolean;
  reason?: string;
}

// ---------------------------------------------------------------------------
// Sound Analysis
// ---------------------------------------------------------------------------

export interface SoundClassification {
  identifier: string;
  confidence: number;
}

export interface SoundClassifyParams {
  path: string;
  top_n?: number; // default: 5
}

export interface SoundTimeRange {
  start: number;
  duration: number;
}

export interface SoundClassifyResult {
  classifications: SoundClassification[];
  time_range?: SoundTimeRange;
}

export interface SoundClassifyAtParams {
  path: string;
  start: number;
  duration: number;
  top_n?: number; // default: 5
}

export interface SoundClassifyAtResult {
  classifications: SoundClassification[];
  time_range: SoundTimeRange; // always present for classify_at
}

export interface SoundCategoriesResult {
  categories: string[];
}

export interface SoundAvailableResult {
  available: boolean;
}

// ---------------------------------------------------------------------------
// LLM (Foundation Models)
// ---------------------------------------------------------------------------

export interface LLMGenerateParams {
  prompt: string;
  system_instructions?: string;
  temperature?: number;
  max_tokens?: number;
}
export interface LLMGenerateResult {
  text: string;
}

export interface LLMGenerateStructuredParams {
  prompt: string;
  schema: Record<string, unknown>;
  system_instructions?: string;
  temperature?: number;
  max_tokens?: number;
}
export interface LLMGenerateStructuredResult {
  json: Record<string, unknown>;
}

export interface LLMStreamParams {
  prompt: string;
  system_instructions?: string;
  temperature?: number;
  max_tokens?: number;
}

export interface LLMSessionCreateParams {
  session_id: string;
  instructions?: string;
}

export interface LLMSessionRespondParams {
  session_id: string;
  prompt: string;
  temperature?: number;
  max_tokens?: number;
}

export interface LLMSessionCloseParams {
  session_id: string;
}

export interface LLMAvailableResult {
  available: boolean;
  reason?: string;
}

export interface LLMOkResult {
  ok: true;
}

export interface LLMChunkNotification {
  request_id: string;
  chunk: string;
}

// ---------------------------------------------------------------------------
// Contacts
// ---------------------------------------------------------------------------

export interface ContactEmailAddress {
  label: string;
  value: string;
}
export interface ContactPhoneNumber {
  label: string;
  value: string;
}
export interface ContactPostalAddress {
  label: string;
  street: string;
  city: string;
  state: string;
  postal_code: string;
  country: string;
}

export interface ContactInfo {
  identifier: string;
  given_name: string;
  family_name: string;
  organization_name: string;
  email_addresses: ContactEmailAddress[];
  phone_numbers: ContactPhoneNumber[];
  postal_addresses: ContactPostalAddress[];
  birthday?: string;
  thumbnail_image_base64?: string;
}

export interface ContactsAuthorizedResult {
  status: "authorized" | "denied" | "restricted" | "notDetermined";
  authorized: boolean;
}
export interface ContactsListParams {
  limit?: number;
}
export interface ContactsListResult {
  contacts: ContactInfo[];
}
export interface ContactsGetParams {
  identifier: string;
}
export interface ContactsSearchParams {
  query: string;
  limit?: number;
}
export interface ContactsSearchResult {
  contacts: ContactInfo[];
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

export interface CalendarInfo {
  identifier: string;
  title: string;
  type:
    | "local"
    | "calDAV"
    | "exchange"
    | "subscription"
    | "birthday"
    | "unknown";
  color: string;
  source: string;
  is_immutable: boolean;
  allows_content_modifications: boolean;
}

export interface CalendarEventInfo {
  identifier: string;
  title: string;
  start_date: string;
  end_date: string;
  is_all_day: boolean;
  location?: string;
  notes?: string;
  calendar_identifier: string;
  calendar_title: string;
  url?: string;
  availability: "free" | "busy" | "tentative" | "unavailable";
  has_alarms: boolean;
  alarms: number[];
  external_identifier?: string;
}

export interface SourceInfo {
  identifier: string;
  title: string;
  source_type:
    | "local"
    | "exchange"
    | "calDAV"
    | "mobileMe"
    | "subscribed"
    | "birthdays"
    | "unknown";
}

export interface CalendarSaveResult {
  success: boolean;
  identifier?: string;
  error?: string;
}

export interface CalendarOkResult {
  ok: boolean;
}

export interface CalendarAuthorizedResult {
  status:
    | "fullAccess"
    | "writeOnly"
    | "denied"
    | "restricted"
    | "notDetermined";
  authorized: boolean;
}
export interface CalendarCalendarsResult {
  calendars: CalendarInfo[];
}
export interface CalendarEventsParams {
  start_date: string;
  end_date: string;
  calendar_identifiers?: string[];
}
export interface CalendarEventsResult {
  events: CalendarEventInfo[];
}
export interface CalendarEventParams {
  identifier: string;
}

export interface CalendarSaveEventParams {
  id?: string;
  calendar_identifier: string;
  title: string;
  start_date: string;
  end_date: string;
  notes?: string;
  location?: string;
  url?: string;
  is_all_day?: boolean;
  availability?: "free" | "busy" | "tentative" | "unavailable";
  alarms?: number[];
  span?: "thisEvent" | "futureEvents";
  commit?: boolean;
}

export interface CalendarRemoveEventParams {
  identifier: string;
  span?: "thisEvent" | "futureEvents";
  commit?: boolean;
}

export interface CalendarItemParams {
  identifier: string;
}

export interface CalendarItemResult {
  type: "event" | "reminder";
  item: CalendarEventInfo | ReminderInfo;
}

export interface CalendarItemsExternalParams {
  external_identifier: string;
}

export interface CalendarItemsExternalResult {
  items: CalendarItemResult[];
}

export interface CalendarSourcesResult {
  sources: SourceInfo[];
}

export interface CalendarSourceParams {
  identifier: string;
}

export interface CalendarSaveCalendarParams {
  id?: string;
  title: string;
  source_identifier: string;
  entity_type?: "event" | "reminder";
  color_hex?: string;
  commit?: boolean;
}

export interface CalendarRemoveCalendarParams {
  identifier: string;
  commit?: boolean;
}

// ---------------------------------------------------------------------------
// Reminders
// ---------------------------------------------------------------------------

export interface ReminderListInfo {
  identifier: string;
  title: string;
  color: string;
  source: string;
}

export interface ReminderInfo {
  identifier: string;
  title: string;
  is_completed: boolean;
  completion_date?: string;
  due_date?: string;
  start_date?: string;
  priority: number;
  notes?: string;
  url?: string;
  list_identifier: string;
  list_title: string;
  has_alarms: boolean;
  external_identifier?: string;
}

export interface RemindersAuthorizedResult {
  status: "fullAccess" | "denied" | "restricted" | "notDetermined";
  authorized: boolean;
}
export interface RemindersListsResult {
  lists: ReminderListInfo[];
}
export interface RemindersItemsParams {
  filter?: "completed" | "incomplete";
  list_identifiers?: string[];
}
export interface RemindersItemsResult {
  reminders: ReminderInfo[];
}

export interface RemindersSaveItemParams {
  id?: string;
  calendar_identifier: string;
  title: string;
  due_date?: string;
  start_date?: string;
  priority?: number;
  notes?: string;
  completed?: boolean;
  url?: string;
  commit?: boolean;
}

export interface RemindersSaveResult {
  success: boolean;
  identifier?: string;
  error?: string;
}

export interface RemindersRemoveItemParams {
  identifier: string;
  commit?: boolean;
}

export interface RemindersCompleteItemParams {
  identifier: string;
}

export interface RemindersIncompleteParams {
  start_date?: string;
  end_date?: string;
  list_identifiers?: string[];
}

export interface RemindersCompletedParams {
  start_date?: string;
  end_date?: string;
  list_identifiers?: string[];
}

// ---------------------------------------------------------------------------
// Notifications (UNUserNotificationCenter)
// ---------------------------------------------------------------------------

export type NotifyAuthorizationOption =
  | "alert"
  | "sound"
  | "badge"
  | "criticalAlert"
  | "provisional";

export interface NotifyRequestAuthorizationParams {
  options?: NotifyAuthorizationOption[];
}
export interface NotifyRequestAuthorizationResult {
  granted: boolean;
}

export type NotifyAuthorizationStatus =
  | "notDetermined"
  | "denied"
  | "authorized"
  | "provisional"
  | "ephemeral";
export type NotifyAlertSetting = "notSupported" | "disabled" | "enabled";

export interface NotifySettingsResult {
  authorization_status: NotifyAuthorizationStatus;
  sound_setting: NotifyAlertSetting;
  badge_setting: NotifyAlertSetting;
  alert_setting: NotifyAlertSetting;
  notification_center_setting: NotifyAlertSetting;
  lock_screen_setting: NotifyAlertSetting;
  critical_alert_setting: NotifyAlertSetting;
  alert_style: "none" | "banner" | "alert";
}

export type NotifySoundType =
  | "default"
  | "none"
  | { named: string }
  | { critical: { volume?: number } };

export interface NotifyTriggerTimeInterval {
  type: "timeInterval";
  seconds: number;
  repeats?: boolean;
}
export interface NotifyTriggerCalendar {
  type: "calendar";
  year?: number;
  month?: number;
  day?: number;
  hour?: number;
  minute?: number;
  second?: number;
  weekday?: number;
  repeats?: boolean;
}
export type NotifyTrigger = NotifyTriggerTimeInterval | NotifyTriggerCalendar;

export interface NotifySendParams {
  title: string;
  body: string;
  subtitle?: string;
  identifier?: string;
  sound?: NotifySoundType;
  badge?: number;
  thread_identifier?: string;
  category_identifier?: string;
  user_info?: Record<string, unknown>;
  attachments?: string[];
  trigger?: NotifyTrigger;
}
export interface NotifySendResult {
  ok: true;
  identifier: string;
}

export interface NotifyActionParams {
  identifier: string;
  title: string;
  text_input?: boolean;
  text_input_button_title?: string;
  text_input_placeholder?: string;
  destructive?: boolean;
  auth_required?: boolean;
}
export interface NotifyRegisterCategoryParams {
  identifier: string;
  actions: NotifyActionParams[];
  hidden_preview_placeholder?: string;
  custom_dismiss_action?: boolean;
}

export interface NotifyPendingInfo {
  identifier: string;
  title: string;
  body: string;
  subtitle?: string;
  thread_identifier?: string;
  category_identifier?: string;
  trigger_type?: string;
  next_trigger_date?: string;
}
export interface NotifyPendingResult {
  notifications: NotifyPendingInfo[];
}

export interface NotifyDeliveredInfo {
  identifier: string;
  title: string;
  body: string;
  subtitle?: string;
  thread_identifier?: string;
  category_identifier?: string;
  date: string;
}
export interface NotifyDeliveredResult {
  notifications: NotifyDeliveredInfo[];
}

export interface NotifyRemoveParams {
  identifiers: string[];
}

export interface NotifyOkResult {
  ok: true;
}

export interface NotifyInteractionEvent {
  notification_identifier: string;
  action_identifier: string;
  user_text?: string;
  user_info: Record<string, unknown>;
  category_identifier: string;
}

// ---------------------------------------------------------------------------
// MethodMap
// ---------------------------------------------------------------------------

export interface MethodMap {
  "nlp.embed": { params: EmbedParams; result: EmbedResult };
  "nlp.distance": { params: DistanceParams; result: DistanceResult };
  "nlp.neighbors": { params: NeighborsParams; result: NeighborsResult };
  "nlp.tag": { params: TagParams; result: TagResult };
  "nlp.sentiment": { params: SentimentParams; result: SentimentResult };
  "nlp.language": { params: LanguageParams; result: LanguageResult };
  "vision.ocr": { params: OCRParams; result: OCRResult };
  "vision.classify": { params: ClassifyParams; result: ClassifyResult };
  "vision.feature_print": {
    params: FeaturePrintParams;
    result: FeaturePrintResult;
  };
  "vision.similarity": { params: SimilarityParams; result: SimilarityResult };
  "vision.detect_faces": {
    params: DetectFacesParams;
    result: DetectFacesResult;
  };
  "vision.detect_barcodes": {
    params: DetectBarcodesParams;
    result: DetectBarcodesResult;
  };
  "vision.saliency": { params: SaliencyParams; result: SaliencyResultData };
  "auth.available": {
    params: Record<string, never>;
    result: AuthAvailableResult;
  };
  "auth.authenticate": {
    params: AuthenticateParams;
    result: AuthenticateResult;
  };
  "system.capabilities": {
    params: Record<string, never>;
    result: CapabilitiesResult;
  };
  "icloud.status": {
    params: Record<string, never>;
    result: ICloudStatusResult;
  };
  "icloud.read": { params: ICloudReadParams; result: ICloudReadResult };
  "icloud.write": { params: ICloudWriteParams; result: ICloudOkResult };
  "icloud.write_bytes": {
    params: ICloudWriteBytesParams;
    result: ICloudOkResult;
  };
  "icloud.delete": { params: ICloudDeleteParams; result: ICloudOkResult };
  "icloud.move": { params: ICloudMoveParams; result: ICloudOkResult };
  "icloud.copy_file": { params: ICloudCopyFileParams; result: ICloudOkResult };
  "icloud.list_dir": {
    params: ICloudListDirParams;
    result: ICloudListDirResult;
  };
  "icloud.ensure_dir": {
    params: ICloudEnsureDirParams;
    result: ICloudOkResult;
  };
  "icloud.start_monitoring": {
    params: Record<string, never>;
    result: ICloudOkResult;
  };
  "icloud.stop_monitoring": {
    params: Record<string, never>;
    result: ICloudOkResult;
  };
  "coreml.load_model": {
    params: CoreMLLoadModelParams;
    result: CoreMLModelInfo;
  };
  "coreml.unload_model": {
    params: CoreMLUnloadModelParams;
    result: CoreMLOkResult;
  };
  "coreml.model_info": {
    params: CoreMLModelInfoParams;
    result: CoreMLModelInfo;
  };
  "coreml.models": {
    params: Record<string, never>;
    result: CoreMLModelsResult;
  };
  "coreml.embed": {
    params: CoreMLEmbedParams;
    result: CoreMLEmbedResult;
  };
  "coreml.embed_batch": {
    params: CoreMLEmbedBatchParams;
    result: CoreMLEmbedBatchResult;
  };
  "coreml.load_contextual": {
    params: CoreMLLoadContextualParams;
    result: CoreMLModelInfo;
  };
  "coreml.contextual_embed": {
    params: CoreMLContextualEmbedParams;
    result: CoreMLEmbedResult;
  };
  "coreml.embed_contextual_batch": {
    params: CoreMLContextualEmbedBatchParams;
    result: CoreMLEmbedBatchResult;
  };
  "translate.text": {
    params: TranslateTextParams;
    result: TranslateTextResult;
  };
  "translate.batch": {
    params: TranslateBatchParams;
    result: TranslateBatchResult;
  };
  "translate.languages": {
    params: Record<string, never>;
    result: TranslateLanguagesResult;
  };
  "translate.language_status": {
    params: TranslateLanguageStatusParams;
    result: TranslateLanguageStatusResult;
  };
  "translate.prepare": {
    params: TranslatePrepareParams;
    result: TranslatePrepareResult;
  };
  "speech.transcribe": {
    params: SpeechTranscribeParams;
    result: SpeechTranscribeResult;
  };
  "speech.languages": {
    params: Record<string, never>;
    result: SpeechLanguagesResult;
  };
  "speech.installed_languages": {
    params: Record<string, never>;
    result: SpeechLanguagesResult;
  };
  "speech.install_language": {
    params: SpeechInstallLanguageParams;
    result: SpeechOkResult;
  };
  "speech.uninstall_language": {
    params: SpeechUninstallLanguageParams;
    result: SpeechOkResult;
  };
  "speech.capabilities": {
    params: Record<string, never>;
    result: SpeechCapabilitiesResult;
  };
  "sound.classify": {
    params: SoundClassifyParams;
    result: SoundClassifyResult;
  };
  "sound.classify_at": {
    params: SoundClassifyAtParams;
    result: SoundClassifyAtResult;
  };
  "sound.categories": {
    params: Record<string, never>;
    result: SoundCategoriesResult;
  };
  "sound.available": {
    params: Record<string, never>;
    result: SoundAvailableResult;
  };
  "llm.generate": {
    params: LLMGenerateParams;
    result: LLMGenerateResult;
  };
  "llm.generate_structured": {
    params: LLMGenerateStructuredParams;
    result: LLMGenerateStructuredResult;
  };
  "llm.stream": {
    params: LLMStreamParams;
    result: LLMGenerateResult;
  };
  "llm.session_create": {
    params: LLMSessionCreateParams;
    result: LLMOkResult;
  };
  "llm.session_respond": {
    params: LLMSessionRespondParams;
    result: LLMGenerateResult;
  };
  "llm.session_close": {
    params: LLMSessionCloseParams;
    result: LLMOkResult;
  };
  "llm.available": {
    params: Record<string, never>;
    result: LLMAvailableResult;
  };
  // Contacts
  "contacts.authorized": {
    params: Record<string, never>;
    result: ContactsAuthorizedResult;
  };
  "contacts.list": {
    params: ContactsListParams;
    result: ContactsListResult;
  };
  "contacts.get": {
    params: ContactsGetParams;
    result: ContactInfo;
  };
  "contacts.search": {
    params: ContactsSearchParams;
    result: ContactsSearchResult;
  };
  // Calendar
  "calendar.authorized": {
    params: Record<string, never>;
    result: CalendarAuthorizedResult;
  };
  "calendar.calendars": {
    params: Record<string, never>;
    result: CalendarCalendarsResult;
  };
  "calendar.events": {
    params: CalendarEventsParams;
    result: CalendarEventsResult;
  };
  "calendar.event": {
    params: CalendarEventParams;
    result: CalendarEventInfo;
  };
  "calendar.save_event": {
    params: CalendarSaveEventParams;
    result: CalendarSaveResult;
  };
  "calendar.remove_event": {
    params: CalendarRemoveEventParams;
    result: CalendarOkResult;
  };
  "calendar.calendar_item": {
    params: CalendarItemParams;
    result: CalendarItemResult;
  };
  "calendar.calendar_items_external": {
    params: CalendarItemsExternalParams;
    result: CalendarItemsExternalResult;
  };
  "calendar.sources": {
    params: Record<string, never>;
    result: CalendarSourcesResult;
  };
  "calendar.source": {
    params: CalendarSourceParams;
    result: SourceInfo;
  };
  "calendar.delegate_sources": {
    params: Record<string, never>;
    result: CalendarSourcesResult;
  };
  "calendar.save_calendar": {
    params: CalendarSaveCalendarParams;
    result: CalendarSaveResult;
  };
  "calendar.remove_calendar": {
    params: CalendarRemoveCalendarParams;
    result: CalendarOkResult;
  };
  "calendar.default_calendar_events": {
    params: Record<string, never>;
    result: CalendarInfo | null;
  };
  "calendar.default_calendar_reminders": {
    params: Record<string, never>;
    result: CalendarInfo | null;
  };
  "calendar.commit": {
    params: Record<string, never>;
    result: CalendarOkResult;
  };
  "calendar.reset": {
    params: Record<string, never>;
    result: CalendarOkResult;
  };
  "calendar.refresh_sources": {
    params: Record<string, never>;
    result: CalendarOkResult;
  };
  "calendar.request_write_only_access": {
    params: Record<string, never>;
    result: CalendarAuthorizedResult;
  };
  // Reminders
  "reminders.authorized": {
    params: Record<string, never>;
    result: RemindersAuthorizedResult;
  };
  "reminders.lists": {
    params: Record<string, never>;
    result: RemindersListsResult;
  };
  "reminders.items": {
    params: RemindersItemsParams;
    result: RemindersItemsResult;
  };
  "reminders.save_item": {
    params: RemindersSaveItemParams;
    result: RemindersSaveResult;
  };
  "reminders.remove_item": {
    params: RemindersRemoveItemParams;
    result: CalendarOkResult;
  };
  "reminders.complete_item": {
    params: RemindersCompleteItemParams;
    result: ReminderInfo;
  };
  "reminders.incomplete": {
    params: RemindersIncompleteParams;
    result: RemindersItemsResult;
  };
  "reminders.completed": {
    params: RemindersCompletedParams;
    result: RemindersItemsResult;
  };
  // Notifications
  "notifications.request_authorization": {
    params: NotifyRequestAuthorizationParams;
    result: NotifyRequestAuthorizationResult;
  };
  "notifications.settings": {
    params: Record<string, never>;
    result: NotifySettingsResult;
  };
  "notifications.send": {
    params: NotifySendParams;
    result: NotifySendResult;
  };
  "notifications.list_pending": {
    params: Record<string, never>;
    result: NotifyPendingResult;
  };
  "notifications.remove_pending": {
    params: NotifyRemoveParams;
    result: NotifyOkResult;
  };
  "notifications.remove_all_pending": {
    params: Record<string, never>;
    result: NotifyOkResult;
  };
  "notifications.list_delivered": {
    params: Record<string, never>;
    result: NotifyDeliveredResult;
  };
  "notifications.remove_delivered": {
    params: NotifyRemoveParams;
    result: NotifyOkResult;
  };
  "notifications.remove_all_delivered": {
    params: Record<string, never>;
    result: NotifyOkResult;
  };
  "notifications.register_category": {
    params: NotifyRegisterCategoryParams;
    result: NotifyOkResult;
  };
}

export type MethodName = keyof MethodMap;

// ---------------------------------------------------------------------------
// PreparedCall (for batch API)
// ---------------------------------------------------------------------------

export interface PreparedCall<M extends MethodName> {
  readonly method: M;
  readonly params: MethodMap[M]["params"];
  readonly __brand: MethodMap[M]["result"]; // phantom type for inference
}

// Helper type to extract results from a tuple of PreparedCalls
export type BatchResult<T extends ReadonlyArray<PreparedCall<MethodName>>> = {
  [K in keyof T]: T[K] extends PreparedCall<infer M>
    ? MethodMap[M]["result"]
    : never;
};
