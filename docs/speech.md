# Speech Namespace

The `speech` namespace provides on-device speech recognition powered by Apple's [Speech framework](https://developer.apple.com/documentation/speech) (`SFSpeechRecognizer`). It transcribes audio files into text with word-level timestamps, manages downloadable language models, and reports device capabilities -- all running locally on your Mac with no cloud API keys required.

> **macOS requirement:** Speech recognition requires **macOS 10.15** (Catalina) or later. On-device transcription (no network) requires **macOS 13** (Ventura) or later. DarwinKit will return an `OS_VERSION_TOO_OLD` error on older systems.

## Installation

```bash
bun add @genesiscz/darwinkit
```

## Quick start

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// Transcribe a voice memo
const result = await dk.speech.transcribe({
  path: "/Users/me/Documents/voice-memo.m4a",
})

console.log(result.text)
// "Hey, remind me to pick up groceries on the way home."

console.log(`Duration: ${result.duration.toFixed(1)}s`)
console.log(`Language: ${result.language}`)

for (const seg of result.segments) {
  console.log(`[${seg.start_time.toFixed(2)}s - ${seg.end_time.toFixed(2)}s] ${seg.text}`)
}

dk.close()
```

---

## Methods

### `speech.transcribe(params, options?)`

Transcribes an audio file to text using on-device speech recognition.

Supported audio formats include `.m4a`, `.wav`, `.mp3`, `.caf`, `.aiff`, and any format supported by AVFoundation.

```ts
const result = await dk.speech.transcribe({
  path: "/Users/me/Recordings/meeting-2024-03-15.m4a",
  language: "en-US",
  timestamps: true,
})
```

#### Parameters

| Parameter    | Type      | Default   | Description                                                        |
| ------------ | --------- | --------- | ------------------------------------------------------------------ |
| `path`       | `string`  | required  | Absolute path to the audio file to transcribe.                     |
| `language`   | `string`  | `"en-US"` | BCP 47 locale identifier for the recognition language.             |
| `timestamps` | `boolean` | `true`    | Whether to include word-level timestamp segments in the result.    |

#### Return type: `SpeechTranscribeResult`

| Field      | Type                            | Description                                        |
| ---------- | ------------------------------- | -------------------------------------------------- |
| `text`     | `string`                        | The full transcription text.                       |
| `segments` | `SpeechTranscriptionSegment[]`  | Word/phrase-level segments with timing information. |
| `language` | `string`                        | The locale used for recognition (e.g. `"en-US"`).  |
| `duration` | `number`                        | Duration of the audio in seconds.                  |

Each segment has the following shape:

| Field        | Type      | Description                                            |
| ------------ | --------- | ------------------------------------------------------ |
| `text`       | `string`  | The transcribed text for this segment.                 |
| `start_time` | `number`  | Start time of the segment in seconds from file start.  |
| `end_time`   | `number`  | End time of the segment in seconds from file start.    |
| `is_final`   | `boolean` | Whether this segment has been finalized by the engine. |

#### Custom timeout

Transcription of long audio files can take significant time. Override the default 30-second timeout:

```ts
const result = await dk.speech.transcribe(
  { path: "/Users/me/Recordings/hour-long-lecture.wav" },
  { timeout: 300_000 }, // 5 minutes
)
```

---

### `speech.languages(options?)`

Returns all languages supported by the speech recognition engine on this device.

```ts
const { languages } = await dk.speech.languages()

for (const lang of languages) {
  const status = lang.installed ? "installed" : "not installed"
  console.log(`${lang.locale} (${status})`)
}
// en-US (installed)
// de-DE (not installed)
// ja-JP (installed)
// ...
```

#### Parameters

None (only an optional `{ timeout?: number }` options object).

#### Return type: `SpeechLanguagesResult`

| Field       | Type                  | Description                       |
| ----------- | --------------------- | --------------------------------- |
| `languages` | `SpeechLanguageInfo[]` | Array of supported languages.    |

Each `SpeechLanguageInfo`:

| Field       | Type      | Description                                           |
| ----------- | --------- | ----------------------------------------------------- |
| `locale`    | `string`  | BCP 47 locale identifier (e.g. `"en-US"`, `"fr-FR"`). |
| `installed` | `boolean` | Whether the model is downloaded locally.              |

---

### `speech.installedLanguages(options?)`

Returns only the languages whose models are currently downloaded on this device. Useful to check what is ready for offline transcription.

```ts
const { languages } = await dk.speech.installedLanguages()

