import { ensureBinary } from "./binary.js"
import { Transport } from "./transport.js"
import { DarwinKitError } from "./errors.js"
import type { DarwinKitEvent, EventMap, EventType } from "./events.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  BatchResult,
  ReadyNotification,
} from "./types.js"
import { NLP } from "./namespaces/nlp.js"
import { Vision } from "./namespaces/vision.js"
import { Auth } from "./namespaces/auth.js"
import { System } from "./namespaces/system.js"
import { ICloud } from "./namespaces/icloud.js"
import { CoreML } from "./namespaces/coreml.js"
import { Translate } from "./namespaces/translate.js"
import { Speech } from "./namespaces/speech.js"
import { Sound } from "./namespaces/sound.js"

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface DarwinKitOptions {
  /** Path to darwinkit binary. If omitted, auto-resolves (PATH → cache → download → build). */
  binary?: string
  /** Default request timeout in ms. Default: 30000. */
  timeout?: number
  /** Auto-reconnect configuration. */
  reconnect?: {
    enabled?: boolean   // default: true
    maxRetries?: number // default: 3
    delay?: number      // default: 1000
  }
  /** Logger instance. Any object with debug/info/warn/error methods. */
  logger?: Logger
  /** Minimum log level. Default: "info". */
  logLevel?: LogLevel
}

export type LogLevel = "debug" | "info" | "warn" | "error" | "silent"

export interface Logger {
  debug(...args: unknown[]): void
  info(...args: unknown[]): void
  warn(...args: unknown[]): void
  error(...args: unknown[]): void
}

/** Interface that namespace classes use to call methods. */
export interface DarwinKitClient {
  call<M extends MethodName>(
    method: M,
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ): Promise<MethodMap[M]["result"]>
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

interface PendingRequest {
  resolve: (value: unknown) => void
  reject: (error: Error) => void
  timer: ReturnType<typeof setTimeout>
  method: string
  params: unknown
}

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
  silent: 4,
}

// ---------------------------------------------------------------------------
// DarwinKit client
// ---------------------------------------------------------------------------

export class DarwinKit implements DarwinKitClient {
  /** Namespaced APIs */
  readonly nlp: NLP
  readonly vision: Vision
  readonly auth: Auth
  readonly system: System
  readonly icloud: ICloud
  readonly coreml: CoreML
  readonly translate: Translate
  readonly speech: Speech
  readonly sound: Sound

  private transport = new Transport()
  private pending = new Map<string, PendingRequest>()
  private nextId = 1
  private _connected = false
  private connectPromise: Promise<ReadyNotification> | null = null

  private readonly binaryPath: string | undefined
  private resolvedBinary: string | null = null
  private readonly defaultTimeout: number
  private readonly reconnectConfig: {
    enabled: boolean
    maxRetries: number
    delay: number
  }
  private readonly logger: Logger | null
  private readonly logLevel: number
  private reconnectAttempt = 0
  private intentionallyClosed = false

  // Event system
  private listeners: Array<(event: DarwinKitEvent) => void> = []
  private typedListeners = new Map<EventType, Set<(payload: never) => void>>()

  constructor(options?: DarwinKitOptions) {
    this.binaryPath = options?.binary
    this.defaultTimeout = options?.timeout ?? 30_000
    this.reconnectConfig = {
      enabled: options?.reconnect?.enabled ?? true,
      maxRetries: options?.reconnect?.maxRetries ?? 3,
      delay: options?.reconnect?.delay ?? 1000,
    }
    this.logger = options?.logger ?? null
    this.logLevel = LOG_LEVELS[options?.logLevel ?? "info"]

    // Initialize namespaces (they hold a reference to `this` as DarwinKitClient)
    this.nlp = new NLP(this)
    this.vision = new Vision(this)
    this.auth = new Auth(this)
    this.system = new System(this)
    this.icloud = new ICloud(this)
    this.coreml = new CoreML(this)
    this.translate = new Translate(this)
    this.speech = new Speech(this)
    this.sound = new Sound(this)
  }

  get connected(): boolean {
    return this._connected
  }

  // ─── Lifecycle ───────────────────────────────────────────

  /**
   * Explicitly connect (eager startup). Optional — auto-connects on first call.
   */
  async connect(): Promise<ReadyNotification> {
    return this.ensureConnected()
  }

  /**
   * Gracefully close the server by closing stdin.
   */
  close(): void {
    this.intentionallyClosed = true
    this._connected = false
    this.connectPromise = null
    this.transport.stop()
    for (const [, pending] of this.pending) {
      clearTimeout(pending.timer)
      pending.reject(new Error("Client closed"))
    }
    this.pending.clear()
  }

  // ─── JSON-RPC call ──────────────────────────────────────

