import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  RemindersAuthorizedResult,
  RemindersListsResult,
  RemindersItemsParams,
  RemindersItemsResult,
  RemindersSaveItemParams,
  RemindersSaveResult,
  RemindersRemoveItemParams,
  CalendarOkResult,
  RemindersCompleteItemParams,
  ReminderInfo,
  RemindersIncompleteParams,
  RemindersCompletedParams,
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

export class Reminders {
  readonly items: {
    (
      params?: RemindersItemsParams,
      options?: { timeout?: number },
    ): Promise<RemindersItemsResult>;
    prepare(params?: RemindersItemsParams): PreparedCall<"reminders.items">;
  };

  readonly saveItem: {
    (
      params: RemindersSaveItemParams,
      options?: { timeout?: number },
    ): Promise<RemindersSaveResult>;
    prepare(
      params: RemindersSaveItemParams,
    ): PreparedCall<"reminders.save_item">;
  };

  readonly removeItem: {
    (
      params: RemindersRemoveItemParams,
      options?: { timeout?: number },
    ): Promise<CalendarOkResult>;
    prepare(
      params: RemindersRemoveItemParams,
    ): PreparedCall<"reminders.remove_item">;
  };

  readonly completeItem: {
    (
      params: RemindersCompleteItemParams,
      options?: { timeout?: number },
    ): Promise<ReminderInfo>;
    prepare(
      params: RemindersCompleteItemParams,
    ): PreparedCall<"reminders.complete_item">;
  };

  readonly incomplete: {
    (
      params?: RemindersIncompleteParams,
      options?: { timeout?: number },
    ): Promise<RemindersItemsResult>;
    prepare(
      params?: RemindersIncompleteParams,
    ): PreparedCall<"reminders.incomplete">;
  };

  readonly completed: {
    (
      params?: RemindersCompletedParams,
      options?: { timeout?: number },
    ): Promise<RemindersItemsResult>;
    prepare(
      params?: RemindersCompletedParams,
    ): PreparedCall<"reminders.completed">;
  };

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;

    // Read methods
    this.items = method(client, "reminders.items") as Reminders["items"];

    // Write methods
    this.saveItem = method(
      client,
      "reminders.save_item",
    ) as Reminders["saveItem"];
    this.removeItem = method(
      client,
      "reminders.remove_item",
    ) as Reminders["removeItem"];
    this.completeItem = method(
      client,
      "reminders.complete_item",
    ) as Reminders["completeItem"];

    // Query methods
    this.incomplete = method(
      client,
      "reminders.incomplete",
    ) as Reminders["incomplete"];
    this.completed = method(
      client,
      "reminders.completed",
    ) as Reminders["completed"];
  }

  // No-param methods
  authorized(options?: {
    timeout?: number;
  }): Promise<RemindersAuthorizedResult> {
    return this.client.call(
      "reminders.authorized",
      {} as Record<string, never>,
      options,
    );
  }

  lists(options?: { timeout?: number }): Promise<RemindersListsResult> {
    return this.client.call(
      "reminders.lists",
      {} as Record<string, never>,
      options,
    );
  }

  requestFullAccess(options?: {
    timeout?: number;
  }): Promise<RemindersAuthorizedResult> {
    return this.client.call(
      "reminders.request_full_access",
      {} as Record<string, never>,
      options,
    );
  }

  // Prepare methods for batch API
  prepareAuthorized(): PreparedCall<"reminders.authorized"> {
    return {
      method: "reminders.authorized",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as RemindersAuthorizedResult,
    };
  }

  prepareLists(): PreparedCall<"reminders.lists"> {
    return {
      method: "reminders.lists",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as RemindersListsResult,
    };
  }
}
