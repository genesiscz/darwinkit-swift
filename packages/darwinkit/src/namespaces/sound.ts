import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  SoundClassifyParams,
  SoundClassifyResult,
  SoundClassifyAtParams,
  SoundClassifyAtResult,
  SoundCategoriesResult,
  SoundAvailableResult,
} from "../types.js";

// helper to create callable+preparable methods
type PreparedMethod<M extends MethodName> = ((
  params: MethodMap[M]["params"],
  options?: { timeout?: number },
) => Promise<MethodMap[M]["result"]>) & {
  prepare(params: MethodMap[M]["params"]): PreparedCall<M>;
};

function method<M extends MethodName>(
  client: DarwinKitClient,
  name: M,
): PreparedMethod<M> {
  const fn = ((
    params: MethodMap[M]["params"],
    options?: { timeout?: number },
  ) => client.call(name, params, options)) as PreparedMethod<M>;
  fn.prepare = (params: MethodMap[M]["params"]): PreparedCall<M> => ({
    method: name,
    params,
    __brand: undefined as unknown as MethodMap[M]["result"],
  });
  return fn;
}

export class Sound {
  readonly classify: {
    (
      params: SoundClassifyParams,
      options?: { timeout?: number },
    ): Promise<SoundClassifyResult>;
    prepare(params: SoundClassifyParams): PreparedCall<"sound.classify">;
  };
  readonly classifyAt: {
    (
      params: SoundClassifyAtParams,
      options?: { timeout?: number },
    ): Promise<SoundClassifyAtResult>;
    prepare(params: SoundClassifyAtParams): PreparedCall<"sound.classify_at">;
  };

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;
    this.classify = method(client, "sound.classify") as Sound["classify"];
    this.classifyAt = method(
      client,
      "sound.classify_at",
    ) as Sound["classifyAt"];
  }

  /** List all available sound categories (no params needed) */
  categories(options?: { timeout?: number }): Promise<SoundCategoriesResult> {
    return this.client.call(
      "sound.categories",
      {} as Record<string, never>,
      options,
    );
  }

  /** Check if SoundAnalysis is available (no params needed) */
  available(options?: { timeout?: number }): Promise<SoundAvailableResult> {
    return this.client.call(
      "sound.available",
      {} as Record<string, never>,
      options,
    );
  }
}
