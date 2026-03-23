# LLM Namespace -- Apple Foundation Models

The `llm` namespace provides access to Apple's on-device Foundation Models -- a ~3B parameter large language model that ships with Apple Intelligence on macOS 26+, iOS 26+, and iPadOS 26+. All inference runs entirely on-device using the Apple Neural Engine; no data leaves the user's machine.

## Requirements

- **macOS 26** (Tahoe) or later / iOS 26+ / iPadOS 26+
- **Apple Intelligence** must be enabled in System Settings
- Apple silicon (M1 or later) or A17 Pro+
- DarwinKit Swift helper binary (auto-resolved by the SDK)

## Quick Start

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

// Check availability first
const { available, reason } = await dk.llm.available()
if (!available) {
  console.error("Apple Intelligence not available:", reason)
  process.exit(1)
}

// Generate text
const result = await dk.llm.generate({
  prompt: "Explain quantum computing in two sentences.",
})
console.log(result.text)

dk.close()
```

---

## Availability Check

Before using any LLM method, verify that Foundation Models are available on the current device. The model may be unavailable if Apple Intelligence is disabled, the OS version is too old, or the hardware does not support it.

```ts
const status = await dk.llm.available()

if (status.available) {
  console.log("Foundation Models ready")
} else {
  console.log("Not available:", status.reason)
}
```

### Return Type

```ts
interface LLMAvailableResult {
  available: boolean
  reason?: string   // Present when available is false
}
```

---

## Text Generation

### `llm.generate` -- Single-shot generation

Generate a complete text response from a prompt. The call blocks until the full response is ready.

```ts
const result = await dk.llm.generate({
  prompt: "Write a haiku about Swift programming.",
})
console.log(result.text)
// Compiled with care
// Optionals unwrap like gifts
// Safe code, swiftly runs
```

#### Parameters

| Parameter              | Type     | Required | Default | Description                                    |
|------------------------|----------|----------|---------|------------------------------------------------|
| `prompt`               | `string` | Yes      | --      | The user prompt / instruction                  |
| `system_instructions`  | `string` | No       | --      | System-level instructions that guide behavior  |
| `temperature`          | `number` | No       | --      | Sampling temperature (higher = more creative)  |
| `max_tokens`           | `number` | No       | --      | Maximum number of tokens to generate           |

#### Return Type

```ts
interface LLMGenerateResult {
  text: string
}
```

#### Example: Summarizer

```ts
const article = await Bun.file("article.txt").text()

const result = await dk.llm.generate({
  prompt: `Summarize the following article in 3 bullet points:\n\n${article}`,
  system_instructions: "You are a concise technical writer. Output only bullet points.",
  temperature: 0.3,
  max_tokens: 200,
})

console.log(result.text)
```

---

### `llm.stream` -- Streaming Generation

Stream tokens as they are generated. The method returns a promise that resolves with the complete response once generation finishes. Use the `onChunk` listener to receive incremental tokens in real time.

```ts
// Register chunk listener BEFORE calling stream
const unsubscribe = dk.llm.onChunk((notification) => {
  process.stdout.write(notification.chunk)
})

const result = await dk.llm.stream({
  prompt: "Tell me a short story about a robot learning to paint.",
  temperature: 0.8,
})

unsubscribe()

// result.text contains the full completed response
console.log("\n\nFull text length:", result.text.length)
```

#### Parameters

| Parameter              | Type     | Required | Default | Description                                    |
|------------------------|----------|----------|---------|------------------------------------------------|
| `prompt`               | `string` | Yes      | --      | The user prompt / instruction                  |
| `system_instructions`  | `string` | No       | --      | System-level instructions that guide behavior  |
| `temperature`          | `number` | No       | --      | Sampling temperature (higher = more creative)  |
| `max_tokens`           | `number` | No       | --      | Maximum number of tokens to generate           |

#### Chunk Notification Shape

```ts
interface LLMChunkNotification {
  request_id: string   // Correlate chunks with their originating request
  chunk: string        // The incremental text fragment
}
```

#### `onChunk(handler)` Method

Registers a listener for streaming chunk notifications. Returns an unsubscribe function.

```ts
onChunk(handler: (notification: LLMChunkNotification) => void): () => void
```

You can also listen for chunks via the global event system:

```ts
dk.on("llmChunk", ({ request_id, chunk }) => {
  process.stdout.write(chunk)
})
```

#### Example: Streaming UI Updates

```ts
let accumulated = ""

