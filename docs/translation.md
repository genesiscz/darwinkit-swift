# Translation

Translate text between languages using Apple's [Translation framework](https://developer.apple.com/documentation/translation). All processing runs on-device using CoreML models -- no API keys, no cloud, no data leaves the Mac.

## Requirements

| Feature | Minimum macOS |
|---------|---------------|
| Language availability checking (`languages`, `languageStatus`) | 14.4 (Sonoma) |
| Language model preparation (`preparePair`) | 14.4 (Sonoma) |
| Translation (`text`, `batch`) | 26.0 (Tahoe) via `TranslationSession` |

> **Note:** The Translation framework requires Apple Silicon or Intel Macs with macOS 14.4+. Translation models are downloaded on-demand by the OS and cached locally. First-time translation for a language pair may trigger a model download.

## Setup

```bash
bun add @genesiscz/darwinkit
```

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()
```

The SDK auto-downloads the `darwinkit` binary on first use if it is not found on PATH.

## Methods

### `translate.text` -- Translate a single string

Translates a single text string from one language to another.

```typescript
const result = await dk.translate.text({
  text: "Hello, how are you?",
  target: "es",
})

console.log(result.text)   // "Hola, ?como estas?"
console.log(result.source) // "en" (auto-detected)
console.log(result.target) // "es"
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | `string` | Yes | The text to translate |
| `source` | `string` | No | Source language locale code (e.g. `"en"`, `"fr"`). Omit to auto-detect. |
| `target` | `string` | Yes | Target language locale code |

#### Return type: `TranslateTextResult`

| Field | Type | Description |
|-------|------|-------------|
| `text` | `string` | The translated text |
| `source` | `string` | Source language that was used (useful when auto-detected) |
| `target` | `string` | Target language that was used |

#### Options

All methods accept an optional second argument with a `timeout` (in milliseconds):

```typescript
const result = await dk.translate.text(
  { text: "Hello", target: "ja" },
  { timeout: 60_000 }, // 60 seconds (useful for first-time model downloads)
)
```

---

### `translate.batch` -- Translate multiple strings

Translates an array of strings in a single call. All strings share the same source/target language pair.

```typescript
const result = await dk.translate.batch({
  texts: [
    "Good morning",
    "Thank you",
    "See you tomorrow",
  ],
  target: "fr",
})

for (const t of result.translations) {
  console.log(`${t.source}: ${t.text}`)
}
// en: Bonjour
// en: Merci
// en: A demain
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `texts` | `string[]` | Yes | Array of texts to translate |
| `source` | `string` | No | Source language locale code. Omit to auto-detect. |
| `target` | `string` | Yes | Target language locale code |

#### Return type: `TranslateBatchResult`

| Field | Type | Description |
|-------|------|-------------|
| `translations` | `TranslateTextResult[]` | Array of results, one per input text (same order) |

---

### `translate.languages` -- List supported languages

Returns all languages supported by the Translation framework on this system.

```typescript
const { languages } = await dk.translate.languages()

for (const lang of languages) {
  console.log(`${lang.locale} - ${lang.name}`)
}
// en - English
// es - Spanish
// fr - French
// de - German
// ja - Japanese
// ...
```

#### Parameters

None.

#### Return type: `TranslateLanguagesResult`

| Field | Type | Description |
|-------|------|-------------|
| `languages` | `TranslateLanguageInfo[]` | Array of supported languages |

Each `TranslateLanguageInfo` contains:

| Field | Type | Description |
|-------|------|-------------|
| `locale` | `string` | Language locale code (e.g. `"en"`, `"zh-Hans"`) |
| `name` | `string` | Human-readable language name |

---

### `translate.languageStatus` -- Check language pair availability

Checks whether a specific source-target language pair is ready for translation.

```typescript
const status = await dk.translate.languageStatus({
  source: "en",
  target: "ja",
})

console.log(status.status) // "installed" | "supported" | "unsupported"
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source` | `string` | Yes | Source language locale code |
| `target` | `string` | Yes | Target language locale code |

#### Return type: `TranslateLanguageStatusResult`

| Field | Type | Description |
|-------|------|-------------|
| `status` | `TranslateLanguageStatus` | One of `"installed"`, `"supported"`, or `"unsupported"` |
| `source` | `string` | Source language that was checked |
| `target` | `string` | Target language that was checked |

**Status values:**

| Status | Meaning |
|--------|---------|
| `"installed"` | Model is downloaded and ready -- translation will be instant |
| `"supported"` | Pair is supported but model needs to be downloaded first |
| `"unsupported"` | This language pair is not available |

---

### `translate.preparePair` -- Download a language model

Triggers the download of a translation model for a language pair. Call this before translating to avoid delays on first use.

```typescript
const result = await dk.translate.preparePair(
  { source: "en", target: "ko" },
  { timeout: 120_000 }, // model downloads can take a while
)

