import type { DarwinKitClient } from "../client.js";
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  ContactsAuthorizedResult,
  ContactsListParams,
  ContactsListResult,
  ContactsGetParams,
  ContactInfo,
  ContactsSearchParams,
  ContactsSearchResult,
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

export class Contacts {
  readonly list: {
    (
      params?: ContactsListParams,
      options?: { timeout?: number },
    ): Promise<ContactsListResult>;
    prepare(params?: ContactsListParams): PreparedCall<"contacts.list">;
  };
  readonly get: {
    (
      params: ContactsGetParams,
      options?: { timeout?: number },
    ): Promise<ContactInfo>;
    prepare(params: ContactsGetParams): PreparedCall<"contacts.get">;
  };
  readonly search: {
    (
      params: ContactsSearchParams,
      options?: { timeout?: number },
    ): Promise<ContactsSearchResult>;
    prepare(params: ContactsSearchParams): PreparedCall<"contacts.search">;
  };

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;
    this.list = method(client, "contacts.list") as Contacts["list"];
    this.get = method(client, "contacts.get") as Contacts["get"];
    this.search = method(client, "contacts.search") as Contacts["search"];
  }

  authorized(options?: {
    timeout?: number;
  }): Promise<ContactsAuthorizedResult> {
    return this.client.call(
      "contacts.authorized",
      {} as Record<string, never>,
      options,
    );
  }

  prepareAuthorized(): PreparedCall<"contacts.authorized"> {
    return {
      method: "contacts.authorized",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as ContactsAuthorizedResult,
    };
  }
}
