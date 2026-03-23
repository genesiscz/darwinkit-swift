import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  EmbedParams,
  EmbedResult,
  DistanceParams,
  DistanceResult,
  NeighborsParams,
  NeighborsResult,
  TagParams,
  TagResult,
  SentimentParams,
  SentimentResult,
  LanguageParams,
  LanguageResult,
} from "../types.js"

// helper to create callable+preparable methods
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

export class NLP {
  readonly embed: {
    (params: EmbedParams, options?: { timeout?: number }): Promise<EmbedResult>
    prepare(params: EmbedParams): PreparedCall<"nlp.embed">
  }
  readonly distance: {
    (
      params: DistanceParams,
      options?: { timeout?: number },
    ): Promise<DistanceResult>
    prepare(params: DistanceParams): PreparedCall<"nlp.distance">
  }
  readonly neighbors: {
    (
      params: NeighborsParams,
      options?: { timeout?: number },
    ): Promise<NeighborsResult>
    prepare(params: NeighborsParams): PreparedCall<"nlp.neighbors">
  }
  readonly tag: {
    (params: TagParams, options?: { timeout?: number }): Promise<TagResult>
    prepare(params: TagParams): PreparedCall<"nlp.tag">
  }
  readonly sentiment: {
    (
      params: SentimentParams,
      options?: { timeout?: number },
    ): Promise<SentimentResult>
    prepare(params: SentimentParams): PreparedCall<"nlp.sentiment">
  }
  readonly language: {
    (
      params: LanguageParams,
      options?: { timeout?: number },
    ): Promise<LanguageResult>
    prepare(params: LanguageParams): PreparedCall<"nlp.language">
  }

  constructor(client: DarwinKitClient) {
    this.embed = method(client, "nlp.embed") as NLP["embed"]
    this.distance = method(client, "nlp.distance") as NLP["distance"]
    this.neighbors = method(client, "nlp.neighbors") as NLP["neighbors"]
    this.tag = method(client, "nlp.tag") as NLP["tag"]
    this.sentiment = method(client, "nlp.sentiment") as NLP["sentiment"]
    this.language = method(client, "nlp.language") as NLP["language"]
  }
}
