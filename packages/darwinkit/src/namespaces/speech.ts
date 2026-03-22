import type { DarwinKitClient } from "../client.js"
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

export class Speech {
  readonly transcribe: {
    (
      params: SpeechTranscribeParams,
      options?: { timeout?: number },
    ): Promise<SpeechTranscribeResult>
    prepare(
      params: SpeechTranscribeParams,
    ): PreparedCall<"speech.transcribe">
  }
  readonly installLanguage: {
    (
      params: SpeechInstallLanguageParams,
      options?: { timeout?: number },
    ): Promise<SpeechOkResult>
    prepare(
      params: SpeechInstallLanguageParams,
    ): PreparedCall<"speech.install_language">
  }
  readonly uninstallLanguage: {
    (
      params: SpeechUninstallLanguageParams,
      options?: { timeout?: number },
    ): Promise<SpeechOkResult>
    prepare(
      params: SpeechUninstallLanguageParams,
    ): PreparedCall<"speech.uninstall_language">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.transcribe = method(
      client,
      "speech.transcribe",
    ) as Speech["transcribe"]
    this.installLanguage = method(
      client,
      "speech.install_language",
    ) as Speech["installLanguage"]
    this.uninstallLanguage = method(
      client,
      "speech.uninstall_language",
    ) as Speech["uninstallLanguage"]
  }

  /** List all supported languages for speech recognition */
  languages(options?: { timeout?: number }): Promise<SpeechLanguagesResult> {
    return this.client.call(
      "speech.languages",
      {} as Record<string, never>,
      options,
    )
  }

  /** List installed (downloaded) language models */
  installedLanguages(
    options?: { timeout?: number },
  ): Promise<SpeechLanguagesResult> {
    return this.client.call(
      "speech.installed_languages",
      {} as Record<string, never>,
      options,
    )
  }

  /** Check speech recognition availability and device support */
  capabilities(
    options?: { timeout?: number },
  ): Promise<SpeechCapabilitiesResult> {
    return this.client.call(
      "speech.capabilities",
      {} as Record<string, never>,
      options,
    )
  }
}
