import type { DarwinKitClient } from "../client.js";
import type { PreparedCall, CapabilitiesResult } from "../types.js";

export class System {
  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;
  }

  capabilities(options?: { timeout?: number }): Promise<CapabilitiesResult> {
    return this.client.call(
      "system.capabilities",
      {} as Record<string, never>,
      options,
    );
  }

  prepareCapabilities(): PreparedCall<"system.capabilities"> {
    return {
      method: "system.capabilities",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as CapabilitiesResult,
    };
  }
}
