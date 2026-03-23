import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  RemindersAuthorizedResult,
  RemindersListsResult,
  RemindersItemsParams,
  RemindersItemsResult,
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

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;
    this.items = method(client, "reminders.items") as Reminders["items"];
  }

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
