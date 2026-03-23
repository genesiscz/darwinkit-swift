import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  TranslateTextParams,
  TranslateTextResult,
  TranslateBatchParams,
  TranslateBatchResult,
  TranslateLanguagesResult,
  TranslateLanguageStatusParams,
  TranslateLanguageStatusResult,
  TranslatePrepareParams,
  TranslatePrepareResult,
} from "../types.js";

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

export class Translate {
  readonly text: {
    (
      params: TranslateTextParams,
      options?: { timeout?: number },
    ): Promise<TranslateTextResult>;
    prepare(params: TranslateTextParams): PreparedCall<"translate.text">;
  };
  readonly batch: {
    (
      params: TranslateBatchParams,
      options?: { timeout?: number },
    ): Promise<TranslateBatchResult>;
    prepare(params: TranslateBatchParams): PreparedCall<"translate.batch">;
  };
  readonly languageStatus: {
    (
      params: TranslateLanguageStatusParams,
      options?: { timeout?: number },
    ): Promise<TranslateLanguageStatusResult>;
    prepare(
      params: TranslateLanguageStatusParams,
    ): PreparedCall<"translate.language_status">;
  };
  readonly preparePair: {
    (
      params: TranslatePrepareParams,
      options?: { timeout?: number },
    ): Promise<TranslatePrepareResult>;
    prepare(params: TranslatePrepareParams): PreparedCall<"translate.prepare">;
  };

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;
    this.text = method(client, "translate.text") as Translate["text"];
    this.batch = method(client, "translate.batch") as Translate["batch"];
    this.languageStatus = method(
      client,
      "translate.language_status",
    ) as Translate["languageStatus"];
    this.preparePair = method(
      client,
      "translate.prepare",
    ) as Translate["preparePair"];
  }

  /** List all supported translation languages (no params needed) */
  languages(options?: { timeout?: number }): Promise<TranslateLanguagesResult> {
    return this.client.call(
      "translate.languages",
      {} as Record<string, never>,
      options,
    );
  }
}
