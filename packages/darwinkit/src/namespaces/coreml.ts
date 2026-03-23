import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  CoreMLLoadModelParams,
  CoreMLModelInfo,
  CoreMLUnloadModelParams,
  CoreMLOkResult,
  CoreMLModelInfoParams,
  CoreMLModelsResult,
  CoreMLEmbedParams,
  CoreMLEmbedResult,
  CoreMLEmbedBatchParams,
  CoreMLEmbedBatchResult,
  CoreMLLoadContextualParams,
  CoreMLContextualEmbedParams,
  CoreMLContextualEmbedBatchParams,
} from "../types.js"

type PreparedMethod<M extends MethodName> = ((
  params: MethodMap[M]["params"],
  options?: { timeout?: number },
) => Promise<MethodMap[M]["result"]>) & {
  prepare(params: MethodMap[M]["params"]): PreparedCall<M>
}

function method<M extends MethodName>(
  client: DarwinKitClient,
  name: M,
): PreparedMethod<M> {
  const fn = ((
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)) as PreparedMethod<M>
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  })
  return fn
}

export class CoreML {
  readonly loadModel: {
    (
      params: CoreMLLoadModelParams,
      options?: { timeout?: number },
    ): Promise<CoreMLModelInfo>
    prepare(params: CoreMLLoadModelParams): PreparedCall<"coreml.load_model">
  }
  readonly unloadModel: {
    (
      params: CoreMLUnloadModelParams,
      options?: { timeout?: number },
    ): Promise<CoreMLOkResult>
    prepare(
      params: CoreMLUnloadModelParams,
    ): PreparedCall<"coreml.unload_model">
  }
  readonly modelInfo: {
    (
      params: CoreMLModelInfoParams,
      options?: { timeout?: number },
    ): Promise<CoreMLModelInfo>
    prepare(
      params: CoreMLModelInfoParams,
    ): PreparedCall<"coreml.model_info">
  }
  readonly embed: {
    (
      params: CoreMLEmbedParams,
      options?: { timeout?: number },
    ): Promise<CoreMLEmbedResult>
    prepare(params: CoreMLEmbedParams): PreparedCall<"coreml.embed">
  }
  readonly embedBatch: {
    (
      params: CoreMLEmbedBatchParams,
      options?: { timeout?: number },
    ): Promise<CoreMLEmbedBatchResult>
    prepare(
      params: CoreMLEmbedBatchParams,
    ): PreparedCall<"coreml.embed_batch">
  }
  readonly loadContextual: {
    (
      params: CoreMLLoadContextualParams,
      options?: { timeout?: number },
    ): Promise<CoreMLModelInfo>
    prepare(
      params: CoreMLLoadContextualParams,
    ): PreparedCall<"coreml.load_contextual">
  }
  readonly contextualEmbed: {
    (
      params: CoreMLContextualEmbedParams,
      options?: { timeout?: number },
    ): Promise<CoreMLEmbedResult>
    prepare(
      params: CoreMLContextualEmbedParams,
    ): PreparedCall<"coreml.contextual_embed">
  }
  readonly embedContextualBatch: {
    (
      params: CoreMLContextualEmbedBatchParams,
      options?: { timeout?: number },
    ): Promise<CoreMLEmbedBatchResult>
    prepare(
      params: CoreMLContextualEmbedBatchParams,
    ): PreparedCall<"coreml.embed_contextual_batch">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.loadModel = method(client, "coreml.load_model") as CoreML["loadModel"]
    this.unloadModel = method(
      client,
      "coreml.unload_model",
    ) as CoreML["unloadModel"]
    this.modelInfo = method(
      client,
      "coreml.model_info",
    ) as CoreML["modelInfo"]
    this.embed = method(client, "coreml.embed") as CoreML["embed"]
    this.embedBatch = method(
      client,
      "coreml.embed_batch",
    ) as CoreML["embedBatch"]
    this.loadContextual = method(
      client,
      "coreml.load_contextual",
    ) as CoreML["loadContextual"]
    this.contextualEmbed = method(
      client,
      "coreml.contextual_embed",
    ) as CoreML["contextualEmbed"]
    this.embedContextualBatch = method(
      client,
      "coreml.embed_contextual_batch",
    ) as CoreML["embedContextualBatch"]
  }

  /** List all loaded models (no params needed) */
  models(options?: { timeout?: number }): Promise<CoreMLModelsResult> {
    return this.client.call(
      "coreml.models",
      {} as Record<string, never>,
      options,
    )
  }
}