const unsubscribe = dk.llm.onChunk(({ chunk }) => {
  accumulated += chunk
  // Update your UI with the partial response
  updateUI(accumulated)
})

await dk.llm.stream({
  prompt: userInput,
  system_instructions: "You are a helpful coding assistant.",
})

unsubscribe()
// Final UI update with complete text
updateUI(accumulated)
```

---

## Structured Output

### `llm.generateStructured` -- JSON Schema Output

Generate structured data that conforms to a JSON schema. The model output is parsed and validated against the provided schema, returning a typed JSON object.

```ts
const result = await dk.llm.generateStructured({
  prompt: "Extract the person's details: John Smith, age 34, software engineer at Apple",
  schema: {
    type: "object",
    properties: {
      name: { type: "string" },
      age: { type: "number" },
      occupation: { type: "string" },
      company: { type: "string" },
    },
    required: ["name", "age", "occupation", "company"],
  },
})

console.log(result.json)
// { name: "John Smith", age: 34, occupation: "software engineer", company: "Apple" }
```

#### Parameters

| Parameter              | Type                      | Required | Default | Description                                           |
|------------------------|---------------------------|----------|---------|-------------------------------------------------------|
| `prompt`               | `string`                  | Yes      | --      | The user prompt / instruction                         |
| `schema`               | `Record<string, unknown>` | Yes      | --      | JSON Schema that the output must conform to           |
| `system_instructions`  | `string`                  | No       | --      | System-level instructions that guide behavior         |
| `temperature`          | `number`                  | No       | --      | Sampling temperature                                  |
| `max_tokens`           | `number`                  | No       | --      | Maximum number of tokens to generate                  |

#### Return Type

```ts
interface LLMGenerateStructuredResult {
  json: Record<string, unknown>
}
```

#### Example: Structured Data Extraction

```ts
const emailText = `
  From: jane.doe@example.com
  Subject: Q3 Budget Review Meeting
  Date: March 28, 2026 2:00 PM

  Hi team, let's meet to discuss the Q3 budget allocations.
  Please bring your department reports. Conference Room B.
`

const result = await dk.llm.generateStructured({
  prompt: `Extract meeting details from this email:\n\n${emailText}`,
  schema: {
    type: "object",
    properties: {
      sender: { type: "string" },
      subject: { type: "string" },
      date: { type: "string", description: "ISO 8601 format" },
      location: { type: "string" },
      action_items: {
        type: "array",
        items: { type: "string" },
      },
    },
    required: ["sender", "subject", "date"],
  },
  temperature: 0.1,
})

console.log(result.json)
// {
//   sender: "jane.doe@example.com",
//   subject: "Q3 Budget Review Meeting",
//   date: "2026-03-28T14:00:00",
//   location: "Conference Room B",
//   action_items: ["Bring department reports"]
// }
```

#### Example: Classification

```ts
const result = await dk.llm.generateStructured({
  prompt: `Classify the sentiment and topic of this review: "The new MacBook Pro is incredibly fast but the price is hard to justify."`,
  schema: {
    type: "object",
    properties: {
      sentiment: { type: "string", enum: ["positive", "negative", "mixed", "neutral"] },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      topics: {
        type: "array",
        items: { type: "string" },
      },
      summary: { type: "string" },
    },
    required: ["sentiment", "confidence", "topics"],
  },
})