console.log("Ready for offline use:")
for (const lang of languages) {
  console.log(`  ${lang.locale}`)
}
```

#### Parameters

None (only an optional `{ timeout?: number }` options object).

#### Return type: `SpeechLanguagesResult`

Same shape as [`speech.languages()`](#speechlanguagesoptions).

---

### `speech.installLanguage(params, options?)`

Downloads a speech recognition model for the specified locale. The model must be supported (check with `speech.languages()` first). This is an asynchronous operation that downloads model data from Apple.

```ts
await dk.speech.installLanguage({ locale: "de-DE" })
console.log("German language model installed")
```

#### Parameters

| Parameter | Type     | Description                                         |
| --------- | -------- | --------------------------------------------------- |
| `locale`  | `string` | BCP 47 locale identifier of the language to install. |

#### Return type: `SpeechOkResult`

| Field | Type   | Description                |
| ----- | ------ | -------------------------- |
| `ok`  | `true` | Confirms successful install. |

---

### `speech.uninstallLanguage(params, options?)`

Removes a previously downloaded speech recognition model to free disk space.

```ts
await dk.speech.uninstallLanguage({ locale: "de-DE" })
console.log("German language model removed")
```

#### Parameters

| Parameter | Type     | Description                                           |
| --------- | -------- | ----------------------------------------------------- |
| `locale`  | `string` | BCP 47 locale identifier of the language to uninstall. |

#### Return type: `SpeechOkResult`

| Field | Type   | Description                  |
| ----- | ------ | ---------------------------- |
| `ok`  | `true` | Confirms successful removal. |

---

### `speech.capabilities(options?)`

Checks whether speech recognition is available on this device and reports the reason if it is not.

```ts
const caps = await dk.speech.capabilities()

if (caps.available) {
  console.log("Speech recognition is available")
} else {
  console.log(`Speech recognition unavailable: ${caps.reason}`)
}
```

#### Parameters

None (only an optional `{ timeout?: number }` options object).

#### Return type: `SpeechCapabilitiesResult`

| Field       | Type      | Description                                                                 |
| ----------- | --------- | --------------------------------------------------------------------------- |
| `available` | `boolean` | `true` if speech recognition can be used.                                   |
| `reason`    | `string?` | Human-readable explanation when `available` is `false` (e.g. OS too old).   |

---

## Error handling

All speech methods throw `DarwinKitError` on failure. The error includes a numeric `code` and convenience getters for common cases:

```ts
import { DarwinKit, DarwinKitError, ErrorCodes } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

try {
  const result = await dk.speech.transcribe({
    path: "/nonexistent/audio.m4a",
  })
} catch (err) {
  if (err instanceof DarwinKitError) {
    // Structured error from the native side
    console.error(`Error ${err.code}: ${err.message}`)

    if (err.isOSVersionTooOld) {
      console.error("Please update to macOS 10.15 or later")
    }
    if (err.isFrameworkUnavailable) {
      console.error("Speech framework is not available on this device")
    }
    if (err.isPermissionDenied) {
      console.error("Speech recognition permission was denied")
    }
  } else {
    // Network/transport error
    throw err
  }
}

dk.close()
```

### Error codes reference

| Code     | Constant                | Getter                     | Meaning                                |
| -------- | ----------------------- | -------------------------- | -------------------------------------- |
| `-32700` | `PARSE_ERROR`           | --                         | Malformed JSON-RPC request.            |
| `-32600` | `INVALID_REQUEST`       | --                         | Invalid request structure.             |
| `-32601` | `METHOD_NOT_FOUND`      | --                         | Method does not exist.                 |
| `-32602` | `INVALID_PARAMS`        | --                         | Invalid or missing parameters.         |
| `-32603` | `INTERNAL_ERROR`        | --                         | Internal error (also used for timeouts). |
| `-32001` | `FRAMEWORK_UNAVAILABLE` | `err.isFrameworkUnavailable` | Apple framework not available.         |
| `-32002` | `PERMISSION_DENIED`     | `err.isPermissionDenied`   | User denied permission.               |
| `-32003` | `OS_VERSION_TOO_OLD`    | `err.isOSVersionTooOld`    | macOS version too old.                 |
| `-32004` | `OPERATION_CANCELLED`   | `err.isCancelled`          | Operation was cancelled.               |

---

## Common patterns

### Check capabilities before transcribing

Always verify that the device supports speech recognition before attempting a transcription, especially in distributed or CI environments:

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

const caps = await dk.speech.capabilities()
if (!caps.available) {
  console.error(`Cannot transcribe: ${caps.reason}`)
  process.exit(1)
}

const result = await dk.speech.transcribe({
  path: "/Users/me/meeting.m4a",
})
console.log(result.text)

dk.close()
```

### Install a language before transcribing

For non-English transcription, ensure the language model is installed first:

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// Check if Japanese is already installed
const { languages } = await dk.speech.installedLanguages()
const hasJapanese = languages.some((l) => l.locale === "ja-JP")

if (!hasJapanese) {
  console.log("Downloading Japanese language model...")
  await dk.speech.installLanguage({ locale: "ja-JP" })
  console.log("Done")
}

// Transcribe a Japanese audio file
const result = await dk.speech.transcribe({
  path: "/Users/me/japanese-podcast.m4a",
  language: "ja-JP",
})

