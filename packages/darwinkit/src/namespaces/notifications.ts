import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  NotifyRequestAuthorizationParams,
  NotifyRequestAuthorizationResult,
  NotifySettingsResult,
  NotifySendParams,
  NotifySendResult,
  NotifyPendingResult,
  NotifyDeliveredResult,
  NotifyRemoveParams,
  NotifyOkResult,
  NotifyRegisterCategoryParams,
  NotifyInteractionEvent,
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

export class Notifications {
  private client: DarwinKitClient;
  private interactionListeners: Array<
    (event: NotifyInteractionEvent) => void
  > = [];

  readonly send: {
    (
      params: NotifySendParams,
      options?: { timeout?: number },
    ): Promise<NotifySendResult>;
    prepare(params: NotifySendParams): PreparedCall<"notifications.send">;
  };
  readonly removePending: {
    (
      params: NotifyRemoveParams,
      options?: { timeout?: number },
    ): Promise<NotifyOkResult>;
    prepare(
      params: NotifyRemoveParams,
    ): PreparedCall<"notifications.remove_pending">;
  };
  readonly removeDelivered: {
    (
      params: NotifyRemoveParams,
      options?: { timeout?: number },
    ): Promise<NotifyOkResult>;
    prepare(
      params: NotifyRemoveParams,
    ): PreparedCall<"notifications.remove_delivered">;
  };
  readonly registerCategory: {
    (
      params: NotifyRegisterCategoryParams,
      options?: { timeout?: number },
    ): Promise<NotifyOkResult>;
    prepare(
      params: NotifyRegisterCategoryParams,
    ): PreparedCall<"notifications.register_category">;
  };

  constructor(client: DarwinKitClient) {
    this.client = client;
    this.send = method(client, "notifications.send") as Notifications["send"];
    this.removePending = method(
      client,
      "notifications.remove_pending",
    ) as Notifications["removePending"];
    this.removeDelivered = method(
      client,
      "notifications.remove_delivered",
    ) as Notifications["removeDelivered"];
    this.registerCategory = method(
      client,
      "notifications.register_category",
    ) as Notifications["registerCategory"];
  }

  requestAuthorization(
    params?: NotifyRequestAuthorizationParams,
    options?: { timeout?: number },
  ): Promise<NotifyRequestAuthorizationResult> {
    return this.client.call(
      "notifications.request_authorization",
      params ?? ({} as NotifyRequestAuthorizationParams),
      options,
    );
  }

  settings(options?: { timeout?: number }): Promise<NotifySettingsResult> {
    return this.client.call(
      "notifications.settings",
      {} as Record<string, never>,
      options,
    );
  }

  listPending(options?: { timeout?: number }): Promise<NotifyPendingResult> {
    return this.client.call(
      "notifications.list_pending",
      {} as Record<string, never>,
      options,
    );
  }

  removeAllPending(options?: { timeout?: number }): Promise<NotifyOkResult> {
    return this.client.call(
      "notifications.remove_all_pending",
      {} as Record<string, never>,
      options,
    );
  }

  listDelivered(options?: { timeout?: number }): Promise<NotifyDeliveredResult> {
    return this.client.call(
      "notifications.list_delivered",
      {} as Record<string, never>,
      options,
    );
  }

  removeAllDelivered(options?: { timeout?: number }): Promise<NotifyOkResult> {
    return this.client.call(
      "notifications.remove_all_delivered",
      {} as Record<string, never>,
      options,
    );
  }

  /**
   * Listen for notification interaction events (taps, action buttons, reply text).
   * Returns an unsubscribe function.
   */
  onInteraction(
    handler: (event: NotifyInteractionEvent) => void,
  ): () => void {
    this.interactionListeners.push(handler);
    return () => {
      const idx = this.interactionListeners.indexOf(handler);
      if (idx !== -1) this.interactionListeners.splice(idx, 1);
    };
  }

  /** @internal Called by DarwinKit client when notifications.interaction arrives */
  _notifyInteraction(event: NotifyInteractionEvent): void {
    for (const handler of this.interactionListeners) {
      handler(event);
    }
  }
}