console.log(result.json.sentiment) // "mixed"
console.log(result.json.topics)    // ["performance", "pricing"]
```

---

## Multi-Turn Conversations

The session API enables multi-turn conversations where context is preserved across messages. You create a session, send messages to it, and close it when done.

### Session Lifecycle

1. **Create** a session with `sessionCreate`
2. **Send messages** with `sessionRespond` (returns the assistant reply)
3. **Close** the session with `sessionClose` when finished

```ts
import { randomUUID } from "crypto"

const sessionId = randomUUID()

// 1. Create session with optional system instructions
await dk.llm.sessionCreate({
  session_id: sessionId,
  instructions: "You are a helpful cooking assistant. Be concise.",
})

// 2. Multi-turn conversation
const r1 = await dk.llm.sessionRespond({
  session_id: sessionId,
  prompt: "What ingredients do I need for carbonara?",
})
console.log("Assistant:", r1.text)

const r2 = await dk.llm.sessionRespond({
  session_id: sessionId,
  prompt: "How long does it take to cook?",
})
console.log("Assistant:", r2.text)
// The model remembers the previous context about carbonara

const r3 = await dk.llm.sessionRespond({
  session_id: sessionId,
  prompt: "Can I substitute the guanciale with bacon?",
})
console.log("Assistant:", r3.text)

// 3. Clean up
await dk.llm.sessionClose({ session_id: sessionId })
```

### `llm.sessionCreate`

| Parameter       | Type     | Required | Default | Description                                     |
|-----------------|----------|----------|---------|-------------------------------------------------|
| `session_id`    | `string` | Yes      | --      | A unique identifier for this session (use UUID) |
| `instructions`  | `string` | No       | --      | System instructions for the session             |

Returns `{ ok: true }` on success.

### `llm.sessionRespond`

| Parameter    | Type     | Required | Default | Description                                  |
|--------------|----------|----------|---------|----------------------------------------------|
| `session_id` | `string` | Yes      | --      | The session to send the message to           |
| `prompt`     | `string` | Yes      | --      | The user message                             |
| `temperature`| `number` | No       | --      | Sampling temperature for this response       |
| `max_tokens` | `number` | No       | --      | Maximum tokens for this response             |

Returns `LLMGenerateResult` with the assistant's reply in `text`.

### `llm.sessionClose`

| Parameter    | Type     | Required | Default | Description                     |
|--------------|----------|----------|---------|---------------------------------|
| `session_id` | `string` | Yes      | --      | The session to close            |

Returns `{ ok: true }` on success.

#### Example: Interactive Chatbot

```ts
import { randomUUID } from "crypto"

const sessionId = randomUUID()

await dk.llm.sessionCreate({
  session_id: sessionId,
  instructions: `You are a macOS troubleshooting assistant. Ask clarifying questions
when needed. Keep answers under 3 sentences unless the user asks for detail.`,
})

// Simulate a conversation loop
const questions = [
  "My Mac is running slowly after the update.",
  "It's a MacBook Air M2 with 16GB RAM.",
  "Activity Monitor shows kernel_task using 400% CPU.",
]

for (const question of questions) {
  console.log(`User: ${question}`)
  const response = await dk.llm.sessionRespond({
    session_id: sessionId,
    prompt: question,
    temperature: 0.5,
  })
  console.log(`Assistant: ${response.text}\n`)
}

await dk.llm.sessionClose({ session_id: sessionId })
```

---

## Batch API

All LLM methods support the `prepare` pattern for batching multiple calls together using `dk.batch()`. This dispatches all requests concurrently and returns results in order.

```ts
const [summary, translation, keywords] = await dk.batch(
  dk.llm.generate.prepare({
    prompt: "Summarize: " + articleText,
    max_tokens: 100,
  }),
  dk.llm.generate.prepare({
    prompt: "Translate to French: " + articleText,
  }),
  dk.llm.generateStructured.prepare({
    prompt: "Extract 5 keywords from: " + articleText,
    schema: {
      type: "object",
      properties: {
        keywords: {
          type: "array",
          items: { type: "string" },
        },
      },
      required: ["keywords"],
    },
  }),
)

