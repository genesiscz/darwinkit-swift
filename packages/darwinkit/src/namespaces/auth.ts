import type { DarwinKitClient } from "../client.js"
import type {
  PreparedCall,
  AuthAvailableResult,
  AuthenticateParams,
  AuthenticateResult,
} from "../types.js"

export class Auth {
  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
  }

  available(options?: { timeout?: number }): Promise<AuthAvailableResult> {
    return this.client.call(
      "auth.available",
      {} as Record<string, never>,
      options,
    )
  }

  authenticate(
    params?: AuthenticateParams,
    options?: { timeout?: number },
  ): Promise<AuthenticateResult> {
    return this.client.call(
      "auth.authenticate",
      params ?? ({} as Record<string, never> as AuthenticateParams),
      options,
    )
  }

  prepareAvailable(): PreparedCall<"auth.available"> {
    return {
      method: "auth.available",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as AuthAvailableResult,
    }
  }

  prepareAuthenticate(
    params?: AuthenticateParams,
  ): PreparedCall<"auth.authenticate"> {
    return {
      method: "auth.authenticate",
      params: params ?? ({} as Record<string, never> as AuthenticateParams),
      __brand: undefined as unknown as AuthenticateResult,
    }
  }
}
