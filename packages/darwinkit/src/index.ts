export { DarwinKit } from "./client.js";
export type {
  DarwinKitOptions,
  DarwinKitClient,
  Logger,
  LogLevel,
} from "./client.js";
export { DarwinKitError, ErrorCodes } from "./errors.js";
export type { ErrorCode } from "./errors.js";
export type { DarwinKitEvent, EventMap, EventType } from "./events.js";
export { ensureBinary } from "./binary.js";

// Namespace classes (for advanced usage / custom composition)
export { NLP } from "./namespaces/nlp.js";
export { Vision } from "./namespaces/vision.js";
export { Auth } from "./namespaces/auth.js";
export { System } from "./namespaces/system.js";
export { ICloud } from "./namespaces/icloud.js";
export { CoreML } from "./namespaces/coreml.js";
export { Translate } from "./namespaces/translate.js";
export { Speech } from "./namespaces/speech.js";
export { Sound } from "./namespaces/sound.js";
export { LLM } from "./namespaces/llm.js";
export { Contacts } from "./namespaces/contacts.js";
export { Calendar } from "./namespaces/calendar.js";
export { Reminders } from "./namespaces/reminders.js";
export { Notifications } from "./namespaces/notifications.js";

// All types
export type {
  MethodMap,
  MethodName,
  PreparedCall,
  BatchResult,
  // NLP
  EmbedType,
  NLPLanguage,
  EmbedParams,
  EmbedResult,
  DistanceParams,
  DistanceResult,
  Neighbor,
  NeighborsParams,
  NeighborsResult,
  TagScheme,
  TagParams,
  TagToken,
  TagResult,
  SentimentParams,
  SentimentResult,
  LanguageParams,
  LanguageResult,
  // Vision
  RecognitionLevel,
  OCRParams,
  OCRBounds,
  OCRBlock,
  OCRResult,
  ClassifyParams,
  ClassificationItem,
  ClassifyResult,
  FeaturePrintParams,
  FeaturePrintResult,
  SimilarityParams,
  SimilarityResult,
  FaceBounds,
  FaceLandmarkPoints,
  FaceLandmarks,
  FaceObservation,
  DetectFacesParams,
  DetectFacesResult,
  BarcodeObservation,
  DetectBarcodesParams,
  DetectBarcodesResult,
  SaliencyType,
  SaliencyRegion,
  SaliencyParams,
  SaliencyResultData,
  // Auth
  BiometryType,
  AuthAvailableResult,
  AuthenticateParams,
  AuthenticateResult,
  // System
  MethodCapability,
  CapabilitiesResult,
  // iCloud
  ICloudStatusResult,
  ICloudReadParams,
  ICloudReadResult,
  ICloudWriteParams,
  ICloudWriteBytesParams,
  ICloudDeleteParams,
  ICloudMoveParams,
  ICloudCopyFileParams,
  ICloudListDirParams,
  ICloudDirEntry,
  ICloudListDirResult,
  ICloudEnsureDirParams,
  ICloudOkResult,
  // CoreML
  CoreMLComputeUnits,
  CoreMLLoadModelParams,
  CoreMLModelInfo,
  CoreMLUnloadModelParams,
  CoreMLModelInfoParams,
  CoreMLModelsResult,
  CoreMLEmbedParams,
  CoreMLEmbedResult,
  CoreMLEmbedBatchParams,
  CoreMLEmbedBatchResult,
  CoreMLLoadContextualParams,
  CoreMLContextualEmbedParams,
  CoreMLContextualEmbedBatchParams,
  CoreMLOkResult,
  // Translation
  TranslateTextParams,
  TranslateTextResult,
  TranslateBatchParams,
  TranslateBatchResult,
  TranslateLanguagesResult,
  TranslateLanguageInfo,
  TranslateLanguageStatusParams,
  TranslateLanguageStatus,
  TranslateLanguageStatusResult,
  TranslatePrepareParams,
  TranslatePrepareResult,
  // Speech
  SpeechTranscribeParams,
  SpeechTranscriptionSegment,
  SpeechTranscribeResult,
  SpeechLanguageInfo,
  SpeechLanguagesResult,
  SpeechInstallLanguageParams,
  SpeechUninstallLanguageParams,
  SpeechOkResult,
  SpeechCapabilitiesResult,
  // Sound Analysis
  SoundClassification,
  SoundClassifyParams,
  SoundTimeRange,
  SoundClassifyResult,
  SoundClassifyAtParams,
  SoundClassifyAtResult,
  SoundCategoriesResult,
  SoundAvailableResult,
  // LLM
  LLMGenerateParams,
  LLMGenerateResult,
  LLMGenerateStructuredParams,
  LLMGenerateStructuredResult,
  LLMStreamParams,
  LLMSessionCreateParams,
  LLMSessionRespondParams,
  LLMSessionCloseParams,
  LLMAvailableResult,
  LLMOkResult,
  LLMChunkNotification,
  // Contacts
  ContactEmailAddress,
  ContactPhoneNumber,
  ContactPostalAddress,
  ContactInfo,
  ContactsAuthorizedResult,
  ContactsListParams,
  ContactsListResult,
  ContactsGetParams,
  ContactsSearchParams,
  ContactsSearchResult,
  // Calendar
  CalendarInfo,
  CalendarEventInfo,
  CalendarAuthorizedResult,
  CalendarCalendarsResult,
  CalendarEventsParams,
  CalendarEventsResult,
  CalendarEventParams,
  // Reminders
  ReminderListInfo,
  ReminderInfo,
  RemindersAuthorizedResult,
  RemindersListsResult,
  RemindersItemsParams,
  RemindersItemsResult,
  // Notifications (system)
  ReadyNotification,
  FilesChangedNotification,
  // Notifications (UNUserNotificationCenter)
  NotifyAuthorizationOption,
  NotifyRequestAuthorizationParams,
  NotifyRequestAuthorizationResult,
  NotifyAuthorizationStatus,
  NotifyAlertSetting,
  NotifySettingsResult,
  NotifySoundType,
  NotifyTriggerTimeInterval,
  NotifyTriggerCalendar,
  NotifyTrigger,
  NotifySendParams,
  NotifySendResult,
  NotifyActionParams,
  NotifyRegisterCategoryParams,
  NotifyPendingInfo,
  NotifyPendingResult,
  NotifyDeliveredInfo,
  NotifyDeliveredResult,
  NotifyRemoveParams,
  NotifyOkResult,
  NotifyInteractionEvent,
} from "./types.js";
