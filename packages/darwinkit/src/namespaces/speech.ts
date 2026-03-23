import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  SpeechTranscribeParams,
  SpeechTranscribeResult,
  SpeechLanguagesResult,
  SpeechInstallLanguageParams,
  SpeechUninstallLanguageParams,
  SpeechOkResult,
  SpeechCapabilitiesResult,
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

export class Speech {
  readonly transcribe: {
    (
      params: SpeechTranscribeParams,
      options?: { timeout?: number },
    ): Promise<SpeechTranscribeResult>;
    prepare(params: SpeechTranscribeParams): PreparedCall<"speech.transcribe">;
  };
  readonly installLanguage: {
    (
      params: SpeechInstallLanguageParams,
      options?: { timeout?: number },
    ): Promise<SpeechOkResult>;
    prepare(
      params: SpeechInstallLanguageParams,
    ): PreparedCall<"speech.install_language">;
  };
  readonly uninstallLanguage: {
    (
      params: SpeechUninstallLanguageParams,
      options?: { timeout?: number },
    ): Promise<SpeechOkResult>;
    prepare(
      params: SpeechUninstallLanguageParams,
    ): PreparedCall<"speech.uninstall_language">;
  };
  readonly languages: {
    (options?: { timeout?: number }): Promise<SpeechLanguagesResult>;
    prepare(params: Record<string, never>): PreparedCall<"speech.languages">;
  };
  readonly installedLanguages: {
    (options?: { timeout?: number }): Promise<SpeechLanguagesResult>;
    prepare(
      params: Record<string, never>,
    ): PreparedCall<"speech.installed_languages">;
  };
  readonly capabilities: {
    (options?: { timeout?: number }): Promise<SpeechCapabilitiesResult>;
    prepare(params: Record<string, never>): PreparedCall<"speech.capabilities">;
  };

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;
    this.transcribe = method(
      client,
      "speech.transcribe",
    ) as Speech["transcribe"];
    this.installLanguage = method(
      client,
      "speech.install_language",
    ) as Speech["installLanguage"];
    this.uninstallLanguage = method(
      client,
      "speech.uninstall_language",
    ) as Speech["uninstallLanguage"];
    this.languages = method(client, "speech.languages") as Speech["languages"];
    this.installedLanguages = method(
      client,
      "speech.installed_languages",
    ) as Speech["installedLanguages"];
    this.capabilities = method(
      client,
      "speech.capabilities",
    ) as Speech["capabilities"];
  }
}
