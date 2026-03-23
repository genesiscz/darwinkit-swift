# Sound Namespace

The `sound` namespace provides access to Apple's **SoundAnalysis** framework, enabling on-device classification of audio files into **300+ sound categories**. It can identify speech, music, laughter, applause, environmental sounds, animal vocalizations, vehicle noises, and much more -- all processed locally with zero network requests.

## Requirements

| Requirement | Value |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Framework | SoundAnalysis (ships with macOS) |
| Audio formats | WAV, MP3, M4A, CAF, AIFF, and other formats supported by AVFoundation |

## Setup

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

// All sound methods are available on dk.sound
```

## Methods

### `sound.available` -- Check availability

Checks whether SoundAnalysis is available on the current system.

```ts
const { available } = await dk.sound.available()

if (!available) {
  console.error("SoundAnalysis requires macOS 14+")
  process.exit(1)
}
```

**Parameters:** None

**Returns: `SoundAvailableResult`**

| Field | Type | Description |
|---|---|---|
| `available` | `boolean` | `true` if SoundAnalysis is available on this system |

---

### `sound.categories` -- List all sound categories

Returns every sound category the built-in classifier can recognize, sorted alphabetically. The Version 1 classifier includes over 300 categories.

```ts
const { categories } = await dk.sound.categories()

console.log(`${categories.length} categories available`)
// => "300+ categories available (exact count varies by macOS version)"

// Check if a specific category exists
if (categories.includes("speech")) {
  console.log("Speech detection is supported")
}
```

**Parameters:** None

**Returns: `SoundCategoriesResult`**

| Field | Type | Description |
|---|---|---|
| `categories` | `string[]` | Alphabetically sorted list of all recognizable sound identifiers |

---

### `sound.classify` -- Classify an entire audio file

Analyzes an audio file and returns the top N most confident sound classifications. The classifier processes the full file and returns the classification window with the highest confidence.

```ts
const result = await dk.sound.classify({
  path: "/path/to/audio.wav",
  top_n: 5,
})

for (const c of result.classifications) {
  console.log(`${c.identifier}: ${(c.confidence * 100).toFixed(1)}%`)
}
// => "speech: 92.3%"
// => "music: 4.1%"
// => "silence: 2.0%"
// => "noise: 1.1%"
// => "breathing: 0.5%"
```

**Parameters: `SoundClassifyParams`**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `path` | `string` | Yes | -- | Absolute path to the audio file |
| `top_n` | `number` | No | `5` | Number of top classifications to return |

**Returns: `SoundClassifyResult`**

| Field | Type | Description |
|---|---|---|
| `classifications` | `SoundClassification[]` | Array of classifications sorted by confidence (descending) |
| `time_range` | `SoundTimeRange \| undefined` | Not present for whole-file classification |

**`SoundClassification` object:**

| Field | Type | Description |
|---|---|---|
| `identifier` | `string` | Sound category name (e.g., `"speech"`, `"music"`, `"laughter"`) |
| `confidence` | `number` | Confidence score between `0.0` and `1.0` |

---

### `sound.classifyAt` -- Classify a time range

Analyzes a specific time range within an audio file. This is useful for scanning through long recordings, detecting transitions, or isolating segments of interest.

```ts
const result = await dk.sound.classifyAt({
  path: "/path/to/podcast.mp3",
  start: 30.0,    // 30 seconds in
  duration: 10.0, // analyze 10 seconds
  top_n: 3,
})

console.log(`Time range: ${result.time_range.start}s - ${result.time_range.start + result.time_range.duration}s`)
for (const c of result.classifications) {
  console.log(`  ${c.identifier}: ${(c.confidence * 100).toFixed(1)}%`)
}
// => "Time range: 30s - 40s"
// => "  music: 87.5%"
// => "  singing: 8.2%"
// => "  speech: 3.1%"
```

**Parameters: `SoundClassifyAtParams`**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `path` | `string` | Yes | -- | Absolute path to the audio file |
| `start` | `number` | Yes | -- | Start time in seconds (must be >= 0) |
| `duration` | `number` | Yes | -- | Duration in seconds (must be > 0) |
| `top_n` | `number` | No | `5` | Number of top classifications to return |

**Returns: `SoundClassifyAtResult`**

| Field | Type | Description |
|---|---|---|
| `classifications` | `SoundClassification[]` | Array of classifications sorted by confidence (descending) |
| `time_range` | `SoundTimeRange` | The analyzed time range (always present for `classifyAt`) |

**`SoundTimeRange` object:**

| Field | Type | Description |
|---|---|---|
| `start` | `number` | Start time in seconds |
| `duration` | `number` | Duration in seconds |

---

## Error Handling

All sound methods throw `DarwinKitError` on failure. Common error scenarios:

```ts
import { DarwinKit, DarwinKitError, ErrorCodes } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

