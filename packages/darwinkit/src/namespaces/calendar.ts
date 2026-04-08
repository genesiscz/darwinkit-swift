import type { DarwinKitClient } from "../client.js";
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
  CalendarSaveEventParams,
  CalendarSaveResult,
  CalendarRemoveEventParams,
  CalendarOkResult,
  CalendarItemParams,
  CalendarItemResult,
  CalendarItemsExternalParams,
  CalendarItemsExternalResult,
  CalendarSourcesResult,
  CalendarSourceParams,
  SourceInfo,
  CalendarSaveCalendarParams,
  CalendarRemoveCalendarParams,
  CalendarInfo,
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

export class Calendar {
  // Read methods
  readonly events: {
    (
      params: CalendarEventsParams,
      options?: { timeout?: number },
    ): Promise<CalendarEventsResult>;
    prepare(params: CalendarEventsParams): PreparedCall<"calendar.events">;
  };
  readonly event: {
    (
      params: CalendarEventParams,
      options?: { timeout?: number },
    ): Promise<CalendarEventInfo>;
    prepare(params: CalendarEventParams): PreparedCall<"calendar.event">;
  };

  // Write methods
  readonly saveEvent: {
    (
      params: CalendarSaveEventParams,
      options?: { timeout?: number },
    ): Promise<CalendarSaveResult>;
    prepare(
      params: CalendarSaveEventParams,
    ): PreparedCall<"calendar.save_event">;
  };
  readonly removeEvent: {
    (
      params: CalendarRemoveEventParams,
      options?: { timeout?: number },
    ): Promise<CalendarOkResult>;
    prepare(
      params: CalendarRemoveEventParams,
    ): PreparedCall<"calendar.remove_event">;
  };
  readonly calendarItem: {
    (
      params: CalendarItemParams,
      options?: { timeout?: number },
    ): Promise<CalendarItemResult>;
    prepare(
      params: CalendarItemParams,
    ): PreparedCall<"calendar.calendar_item">;
  };
  readonly calendarItemsExternal: {
    (
      params: CalendarItemsExternalParams,
      options?: { timeout?: number },
    ): Promise<CalendarItemsExternalResult>;
    prepare(
      params: CalendarItemsExternalParams,
    ): PreparedCall<"calendar.calendar_items_external">;
  };
  readonly source: {
    (
      params: CalendarSourceParams,
      options?: { timeout?: number },
    ): Promise<SourceInfo>;
    prepare(params: CalendarSourceParams): PreparedCall<"calendar.source">;
  };
  readonly saveCalendar: {
    (
      params: CalendarSaveCalendarParams,
      options?: { timeout?: number },
    ): Promise<CalendarSaveResult>;
    prepare(
      params: CalendarSaveCalendarParams,
    ): PreparedCall<"calendar.save_calendar">;
  };
  readonly removeCalendar: {
    (
      params: CalendarRemoveCalendarParams,
      options?: { timeout?: number },
    ): Promise<CalendarOkResult>;
    prepare(
      params: CalendarRemoveCalendarParams,
    ): PreparedCall<"calendar.remove_calendar">;
  };

  private client: DarwinKitClient;

  constructor(client: DarwinKitClient) {
    this.client = client;

    // Read methods
    this.events = method(client, "calendar.events") as Calendar["events"];
    this.event = method(client, "calendar.event") as Calendar["event"];

    // Write methods
    this.saveEvent = method(
      client,
      "calendar.save_event",
    ) as Calendar["saveEvent"];
    this.removeEvent = method(
      client,
      "calendar.remove_event",
    ) as Calendar["removeEvent"];
    this.calendarItem = method(
      client,
      "calendar.calendar_item",
    ) as Calendar["calendarItem"];
    this.calendarItemsExternal = method(
      client,
      "calendar.calendar_items_external",
    ) as Calendar["calendarItemsExternal"];
    this.source = method(client, "calendar.source") as Calendar["source"];
    this.saveCalendar = method(
      client,
      "calendar.save_calendar",
    ) as Calendar["saveCalendar"];
    this.removeCalendar = method(
      client,
      "calendar.remove_calendar",
    ) as Calendar["removeCalendar"];
  }

  // No-param methods
  authorized(options?: {
    timeout?: number;
  }): Promise<CalendarAuthorizedResult> {
    return this.client.call(
      "calendar.authorized",
      {} as Record<string, never>,
      options,
    );
  }

  calendars(options?: { timeout?: number }): Promise<CalendarCalendarsResult> {
    return this.client.call(
      "calendar.calendars",
      {} as Record<string, never>,
      options,
    );
  }

  sources(options?: { timeout?: number }): Promise<CalendarSourcesResult> {
    return this.client.call(
      "calendar.sources",
      {} as Record<string, never>,
      options,
    );
  }

  delegateSources(options?: {
    timeout?: number;
  }): Promise<CalendarSourcesResult> {
    return this.client.call(
      "calendar.delegate_sources",
      {} as Record<string, never>,
      options,
    );
  }

  defaultCalendarForEvents(options?: {
    timeout?: number;
  }): Promise<CalendarInfo | null> {
    return this.client.call(
      "calendar.default_calendar_events",
      {} as Record<string, never>,
      options,
    );
  }

  defaultCalendarForReminders(options?: {
    timeout?: number;
  }): Promise<CalendarInfo | null> {
    return this.client.call(
      "calendar.default_calendar_reminders",
      {} as Record<string, never>,
      options,
    );
  }

  commit(options?: { timeout?: number }): Promise<CalendarOkResult> {
    return this.client.call(
      "calendar.commit",
      {} as Record<string, never>,
      options,
    );
  }

  reset(options?: { timeout?: number }): Promise<CalendarOkResult> {
    return this.client.call(
      "calendar.reset",
      {} as Record<string, never>,
      options,
    );
  }

  refreshSources(options?: { timeout?: number }): Promise<CalendarOkResult> {
    return this.client.call(
      "calendar.refresh_sources",
      {} as Record<string, never>,
      options,
    );
  }

  requestWriteOnlyAccess(options?: {
    timeout?: number;
  }): Promise<CalendarAuthorizedResult> {
    return this.client.call(
      "calendar.request_write_only_access",
      {} as Record<string, never>,
      options,
    );
  }

  // Prepare methods for batch API
  prepareAuthorized(): PreparedCall<"calendar.authorized"> {
    return {
      method: "calendar.authorized",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as CalendarAuthorizedResult,
    };
  }

  prepareCalendars(): PreparedCall<"calendar.calendars"> {
    return {
      method: "calendar.calendars",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as CalendarCalendarsResult,
    };
  }

  prepareSources(): PreparedCall<"calendar.sources"> {
    return {
      method: "calendar.sources",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as CalendarSourcesResult,
    };
  }
}