console.log(result.text)
dk.close()
```

### Transcribing multiple files with the batch API

Use the `prepare` / `batch` pattern to transcribe several files concurrently. Each method on the `Speech` namespace exposes a `.prepare()` variant that returns a `PreparedCall` -- pass them all to `dk.batch()`:

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

const files = [
  "/Users/me/Recordings/standup-monday.m4a",
  "/Users/me/Recordings/standup-tuesday.m4a",
  "/Users/me/Recordings/standup-wednesday.m4a",
]

// Prepare calls (no network yet)
const prepared = [
  dk.speech.transcribe.prepare({ path: files[0], language: "en-US" }),
  dk.speech.transcribe.prepare({ path: files[1], language: "en-US" }),
  dk.speech.transcribe.prepare({ path: files[2], language: "en-US" }),
] as const

// Execute all in parallel
const results = await dk.batch(...prepared)

for (let i = 0; i < files.length; i++) {
  console.log(`\n--- ${files[i]} ---`)
  console.log(`Duration: ${results[i].duration.toFixed(1)}s`)
  console.log(results[i].text)
}

dk.close()
```

### Generating subtitles / SRT from segments

Use timestamp segments to build subtitle files from recordings:

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

const result = await dk.speech.transcribe({
  path: "/Users/me/Videos/presentation.m4a",
  timestamps: true,
})

// Build SRT format
const srt = result.segments
  .map((seg, i) => {
    const start = formatSrtTime(seg.start_time)
    const end = formatSrtTime(seg.end_time)
    return `${i + 1}\n${start} --> ${end}\n${seg.text}\n`
  })
  .join("\n")

await Bun.write("/Users/me/Videos/presentation.srt", srt)
console.log(`Wrote ${result.segments.length} subtitle entries`)

dk.close()

function formatSrtTime(seconds: number): string {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  const ms = Math.round((seconds % 1) * 1000)
  return `${pad(h)}:${pad(m)}:${pad(s)},${pad(ms, 3)}`
}

function pad(n: number, width = 2): string {
  return String(n).padStart(width, "0")
}
```

### Processing a directory of voice memos

Scan a folder and transcribe every audio file, collecting results into a summary:

```ts
import { DarwinKit } from "@genesiscz/darwinkit"
import { readdir } from "node:fs/promises"
import { join, extname } from "node:path"

const dk = new DarwinKit()

const AUDIO_EXTS = new Set([".m4a", ".wav", ".mp3", ".caf", ".aiff"])
const dir = "/Users/me/Voice Memos"

const entries = await readdir(dir)
const audioFiles = entries.filter((f) => AUDIO_EXTS.has(extname(f).toLowerCase()))

console.log(`Found ${audioFiles.length} audio files\n`)

for (const file of audioFiles) {
  const path = join(dir, file)
  try {
    const result = await dk.speech.transcribe(
      { path },
      { timeout: 120_000 }, // 2 min per file
    )
    console.log(`${file} (${result.duration.toFixed(1)}s):`)
    console.log(`  ${result.text.slice(0, 120)}...`)
    console.log()
  } catch (err) {
    console.error(`Failed to transcribe ${file}: ${err}`)
  }
}

dk.close()
```

### Multilingual transcription with language detection

When you do not know the language of an audio file, transcribe with the default and inspect the returned `language` field, or combine with the NLP namespace's language detection:

```ts
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// First pass: transcribe with default language
const firstPass = await dk.speech.transcribe({
  path: "/Users/me/unknown-language-clip.m4a",
})

// Detect the dominant language of the transcript
const detected = await dk.nlp.language({ text: firstPass.text })
console.log(`Detected language: ${detected.language} (${(detected.confidence * 100).toFixed(0)}%)`)

// If the detected language differs, re-transcribe with the correct model
if (detected.language !== "en" && detected.confidence > 0.8) {
  const locale = detected.language // e.g. "fr", "de", "ja"

  // Ensure the model is installed
  const { languages } = await dk.speech.installedLanguages()
  const match = languages.find((l) => l.locale.startsWith(locale))

  if (!match) {
    // Find and install the right locale
    const all = await dk.speech.languages()
    const target = all.languages.find((l) => l.locale.startsWith(locale))
    if (target) {
      await dk.speech.installLanguage({ locale: target.locale })
    }
  }

  const targetLocale = match?.locale ?? `${locale}-${locale.toUpperCase()}`
  const refined = await dk.speech.transcribe({
    path: "/Users/me/unknown-language-clip.m4a",
    language: targetLocale,
  })
  console.log(`Refined transcription: ${refined.text}`)
}

dk.close()
```

---

## Type exports

All types are re-exported from the package entry point for use in your own code:

```ts
import type {
  SpeechTranscribeParams,
  SpeechTranscribeResult,
  SpeechTranscriptionSegment,
  SpeechLanguageInfo,
  SpeechLanguagesResult,
  SpeechInstallLanguageParams,
  SpeechUninstallLanguageParams,
  SpeechOkResult,
  SpeechCapabilitiesResult,
} from "@genesiscz/darwinkit"
```