console.log(result.ok) // true
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source` | `string` | Yes | Source language locale code |
| `target` | `string` | Yes | Target language locale code |

#### Return type: `TranslatePrepareResult`

| Field | Type | Description |
|-------|------|-------------|
| `ok` | `true` | Indicates the model is now ready |
| `source` | `string` | Source language that was prepared |
| `target` | `string` | Target language that was prepared |

---

## Auto-detecting the source language

Omit the `source` parameter to let Apple's framework detect the language automatically:

```typescript
// Auto-detect source language
const result = await dk.translate.text({
  text: "Bonjour, comment allez-vous?",
  target: "en",
})

console.log(result.text)   // "Hello, how are you?"
console.log(result.source) // "fr" (auto-detected)
```

Auto-detection works for both `text` and `batch` calls. When using `batch`, all texts should be in the same source language for best results.

```typescript
// Mixed-language batch with auto-detect
const result = await dk.translate.batch({
  texts: [
    "Guten Morgen",      // German
    "Gute Nacht",        // German
    "Auf Wiedersehen",   // German
  ],
  target: "en",
})
// result.translations[0].source -> "de"
```

---

## Practical examples

### Translating emails

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function translateEmail(
  subject: string,
  body: string,
  targetLang: string,
) {
  const result = await dk.translate.batch({
    texts: [subject, body],
    target: targetLang,
  })

  return {
    subject: result.translations[0].text,
    body: result.translations[1].text,
    detectedLanguage: result.translations[0].source,
  }
}

const email = await translateEmail(
  "Meeting Tomorrow",
  "Hi team, let's meet at 3pm to discuss the Q4 roadmap. Please bring your updates.",
  "ja",
)

console.log(`Subject: ${email.subject}`)
console.log(`Body: ${email.body}`)
console.log(`Original language: ${email.detectedLanguage}`)

dk.close()
```

### Real-time chat translation

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

interface ChatMessage {
  user: string
  text: string
  timestamp: number
}

async function translateMessages(
  messages: ChatMessage[],
  targetLang: string,
): Promise<Array<ChatMessage & { translated: string }>> {
  const result = await dk.translate.batch({
    texts: messages.map((m) => m.text),
    target: targetLang,
  })

  return messages.map((msg, i) => ({
    ...msg,
    translated: result.translations[i].text,
  }))
}

const chat: ChatMessage[] = [
  { user: "Alice", text: "Hola, como va el proyecto?", timestamp: Date.now() },
  { user: "Bob", text: "Bien, casi terminamos la primera fase.", timestamp: Date.now() },
  { user: "Alice", text: "Excelente! Cuando podemos hacer la demo?", timestamp: Date.now() },
]

const translated = await translateMessages(chat, "en")

for (const msg of translated) {
  console.log(`[${msg.user}] ${msg.translated}`)
}
// [Alice] Hi, how's the project going?
// [Bob] Good, we're almost done with the first phase.
// [Alice] Excellent! When can we do the demo?

dk.close()
```

### Batch document processing

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

interface Document {
  id: string
  title: string
  content: string
}

async function translateDocuments(
  docs: Document[],
  targetLang: string,
): Promise<Document[]> {
  // Flatten all text fields into a single batch
  const allTexts = docs.flatMap((d) => [d.title, d.content])

  const result = await dk.translate.batch({
    texts: allTexts,
    target: targetLang,
  })

  // Re-assemble: every 2 translations map back to one document
  return docs.map((doc, i) => ({
    id: doc.id,
    title: result.translations[i * 2].text,
    content: result.translations[i * 2 + 1].text,
  }))
}

const docs: Document[] = [
  { id: "1", title: "Getting Started", content: "Welcome to our platform. This guide will help you set up your account." },
  { id: "2", title: "API Reference", content: "All endpoints accept JSON and return JSON. Authentication is via Bearer tokens." },
]

const translated = await translateDocuments(docs, "de")

for (const doc of translated) {
  console.log(`[${doc.id}] ${doc.title}`)
  console.log(`    ${doc.content}\n`)
}

dk.close()
```

### Checking and downloading language packs

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// List all available languages
const { languages } = await dk.translate.languages()
console.log(`${languages.length} languages available:`)
for (const lang of languages) {
  console.log(`  ${lang.locale.padEnd(8)} ${lang.name}`)
}

// Check if a language pair is ready
const pairs = [
  { source: "en", target: "es" },
  { source: "en", target: "ja" },
  { source: "en", target: "zh-Hans" },
  { source: "en", target: "ko" },
]

for (const pair of pairs) {
  const status = await dk.translate.languageStatus(pair)

  switch (status.status) {
    case "installed":
      console.log(`${pair.source} -> ${pair.target}: ready`)
      break
    case "supported":
      console.log(`${pair.source} -> ${pair.target}: needs download`)
      break
    case "unsupported":
      console.log(`${pair.source} -> ${pair.target}: not available`)
      break
  }
}

