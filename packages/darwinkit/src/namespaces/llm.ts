import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
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
} from "../types.js"

function method<M extends MethodName>(client: DarwinKitClient, name: M) {
  const fn = (
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  })
  return fn
}

export class LLM {
  readonly generate: {
    (
      params: LLMGenerateParams,
      options?: { timeout?: number },
    ): Promise<LLMGenerateResult>
    prepare(params: LLMGenerateParams): PreparedCall<"llm.generate">
  }
  readonly generateStructured: {
    (
      params: LLMGenerateStructuredParams,
      options?: { timeout?: number },
    ): Promise<LLMGenerateStructuredResult>
    prepare(
      params: LLMGenerateStructuredParams,
    ): PreparedCall<"llm.generate_structured">
  }
  readonly sessionCreate: {
    (
      params: LLMSessionCreateParams,
      options?: { timeout?: number },
    ): Promise<LLMOkResult>
    prepare(
      params: LLMSessionCreateParams,
    ): PreparedCall<"llm.session_create">
  }
  readonly sessionRespond: {
    (
      params: LLMSessionRespondParams,
      options?: { timeout?: number },
    ): Promise<LLMGenerateResult>
    prepare(
      params: LLMSessionRespondParams,
    ): PreparedCall<"llm.session_respond">
  }
  readonly sessionClose: {
    (
      params: LLMSessionCloseParams,
      options?: { timeout?: number },
    ): Promise<LLMOkResult>
    prepare(
      params: LLMSessionCloseParams,
    ): PreparedCall<"llm.session_close">
  }

  private client: DarwinKitClient
  private chunkListeners: Array<(notification: LLMChunkNotification) => void> =
    []

  constructor(client: DarwinKitClient) {
    this.client = client
    this.generate = method(client, "llm.generate") as LLM["generate"]
    this.generateStructured = method(
      client,
      "llm.generate_structured",
    ) as LLM["generateStructured"]
    this.sessionCreate = method(
      client,
      "llm.session_create",
    ) as LLM["sessionCreate"]
    this.sessionRespond = method(
      client,
      "llm.session_respond",
    ) as LLM["sessionRespond"]
    this.sessionClose = method(
      client,
      "llm.session_close",
    ) as LLM["sessionClose"]
  }

  /** Check if Apple Intelligence / Foundation Models is available */
  available(options?: { timeout?: number }): Promise<LLMAvailableResult> {
    return this.client.call(
      "llm.available",
      {} as Record<string, never>,
      options,
    )
  }

  /**
   * Stream text generation. Returns the final complete result.
   * Use `onChunk()` to receive streaming tokens as they arrive.
   */
  stream(
    params: LLMStreamParams,
    options?: { timeout?: number },
  ): Promise<LLMGenerateResult> {
    return this.client.call("llm.stream", params, options)
  }

  /**
   * Register a listener for streaming chunk notifications.
   * Returns an unsubscribe function.
   */
  onChunk(
    handler: (notification: LLMChunkNotification) => void,
  ): () => void {
    this.chunkListeners.push(handler)
    return () => {
      const idx = this.chunkListeners.indexOf(handler)
      if (idx !== -1) this.chunkListeners.splice(idx, 1)
    }
  }

  /** @internal Called by DarwinKit client when llm.chunk notification arrives */
  _notifyChunk(notification: LLMChunkNotification): void {
    for (const handler of this.chunkListeners) {
      handler(notification)
    }
  }
}
