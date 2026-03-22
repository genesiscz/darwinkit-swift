import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  CalendarAuthorizedResult,
  CalendarCalendarsResult,
  CalendarEventsParams,
  CalendarEventsResult,
  CalendarEventParams,
  CalendarEventInfo,
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

export class Calendar {
  readonly events: {
    (
      params: CalendarEventsParams,
      options?: { timeout?: number },
    ): Promise<CalendarEventsResult>
    prepare(params: CalendarEventsParams): PreparedCall<"calendar.events">
  }
  readonly event: {
    (
      params: CalendarEventParams,
      options?: { timeout?: number },
    ): Promise<CalendarEventInfo>
    prepare(params: CalendarEventParams): PreparedCall<"calendar.event">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.events = method(client, "calendar.events") as Calendar["events"]
    this.event = method(client, "calendar.event") as Calendar["event"]
  }

  authorized(options?: { timeout?: number }): Promise<CalendarAuthorizedResult> {
    return this.client.call(
      "calendar.authorized",
      {} as Record<string, never>,
      options,
    )
  }

  calendars(options?: { timeout?: number }): Promise<CalendarCalendarsResult> {
    return this.client.call(
      "calendar.calendars",
      {} as Record<string, never>,
      options,
    )
  }

  prepareAuthorized(): PreparedCall<"calendar.authorized"> {
    return {
      method: "calendar.authorized",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as CalendarAuthorizedResult,
    }
  }

  prepareCalendars(): PreparedCall<"calendar.calendars"> {
    return {
      method: "calendar.calendars",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as CalendarCalendarsResult,
    }
  }
}