console.log(summary.text)
console.log(translation.text)
console.log(keywords.json)
```

Each method exposes a `.prepare()` function that creates a `PreparedCall` without executing it. Pass prepared calls to `dk.batch()` to run them concurrently with full type inference on the results.

---

## Temperature and Sampling

The `temperature` parameter controls the randomness of the model's output:

| Temperature | Behavior                                      | Use Case                          |
|-------------|-----------------------------------------------|-----------------------------------|
| `0.0`       | Deterministic, most likely token always chosen | Factual Q&A, data extraction      |
| `0.1 - 0.3` | Low randomness, focused output                | Summarization, classification     |
| `0.5 - 0.7` | Balanced creativity and coherence             | General conversation, chatbots    |
| `0.8 - 1.0` | High creativity, more varied output           | Creative writing, brainstorming   |

```ts
// Factual / deterministic
const fact = await dk.llm.generate({
  prompt: "What is the capital of France?",
  temperature: 0.0,
})

// Creative
const story = await dk.llm.generate({
  prompt: "Write a poem about the sea.",
  temperature: 0.9,
})
```

---

## Error Handling

LLM calls can fail for several reasons. The SDK throws `DarwinKitError` with specific error codes.

```ts
import { DarwinKit, DarwinKitError, ErrorCodes } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

try {
  const result = await dk.llm.generate({
    prompt: "Hello, world!",
  })
  console.log(result.text)
} catch (error) {
  if (error instanceof DarwinKitError) {
    if (error.isFrameworkUnavailable) {
      // Apple Intelligence / Foundation Models not available
      console.error("Foundation Models unavailable:", error.message)
    } else if (error.isOSVersionTooOld) {
      // macOS version does not support Foundation Models
      console.error("macOS 26+ required:", error.message)
    } else if (error.isPermissionDenied) {
      // User denied permission or guardrails triggered
      console.error("Permission denied:", error.message)
    } else if (error.isCancelled) {
      // Request was cancelled (e.g., client closed)
      console.error("Request cancelled:", error.message)
    } else {
      console.error(`Error ${error.code}: ${error.message}`)
    }
  }
}
```

### Error Codes

| Code     | Constant               | Description                                        |
|----------|------------------------|----------------------------------------------------|
| `-32001` | `FRAMEWORK_UNAVAILABLE`| Apple Intelligence or Foundation Models unavailable |
| `-32002` | `PERMISSION_DENIED`    | Permission denied or content guardrails triggered   |
| `-32003` | `OS_VERSION_TOO_OLD`   | macOS version does not support this feature         |
| `-32004` | `OPERATION_CANCELLED`  | The request was cancelled                          |
| `-32602` | `INVALID_PARAMS`       | Invalid parameters (e.g., malformed schema)        |
| `-32603` | `INTERNAL_ERROR`       | Internal error or request timeout                  |

### Guardrails

Apple's Foundation Models include built-in content safety guardrails. If a prompt or response triggers these guardrails, the SDK throws a `DarwinKitError` with code `PERMISSION_DENIED` (`-32002`). There is no way to disable these guardrails -- they are enforced by the system framework.

### Timeout Configuration

All LLM methods accept an optional `timeout` in the options object. The default timeout is 30 seconds (set via `DarwinKitOptions`). LLM generation may take longer than other API calls depending on prompt length and `max_tokens`, so consider increasing the timeout for long-form generation.

```ts
// Per-call timeout override (60 seconds)
const result = await dk.llm.generate(
  { prompt: "Write a detailed essay about renewable energy." },
  { timeout: 60_000 },
)

// Or set a higher default timeout for the entire client
const dk = new DarwinKit({ timeout: 60_000 })
```

---

## Complete Examples

### CLI Summarizer Tool

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

const filePath = process.argv[2]
if (!filePath) {
  console.error("Usage: bun summarize.ts <file>")
  process.exit(1)
}

const content = await Bun.file(filePath).text()

const unsubscribe = dk.llm.onChunk(({ chunk }) => {
  process.stdout.write(chunk)
})

await dk.llm.stream({
  prompt: `Summarize the following document in clear, concise bullet points:\n\n${content}`,
  system_instructions: "Output only markdown bullet points. No preamble.",
  temperature: 0.2,
  max_tokens: 500,
})

unsubscribe()
console.log() // final newline

dk.close()
```