try {
  const result = await dk.sound.classify({
    path: "/path/to/audio.wav",
  })
} catch (error) {
  if (error instanceof DarwinKitError) {
    // Framework not available (macOS < 14)
    if (error.isFrameworkUnavailable) {
      console.error("SoundAnalysis is not available on this system")
    }

    // OS too old
    if (error.isOSVersionTooOld) {
      console.error("macOS 14+ is required for sound classification")
    }

    // Invalid parameters (e.g., file not found, negative start time)
    if (error.code === ErrorCodes.INVALID_PARAMS) {
      console.error("Invalid parameters:", error.message)
    }

    // Internal classification failure
    if (error.code === ErrorCodes.INTERNAL_ERROR) {
      console.error("Classification failed:", error.message)
    }
  }
}
```

### Common error conditions

| Error | Code | Cause |
|---|---|---|
| File not found | `-32602` | The audio file path does not exist |
| Invalid `top_n` | `-32602` | `top_n` is less than 1 |
| Invalid `start` | `-32602` | `start` is negative |
| Invalid `duration` | `-32602` | `duration` is zero or negative |
| Classification failed | `-32603` | SoundAnalysis encountered an internal error processing the file |
| Analysis timed out | `-32603` | Sound analysis did not complete within the 30-second internal timeout |

---

## Batch API

Use `prepare()` on any method to create prepared calls, then execute them concurrently with `dk.batch()`:

```ts
const result = await dk.batch(
  dk.sound.classify.prepare({ path: "/audio/clip1.wav", top_n: 3 }),
  dk.sound.classify.prepare({ path: "/audio/clip2.wav", top_n: 3 }),
  dk.sound.classifyAt.prepare({ path: "/audio/long.mp3", start: 0, duration: 30 }),
)

const [clip1, clip2, segment] = result
// Each element is a fully typed SoundClassifyResult
```

---

## Practical Examples

### Audio content moderation

Scan uploaded audio files to detect potentially inappropriate content:

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

async function moderateAudio(filePath: string): Promise<{
  safe: boolean
  flags: string[]
}> {
  const { classifications } = await dk.sound.classify({
    path: filePath,
    top_n: 15,
  })

  const flaggedCategories = [
    "gunshot", "explosion", "screaming", "siren",
    "fire_alarm", "glass_breaking",
  ]

  const flags: string[] = []
  for (const c of classifications) {
    if (flaggedCategories.includes(c.identifier) && c.confidence > 0.5) {
      flags.push(`${c.identifier} (${(c.confidence * 100).toFixed(0)}%)`)
    }
  }

  return { safe: flags.length === 0, flags }
}

const report = await moderateAudio("/uploads/user-audio.wav")
if (!report.safe) {
  console.warn("Flagged content:", report.flags.join(", "))
}

dk.close()
```

### Podcast chapter detection

Scan through a podcast to detect transitions between speech, music, and silence for automatic chapter markers:

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

interface Chapter {
  startTime: number
  endTime: number
  type: string
  confidence: number
}

async function detectChapters(
  filePath: string,
  totalDuration: number,
  windowSize = 10,
  stepSize = 5,
): Promise<Chapter[]> {
  const chapters: Chapter[] = []
  let currentType = ""
  let chapterStart = 0
  let chapterConfidence = 0

  for (let t = 0; t < totalDuration; t += stepSize) {
    const duration = Math.min(windowSize, totalDuration - t)
    if (duration <= 0) break

    const { classifications } = await dk.sound.classifyAt({
      path: filePath,
      start: t,
      duration,
      top_n: 1,
    })

    const dominant = classifications[0]
    if (!dominant) continue

    // Simplify to broad categories
    const broadType = dominant.identifier === "speech"
      ? "speech"
      : dominant.identifier === "music" || dominant.identifier === "singing"
        ? "music"
        : dominant.identifier === "silence"
          ? "silence"
          : dominant.identifier

    if (broadType !== currentType) {
      if (currentType) {
        chapters.push({
          startTime: chapterStart,
          endTime: t,
          type: currentType,
          confidence: chapterConfidence,
        })
      }
      currentType = broadType
      chapterStart = t
      chapterConfidence = dominant.confidence
    }
  }

  // Close the final chapter
  if (currentType) {
    chapters.push({
      startTime: chapterStart,
      endTime: totalDuration,
      type: currentType,
      confidence: 0,
    })
  }

  return chapters
}

const chapters = await detectChapters("/podcasts/episode-42.mp3", 3600)
for (const ch of chapters) {
  const startMin = Math.floor(ch.startTime / 60)
  const startSec = Math.floor(ch.startTime % 60)
  console.log(
    `[${String(startMin).padStart(2, "0")}:${String(startSec).padStart(2, "0")}] ${ch.type}`,
  )
}