  async call<M extends MethodName>(
    method: M,
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ): Promise<MethodMap[M]["result"]> {
    await this.ensureConnected()

    const id = String(this.nextId++)
    const timeout = options?.timeout ?? this.defaultTimeout
    const request = { jsonrpc: "2.0", id, method, params }

    this.log("debug", `→ ${method} [${id}]`)
    this.transport.writeLine(JSON.stringify(request))

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id)
        reject(new DarwinKitError(-32603, `Request ${method} timed out after ${timeout}ms`))
      }, timeout)

      this.pending.set(id, {
        resolve: resolve as (v: unknown) => void,
        reject,
        timer,
        method,
        params,
      })
    })
  }

  // ─── Batch API ──────────────────────────────────────────

  async batch<T extends ReadonlyArray<PreparedCall<MethodName>>>(
    ...calls: T
  ): Promise<BatchResult<T>> {
    await this.ensureConnected()

    const promises = calls.map((prepared) =>
      this.call(prepared.method, prepared.params),
    )

    return Promise.all(promises) as Promise<BatchResult<T>>
  }

  // ─── Event system ───────────────────────────────────────

  /**
   * Catch-all event listener. Returns an unsubscribe function.
   */
  listen(handler: (event: DarwinKitEvent) => void): () => void {
    this.listeners.push(handler)
    return () => {
      const idx = this.listeners.indexOf(handler)
      if (idx !== -1) this.listeners.splice(idx, 1)
    }
  }

  /**
   * Typed per-event listener. Returns an unsubscribe function.
   */
  on<E extends EventType>(
    event: E,
    handler: (payload: EventMap[E]) => void,
  ): () => void {
    if (!this.typedListeners.has(event)) {
      this.typedListeners.set(event, new Set())
    }
    const set = this.typedListeners.get(event)!
    set.add(handler as (payload: never) => void)
    return () => {
      set.delete(handler as (payload: never) => void)
    }
  }

  // ─── Internal ───────────────────────────────────────────

  private emit(event: DarwinKitEvent): void {
    for (const handler of this.listeners) {
      handler(event)
    }
    const typed = this.typedListeners.get(event.type)
    if (typed) {
      const payload = event as EventMap[typeof event.type]
      for (const handler of typed) {
        ;(handler as (p: typeof payload) => void)(payload)
      }
    }
  }

  private async ensureConnected(): Promise<ReadyNotification> {
    if (this._connected) {
      return { version: "", capabilities: [] }
    }
    if (this.connectPromise) {
      return this.connectPromise
    }
    this.connectPromise = this.doConnect()
    return this.connectPromise
  }

  private async doConnect(): Promise<ReadyNotification> {
    this.intentionallyClosed = false

    if (!this.resolvedBinary) {
      this.log("debug", "Resolving binary...")
      this.resolvedBinary = await ensureBinary(this.binaryPath)
      this.log("debug", `Binary resolved: ${this.resolvedBinary}`)
    }

    return new Promise<ReadyNotification>((resolve, reject) => {
      let readyReceived = false

      this.transport.start({
        binary: this.resolvedBinary!,
        onLine: (line: string) => {
          this.handleLine(line, readyReceived, (notification) => {
            readyReceived = true
            this._connected = true
            this.reconnectAttempt = 0
            resolve(notification)
          })
        },
        onExit: (code: number | null) => {
          this._connected = false
          this.connectPromise = null

          if (!readyReceived) {
            reject(new Error(`darwinkit exited with code ${code} before ready`))
            return
          }

          this.emit({ type: "disconnect", code })

          if (!this.intentionallyClosed && this.reconnectConfig.enabled) {
            this.attemptReconnect()
          } else {
            this.rejectAllPending("Server exited")
          }
        },
        onError: (err: Error) => {
          this._connected = false
          this.connectPromise = null
          this.emit({ type: "error", error: err })
          if (!readyReceived) reject(err)
        },
      })
    })
  }

  private handleLine(
    line: string,
    readyReceived: boolean,
    onReady: (notification: ReadyNotification) => void,
  ): void {
    let msg: Record<string, unknown>
    try {
      msg = JSON.parse(line)
    } catch {
      return
    }

    // Ready notification
    if (!readyReceived && msg.method === "ready") {
      const params = msg.params as ReadyNotification
      this.log("info", `Connected (v${params.version}, ${params.capabilities.length} methods)`)
      this.emit({ type: "ready", ...params })
      onReady(params)
      return
    }

    // iCloud files changed notification
    if (msg.method === "icloud.files_changed") {
      const params = msg.params as { paths: string[] }
      this.emit({ type: "filesChanged", paths: params.paths })
      this.icloud._notifyFilesChanged(params)
      return
    }

    // JSON-RPC response
    const id = msg.id as string | undefined
    if (!id) return

    const pending = this.pending.get(id)
    if (!pending) return
    this.pending.delete(id)
    clearTimeout(pending.timer)

    if (msg.error) {
      const err = msg.error as { code: number; message: string; data?: unknown }
      this.log("debug", `← error ${err.code}: ${err.message} [${id}]`)
      pending.reject(new DarwinKitError(err.code, err.message, err.data))
    } else {
      this.log("debug", `← ${pending.method} [${id}]`)
      pending.resolve(msg.result)
    }
  }

  private async attemptReconnect(): Promise<void> {
    const held = Array.from(this.pending.entries())

    while (this.reconnectAttempt < this.reconnectConfig.maxRetries) {
      this.reconnectAttempt++
      this.log("warn", `Reconnecting (attempt ${this.reconnectAttempt}/${this.reconnectConfig.maxRetries})...`)
      this.emit({ type: "reconnect", attempt: this.reconnectAttempt })

      await sleep(this.reconnectConfig.delay)

      try {
        await this.doConnect()
        // Replay held requests
        for (const [oldId, req] of held) {
          this.pending.delete(oldId)
          clearTimeout(req.timer)
          // Re-send with a new id
          this.call(req.method as MethodName, req.params as MethodMap[MethodName]["params"])
            .then(req.resolve)
            .catch(req.reject)
        }
        return
      } catch {
        // Try again
      }
    }

    this.log("error", "Reconnect failed after max retries")
    this.rejectAllPending("Reconnect failed")
  }

  private rejectAllPending(reason: string): void {
    for (const [, pending] of this.pending) {
      clearTimeout(pending.timer)
      pending.reject(new Error(reason))
    }
    this.pending.clear()
  }

  private log(level: Exclude<LogLevel, "silent">, message: string): void {
    if (!this.logger || LOG_LEVELS[level] < this.logLevel) return
    this.logger[level](`[darwinkit] ${message}`)
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms))
}