### Structured Log Analyzer

```ts
import { DarwinKit } from "darwinkit"

const dk = new DarwinKit()
await dk.connect()

const logLines = `
[ERROR] 2026-03-23 10:15:32 - Connection timeout to db-primary (retry 3/3)
[WARN]  2026-03-23 10:15:33 - Falling back to db-replica
[ERROR] 2026-03-23 10:16:01 - Query failed: SELECT * FROM users WHERE id = 42
[INFO]  2026-03-23 10:16:02 - Circuit breaker opened for db-primary
`

const result = await dk.llm.generateStructured({
  prompt: `Analyze these application logs and extract structured information:\n\n${logLines}`,
  schema: {
    type: "object",
    properties: {
      severity: {
        type: "string",
        enum: ["low", "medium", "high", "critical"],
      },
      root_cause: { type: "string" },
      affected_services: {
        type: "array",
        items: { type: "string" },
      },
      recommended_actions: {
        type: "array",
        items: { type: "string" },
      },
      timeline: {
        type: "array",
        items: {
          type: "object",
          properties: {
            time: { type: "string" },
            event: { type: "string" },
            level: { type: "string" },
          },
        },
      },
    },
    required: ["severity", "root_cause", "affected_services", "recommended_actions"],
  },
  temperature: 0.1,
})

console.log(JSON.stringify(result.json, null, 2))

dk.close()
```

### Multi-Turn Code Review Assistant

```ts
import { DarwinKit } from "darwinkit"
import { randomUUID } from "crypto"

const dk = new DarwinKit({ timeout: 60_000 })
await dk.connect()

const sessionId = randomUUID()

await dk.llm.sessionCreate({
  session_id: sessionId,
  instructions: `You are an expert code reviewer. When reviewing code:
- Identify bugs, security issues, and performance problems
- Suggest improvements with code examples
- Be constructive and specific
- Rate severity: info, warning, error, critical`,
})

// First: submit code for review
const review = await dk.llm.sessionRespond({
  session_id: sessionId,
  prompt: `Review this function:

function fetchUser(id) {
  const res = fetch("/api/users/" + id)
  const data = res.json()
  localStorage.setItem("user_" + id, JSON.stringify(data))
  return data
}`,
  temperature: 0.3,
})
console.log("Review:", review.text)

// Follow-up: ask for a corrected version
const fix = await dk.llm.sessionRespond({
  session_id: sessionId,
  prompt: "Show me the corrected version with all issues fixed.",
  temperature: 0.2,
})
console.log("Fixed code:", fix.text)

// Follow-up: ask about testing
const tests = await dk.llm.sessionRespond({
  session_id: sessionId,
  prompt: "What test cases should I write for the corrected version?",
})
console.log("Test suggestions:", tests.text)

await dk.llm.sessionClose({ session_id: sessionId })
dk.close()
```

---

## API Reference Summary

| Method                   | SDK Method               | Description                              |
|--------------------------|--------------------------|------------------------------------------|
| `llm.available`          | `dk.llm.available()`     | Check Foundation Models availability     |
| `llm.generate`           | `dk.llm.generate()`      | Single-shot text generation              |
| `llm.generate_structured`| `dk.llm.generateStructured()` | Generate JSON conforming to a schema |
| `llm.stream`             | `dk.llm.stream()`        | Streaming text generation                |
| `llm.session_create`     | `dk.llm.sessionCreate()` | Create a multi-turn conversation session |
| `llm.session_respond`    | `dk.llm.sessionRespond()`| Send a message in an existing session    |
| `llm.session_close`      | `dk.llm.sessionClose()`  | Close and clean up a session             |
| --                       | `dk.llm.onChunk()`       | Listen for streaming chunk notifications |

All methods except `available()` and `onChunk()` also expose a `.prepare()` variant for use with `dk.batch()`.