dk.close()
```

### Environmental sound monitoring

Continuously process audio recordings to track environmental sound patterns:

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

interface SoundEvent {
  timestamp: number
  category: string
  confidence: number
}

const environmentalSounds = [
  "rain", "thunder", "wind", "water",
  "bird", "dog_bark", "cat_meow", "insect",
  "car", "truck", "motorcycle", "train", "airplane",
  "construction", "jackhammer",
  "door_knock", "doorbell", "alarm",
]

async function analyzeEnvironment(
  filePath: string,
  totalDuration: number,
  interval = 30,
): Promise<SoundEvent[]> {
  const events: SoundEvent[] = []

  for (let t = 0; t < totalDuration; t += interval) {
    const duration = Math.min(interval, totalDuration - t)
    if (duration <= 0) break

    const { classifications } = await dk.sound.classifyAt({
      path: filePath,
      start: t,
      duration,
      top_n: 10,
    })

    for (const c of classifications) {
      if (environmentalSounds.includes(c.identifier) && c.confidence > 0.3) {
        events.push({
          timestamp: t,
          category: c.identifier,
          confidence: c.confidence,
        })
      }
    }
  }

  return events
}

const events = await analyzeEnvironment("/recordings/backyard-1hr.wav", 3600)

// Group by category
const grouped = new Map<string, number>()
for (const e of events) {
  grouped.set(e.category, (grouped.get(e.category) ?? 0) + 1)
}

console.log("Sound summary:")
for (const [category, count] of [...grouped.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${category}: detected in ${count} segments`)
}

dk.close()
```

---

## Notable Sound Categories

The built-in Version 1 classifier recognizes 300+ categories. Here is a curated selection organized by theme:

### Human sounds

`speech`, `singing`, `shouting`, `whispering`, `laughter`, `crying`, `coughing`, `sneezing`, `breathing`, `snoring`, `clapping`, `whistling`, `yelling`, `humming`, `gargling`, `hiccup`, `burping`

### Music

`music`, `musical_instrument`, `guitar`, `electric_guitar`, `bass_guitar`, `piano`, `keyboard`, `drums`, `drum_kit`, `violin`, `cello`, `flute`, `trumpet`, `harmonica`, `organ`, `synthesizer`, `saxophone`, `clarinet`, `harp`, `banjo`, `ukulele`, `accordion`

### Animals

`dog_bark`, `cat_meow`, `cat_purr`, `bird`, `bird_chirp`, `crow`, `rooster`, `owl`, `duck`, `goose`, `frog`, `cricket`, `bee`, `horse`, `cow`, `pig`, `sheep`, `goat`, `chicken`, `whale`

### Environment and nature

`rain`, `thunder`, `wind`, `water`, `ocean`, `stream`, `waterfall`, `fire`, `fire_crackling`

### Vehicles and transport

`car`, `truck`, `motorcycle`, `bus`, `train`, `airplane`, `helicopter`, `boat`, `engine`, `car_horn`, `bicycle_bell`, `siren`

### Household sounds

`door_knock`, `doorbell`, `door_slam`, `telephone_ring`, `alarm_clock`, `microwave`, `blender`, `vacuum_cleaner`, `washing_machine`, `hair_dryer`, `typing`, `mouse_click`, `printer`

### Impact and mechanical

`explosion`, `gunshot`, `glass_breaking`, `hammering`, `sawing`, `drilling`, `jackhammer`, `construction`

### Other

`silence`, `noise`, `static`, `beep`, `click`, `buzz`, `squeak`, `creak`, `rustle`, `splash`, `pour`, `crunch`, `tear`, `rip`

> **Note:** The full list is accessible at runtime via `dk.sound.categories()`. The categories listed above are representative examples -- the actual classifier taxonomy is defined by Apple's SoundAnalysis Version 1 model and may vary between macOS versions.

---

## Timeouts

Sound classification of long audio files can take significant time. You can set a per-call timeout:

```ts
// 60-second timeout for a large file
const result = await dk.sound.classify(
  { path: "/recordings/long-meeting.wav", top_n: 10 },
  { timeout: 60_000 },
)
```

Or configure a default timeout for all calls:

```ts
const dk = new DarwinKit({ timeout: 60_000 })
```

---

## TypeScript Types

All types are exported from the `darwinkit` package:

```ts
import type {
  SoundClassification,
  SoundClassifyParams,
  SoundClassifyResult,
  SoundClassifyAtParams,
  SoundClassifyAtResult,
  SoundTimeRange,
  SoundCategoriesResult,
  SoundAvailableResult,
} from "darwinkit"
```