// Pre-download models for language pairs you know you will need
async function ensureLanguagePairs(
  pairs: Array<{ source: string; target: string }>,
) {
  for (const pair of pairs) {
    const { status } = await dk.translate.languageStatus(pair)

    if (status === "unsupported") {
      console.warn(`Skipping unsupported pair: ${pair.source} -> ${pair.target}`)
      continue
    }

    if (status === "supported") {
      console.log(`Downloading model for ${pair.source} -> ${pair.target}...`)
      await dk.translate.preparePair(pair, { timeout: 120_000 })
      console.log(`  Done.`)
    }
  }
}

await ensureLanguagePairs([
  { source: "en", target: "ja" },
  { source: "en", target: "de" },
  { source: "en", target: "fr" },
])

dk.close()
```

### Using `.prepare()` with the batch API

Every translate method has a `.prepare()` variant that creates a deferred call for use with `dk.batch()`. This lets you run multiple unrelated translate calls in parallel:

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// Prepare calls without executing them
const greetingToSpanish = dk.translate.text.prepare({
  text: "Good morning",
  target: "es",
})

const greetingToJapanese = dk.translate.text.prepare({
  text: "Good morning",
  target: "ja",
})

const statusCheck = dk.translate.languageStatus.prepare({
  source: "en",
  target: "ko",
})

// Execute all three in parallel
const [spanish, japanese, koStatus] = await dk.batch(
  greetingToSpanish,
  greetingToJapanese,
  statusCheck,
)

console.log(spanish.text)  // "Buenos dias"
console.log(japanese.text) // "おはようございます"
console.log(koStatus.status) // "installed"

dk.close()
```

---

## Error handling

Translation calls can fail for several reasons. The SDK throws `DarwinKitError` with specific error codes:

```typescript
import { DarwinKit, DarwinKitError, ErrorCodes } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

try {
  const result = await dk.translate.text({
    text: "Hello",
    target: "es",
  })
  console.log(result.text)
} catch (error) {
  if (error instanceof DarwinKitError) {
    if (error.isOSVersionTooOld) {
      // macOS version does not support TranslationSession
      console.error("Translation requires macOS 26+. Please update your OS.")
    } else if (error.isFrameworkUnavailable) {
      // Translation framework not available on this system
      console.error("Translation framework is not available.")
    } else if (error.code === ErrorCodes.INVALID_PARAMS) {
      // Bad parameters (e.g. unsupported language code)
      console.error(`Invalid parameters: ${error.message}`)
    } else {
      console.error(`Translation failed (code ${error.code}): ${error.message}`)
    }
  } else {
    throw error
  }
}

dk.close()
```

### Error codes relevant to translation

| Code | Constant | Meaning |
|------|----------|---------|
| `-32003` | `OS_VERSION_TOO_OLD` | macOS version too old for the requested method |
| `-32001` | `FRAMEWORK_UNAVAILABLE` | Translation framework not available |
| `-32602` | `INVALID_PARAMS` | Invalid parameters (bad language code, missing required field) |
| `-32603` | `INTERNAL_ERROR` | Internal translation error or request timeout |

### Handling timeouts

Translation can be slow on the first call for a language pair (model download). Increase the timeout for those cases:

```typescript
try {
  const result = await dk.translate.text(
    { text: "Hello", target: "zh-Hans" },
    { timeout: 120_000 }, // 2 minutes for potential model download
  )
} catch (error) {
  if (error instanceof DarwinKitError && error.message.includes("timed out")) {
    console.error("Translation timed out. The language model may still be downloading.")
    console.error("Try calling preparePair() first, then retry.")
  }
}
```

---

## Supported languages

The exact list depends on the macOS version and installed language packs. Call `dk.translate.languages()` to get the current list on your system. Common languages include:

| Locale | Language |
|--------|----------|
| `ar` | Arabic |
| `de` | German |
| `en` | English |
| `es` | Spanish |
| `fr` | French |
| `hi` | Hindi |
| `id` | Indonesian |
| `it` | Italian |
| `ja` | Japanese |
| `ko` | Korean |
| `nl` | Dutch |
| `pl` | Polish |
| `pt` | Portuguese |
| `ru` | Russian |
| `th` | Thai |
| `tr` | Turkish |
| `uk` | Ukrainian |
| `vi` | Vietnamese |
| `zh-Hans` | Chinese (Simplified) |
| `zh-Hant` | Chinese (Traditional) |

> **Tip:** Not every pair of languages can translate directly. Some pairs may route through English as an intermediary. Use `languageStatus()` to verify a specific pair before translating.

---

## TypeScript types

All types are exported from the package for use in your own code:

```typescript
import type {
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
} from "@genesiscz/darwinkit"
```
