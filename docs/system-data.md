# Contacts, Calendar & Reminders

Read-only access to the user's contacts, calendars, and reminders through Apple's Contacts, EventKit, and Reminders frameworks. All data stays on-device -- nothing leaves the machine.

**Requirements:** macOS 14+ (Sonoma). The `darwinkit` binary must have Contacts, Calendars, and/or Reminders permissions granted via System Settings > Privacy & Security.

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// Each namespace auto-connects on first call
const { contacts } = await dk.contacts.list()
const { events }   = await dk.calendar.events({
  start_date: "2026-03-01T00:00:00Z",
  end_date:   "2026-03-31T23:59:59Z",
})
const { reminders } = await dk.reminders.items({ filter: "incomplete" })

dk.close()
```

---

## Authorization

Every namespace exposes an `.authorized()` method that checks the current TCC (Transparency, Consent, and Control) status **without** triggering a permission prompt. The first actual data call (`.list()`, `.events()`, etc.) triggers the macOS permission dialog if the status is `notDetermined`.

```typescript
const { status, authorized } = await dk.contacts.authorized()

if (status === "notDetermined") {
  // First data call will trigger the system permission dialog
  const { contacts } = await dk.contacts.list({ limit: 1 })
}

if (status === "denied") {
  console.error(
    "Contacts access denied. Grant permission in " +
    "System Settings > Privacy & Security > Contacts."
  )
}
```

### Authorization status values

| Namespace | Possible `status` values |
|-----------|--------------------------|
| Contacts  | `"authorized"`, `"denied"`, `"restricted"`, `"notDetermined"` |
| Calendar  | `"fullAccess"`, `"writeOnly"`, `"denied"`, `"restricted"`, `"notDetermined"` |
| Reminders | `"fullAccess"`, `"denied"`, `"restricted"`, `"notDetermined"` |

All three return an `authorized: boolean` convenience flag that is `true` only when the status permits read access.

### Handling denied access

When authorization is denied, data calls throw a `DarwinKitError` with code `-32002` (`PERMISSION_DENIED`):

```typescript
import { DarwinKitError } from "@genesiscz/darwinkit"

try {
  await dk.contacts.list()
} catch (err) {
  if (err instanceof DarwinKitError && err.isPermissionDenied) {
    // Guide the user to System Settings
    console.error("Please grant Contacts access in System Settings.")
  }
}
```

---

## Contacts

Read contacts from the system address book via Apple's Contacts framework (`CNContactStore`).

### contacts.authorized()

Check the current authorization status.

```typescript
const { status, authorized } = await dk.contacts.authorized()
```

**Returns:** `ContactsAuthorizedResult`

| Field | Type | Description |
|-------|------|-------------|
| `status` | `"authorized" \| "denied" \| "restricted" \| "notDetermined"` | TCC authorization status |
| `authorized` | `boolean` | `true` if read access is granted |

### contacts.list(params?)

Retrieve all contacts, optionally capped by `limit`.

```typescript
// Get all contacts
const { contacts } = await dk.contacts.list()

// Get the first 50
const { contacts: first50 } = await dk.contacts.list({ limit: 50 })
```

**Parameters:** `ContactsListParams` (all optional)

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | `number` | all | Maximum number of contacts to return |

**Returns:** `ContactsListResult`

| Field | Type | Description |
|-------|------|-------------|
| `contacts` | `ContactInfo[]` | Array of contact records |

### contacts.get(params)

Fetch a single contact by its unique identifier.

```typescript
const contact = await dk.contacts.get({
  identifier: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
})

console.log(contact.given_name, contact.family_name)
console.log(contact.email_addresses)
console.log(contact.phone_numbers)
```

**Parameters:** `ContactsGetParams`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `identifier` | `string` | yes | The contact's unique identifier (from a previous `.list()` or `.search()` call) |

**Returns:** `ContactInfo` -- a single contact record (see [ContactInfo shape](#contactinfo) below).

If no contact matches the identifier, a `DarwinKitError` is thrown.

### contacts.search(params)

Search contacts by name, email, phone number, or organization.

```typescript
const { contacts } = await dk.contacts.search({ query: "John" })

// Limit search results
const { contacts: top3 } = await dk.contacts.search({
  query: "Apple",
  limit: 3,
})
```

**Parameters:** `ContactsSearchParams`

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `query` | `string` | yes | -- | Search string matched against name, email, phone, and organization |
| `limit` | `number` | no | all | Maximum results to return |

**Returns:** `ContactsSearchResult`

| Field | Type | Description |
|-------|------|-------------|
| `contacts` | `ContactInfo[]` | Matching contacts |

### ContactInfo

Every contact record has the following shape:

```typescript
interface ContactInfo {
  identifier: string
  given_name: string
  family_name: string
  organization_name: string
  email_addresses: { label: string; value: string }[]
  phone_numbers: { label: string; value: string }[]
  postal_addresses: {
    label: string
    street: string
    city: string
    state: string
    postal_code: string
    country: string
  }[]
  birthday?: string          // ISO 8601 date, e.g. "1990-06-15"
  thumbnail_image_base64?: string  // Base64-encoded JPEG thumbnail
}
```

---

## Calendar

Read calendars and events from Apple's EventKit (`EKEventStore`). Supports iCloud, Google (CalDAV), Exchange, local, subscription, and birthday calendars.

### calendar.authorized()

Check the current authorization status.

```typescript
const { status, authorized } = await dk.calendar.authorized()
```

**Returns:** `CalendarAuthorizedResult`

| Field | Type | Description |
|-------|------|-------------|
| `status` | `"fullAccess" \| "writeOnly" \| "denied" \| "restricted" \| "notDetermined"` | TCC authorization status |
| `authorized` | `boolean` | `true` if read access is granted |

> **Note:** macOS 14 introduced granular calendar permissions. A status of `"writeOnly"` means the app can create events but cannot read existing ones.

### calendar.calendars()

List all calendars the user has configured.

```typescript
const { calendars } = await dk.calendar.calendars()

for (const cal of calendars) {
  console.log(`${cal.title} (${cal.type}) - ${cal.color}`)
}
```

**Returns:** `CalendarCalendarsResult`

| Field | Type | Description |
|-------|------|-------------|
| `calendars` | `CalendarInfo[]` | All configured calendars |

Each `CalendarInfo` has:

| Field | Type | Description |
|-------|------|-------------|
| `identifier` | `string` | Unique calendar identifier |
| `title` | `string` | Calendar display name (e.g. "Work", "Personal") |
| `type` | `"local" \| "calDAV" \| "exchange" \| "subscription" \| "birthday" \| "unknown"` | Calendar source type |
| `color` | `string` | Hex color string (e.g. `"#FF6961"`) |
| `is_immutable` | `boolean` | Whether the calendar is read-only |
| `allows_content_modifications` | `boolean` | Whether events can be added/modified |

### calendar.events(params)

Query events within a date range, optionally filtered to specific calendars.

```typescript
// All events this week
const now = new Date()
const weekLater = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000)

const { events } = await dk.calendar.events({
  start_date: now.toISOString(),
  end_date: weekLater.toISOString(),
})

for (const event of events) {
  console.log(`${event.title}: ${event.start_date} - ${event.end_date}`)
  if (event.location) console.log(`  Location: ${event.location}`)
}
```

```typescript
// Events from a specific calendar only
const { calendars } = await dk.calendar.calendars()
const workCal = calendars.find(c => c.title === "Work")

if (workCal) {
  const { events } = await dk.calendar.events({
    start_date: "2026-03-01T00:00:00Z",
    end_date: "2026-03-31T23:59:59Z",
    calendar_identifiers: [workCal.identifier],
  })
}
```

**Parameters:** `CalendarEventsParams`

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `start_date` | `string` | yes | -- | ISO 8601 datetime for range start |
| `end_date` | `string` | yes | -- | ISO 8601 datetime for range end |
| `calendar_identifiers` | `string[]` | no | all calendars | Filter to events from these calendars only |

**Returns:** `CalendarEventsResult`

| Field | Type | Description |
|-------|------|-------------|
| `events` | `CalendarEventInfo[]` | Events within the specified range |

### calendar.event(params)

Fetch a single event by its identifier.

```typescript
const event = await dk.calendar.event({
  identifier: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
})

console.log(event.title, event.is_all_day)
console.log(event.notes)
```

**Parameters:** `CalendarEventParams`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `identifier` | `string` | yes | The event's unique identifier |

**Returns:** `CalendarEventInfo`

| Field | Type | Description |
|-------|------|-------------|
| `identifier` | `string` | Unique event identifier |
| `title` | `string` | Event title |
| `start_date` | `string` | ISO 8601 start datetime |
| `end_date` | `string` | ISO 8601 end datetime |
| `is_all_day` | `boolean` | Whether this is an all-day event |
| `location` | `string?` | Location string, if set |
| `notes` | `string?` | Event notes/description |
| `calendar_identifier` | `string` | Identifier of the parent calendar |
| `calendar_title` | `string` | Title of the parent calendar |
| `url` | `string?` | Associated URL, if set |

---

## Reminders

Read reminder lists and items from Apple's Reminders framework (`EKEventStore` with entity type `.reminder`).

### reminders.authorized()

Check the current authorization status.

```typescript
const { status, authorized } = await dk.reminders.authorized()
```

**Returns:** `RemindersAuthorizedResult`

| Field | Type | Description |
|-------|------|-------------|
| `status` | `"fullAccess" \| "denied" \| "restricted" \| "notDetermined"` | TCC authorization status |
| `authorized` | `boolean` | `true` if read access is granted |

### reminders.lists()

List all reminder lists.

```typescript
const { lists } = await dk.reminders.lists()

for (const list of lists) {
  console.log(`${list.title} (${list.color})`)
}
```

**Returns:** `RemindersListsResult`

| Field | Type | Description |
|-------|------|-------------|
| `lists` | `ReminderListInfo[]` | All reminder lists |

Each `ReminderListInfo` has:

| Field | Type | Description |
|-------|------|-------------|
| `identifier` | `string` | Unique list identifier |
| `title` | `string` | List display name (e.g. "Groceries", "Work") |
| `color` | `string` | Hex color string |

### reminders.items(params?)

Fetch reminders, optionally filtered by completion status and/or specific lists.

```typescript
// All reminders
const { reminders } = await dk.reminders.items()

// Only incomplete reminders
const { reminders: todo } = await dk.reminders.items({
  filter: "incomplete",
})

// Completed reminders from a specific list
const { lists } = await dk.reminders.lists()
const groceries = lists.find(l => l.title === "Groceries")

if (groceries) {
  const { reminders: done } = await dk.reminders.items({
    filter: "completed",
    list_identifiers: [groceries.identifier],
  })
}
```

**Parameters:** `RemindersItemsParams` (all optional)

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `filter` | `"completed" \| "incomplete"` | all | Filter by completion status |
| `list_identifiers` | `string[]` | all lists | Filter to reminders from these lists only |

**Returns:** `RemindersItemsResult`

| Field | Type | Description |
|-------|------|-------------|
| `reminders` | `ReminderInfo[]` | Matching reminders |

Each `ReminderInfo` has:

| Field | Type | Description |
|-------|------|-------------|
| `identifier` | `string` | Unique reminder identifier |
| `title` | `string` | Reminder title |
| `is_completed` | `boolean` | Whether the reminder is marked complete |
| `completion_date` | `string?` | ISO 8601 datetime when completed |
| `due_date` | `string?` | ISO 8601 datetime when due |
| `priority` | `number` | Priority (0 = none, 1 = high, 5 = medium, 9 = low) |
| `notes` | `string?` | Additional notes |
| `list_identifier` | `string` | Identifier of the parent list |
| `list_title` | `string` | Title of the parent list |

---

## Batch Operations

All namespace methods support `.prepare()` for use with `dk.batch()`, which fires multiple requests concurrently:

```typescript
const [authContacts, authCalendar, authReminders] = await dk.batch(
  dk.contacts.prepareAuthorized(),
  dk.calendar.prepareAuthorized(),
  dk.reminders.prepareAuthorized(),
)
// TypeScript infers:
// [ContactsAuthorizedResult, CalendarAuthorizedResult, RemindersAuthorizedResult]

console.log("Contacts:", authContacts.status)
console.log("Calendar:", authCalendar.status)
console.log("Reminders:", authReminders.status)
```

Data methods also support `.prepare()`:

```typescript
const [contactResult, eventResult, reminderResult] = await dk.batch(
  dk.contacts.search.prepare({ query: "John" }),
  dk.calendar.events.prepare({
    start_date: "2026-03-23T00:00:00Z",
    end_date: "2026-03-24T00:00:00Z",
  }),
  dk.reminders.items.prepare({ filter: "incomplete" }),
)

console.log(contactResult.contacts)
console.log(eventResult.events)
console.log(reminderResult.reminders)
```

---

## Error Handling

All methods throw `DarwinKitError` on failure. The error codes relevant to these namespaces:

| Code | Constant | Getter | Meaning |
|------|----------|--------|---------|
| `-32002` | `PERMISSION_DENIED` | `err.isPermissionDenied` | User denied access in System Settings |
| `-32003` | `OS_VERSION_TOO_OLD` | `err.isOSVersionTooOld` | macOS version does not support this method |
| `-32001` | `FRAMEWORK_UNAVAILABLE` | `err.isFrameworkUnavailable` | Required Apple framework not available |
| `-32602` | `INVALID_PARAMS` | -- | Invalid or missing parameters |

```typescript
import { DarwinKitError } from "@genesiscz/darwinkit"

async function safeContactLookup(dk: DarwinKit, query: string) {
  try {
    return await dk.contacts.search({ query })
  } catch (err) {
    if (!(err instanceof DarwinKitError)) throw err

    if (err.isPermissionDenied) {
      console.error("Contacts permission denied. Open System Settings > Privacy & Security > Contacts.")
      return { contacts: [] }
    }
    if (err.isOSVersionTooOld) {
      console.error("Contacts require macOS 14+. Please update your system.")
      return { contacts: [] }
    }

    throw err
  }
}
```

---

## Privacy & TCC Considerations

Apple's Transparency, Consent, and Control (TCC) framework governs access to Contacts, Calendar, and Reminders data. Key points:

1. **First access triggers a system dialog.** The user sees a macOS permission prompt the first time your app calls a data method. Until the user responds, the call blocks.

2. **Denial is sticky.** Once denied, subsequent calls throw `PERMISSION_DENIED`. The user must manually grant access in System Settings > Privacy & Security.

3. **Terminal apps inherit their parent's permissions.** When running from Terminal.app, the TCC prompt appears for Terminal itself, not your script. If Terminal already has Contacts access, your script inherits it.

4. **Sandboxed apps need entitlements.** If distributing as a sandboxed `.app`, you must add the appropriate entitlements:
   - `com.apple.security.personal-information.addressbook` (Contacts)
   - `com.apple.security.personal-information.calendars` (Calendar)
   - `com.apple.security.personal-information.reminders` (Reminders -- macOS 14+ uses the calendars entitlement for Reminders too via EventKit)

5. **Check before accessing.** Use `.authorized()` to check the current status without triggering the prompt. This lets you show a custom explanation before the system dialog appears.

```typescript
async function ensureContactsAccess(dk: DarwinKit): Promise<boolean> {
  const { status } = await dk.contacts.authorized()

  switch (status) {
    case "authorized":
      return true
    case "notDetermined":
      // Will trigger the system permission dialog
      try {
        await dk.contacts.list({ limit: 1 })
        return true
      } catch {
        return false
      }
    case "denied":
    case "restricted":
      return false
  }
}
```

---

## Practical Examples

### Contact Lookup for AI Assistants

Build a tool that lets an AI assistant resolve contact references from natural language:

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function resolveContact(naturalQuery: string) {
  // Search by the query the AI extracted from conversation
  const { contacts } = await dk.contacts.search({
    query: naturalQuery,
    limit: 5,
  })

  if (contacts.length === 0) {
    return { found: false, message: `No contacts matching "${naturalQuery}"` }
  }

  return {
    found: true,
    contacts: contacts.map(c => ({
      name: `${c.given_name} ${c.family_name}`.trim(),
      organization: c.organization_name,
      emails: c.email_addresses.map(e => e.value),
      phones: c.phone_numbers.map(p => p.value),
    })),
  }
}

// AI asks: "What's Sarah's email?"
const result = await resolveContact("Sarah")
console.log(result)
// {
//   found: true,
//   contacts: [
//     { name: "Sarah Connor", organization: "Cyberdyne", emails: ["sarah@example.com"], phones: ["+1-555-0199"] }
//   ]
// }

dk.close()
```

### Calendar-Aware Scheduling

Check availability before suggesting meeting times:

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function findFreeSlots(date: string, workStartHour = 9, workEndHour = 17) {
  const startOfDay = `${date}T0${workStartHour}:00:00`
  const endOfDay   = `${date}T${workEndHour}:00:00`

  const { events } = await dk.calendar.events({
    start_date: startOfDay,
    end_date: endOfDay,
  })

  // Filter out all-day events for slot calculation
  const timedEvents = events
    .filter(e => !e.is_all_day)
    .map(e => ({
      title: e.title,
      start: new Date(e.start_date),
      end: new Date(e.end_date),
    }))
    .sort((a, b) => a.start.getTime() - b.start.getTime())

  // Find gaps between events
  const freeSlots: { start: Date; end: Date; durationMinutes: number }[] = []
  let cursor = new Date(startOfDay)

  for (const event of timedEvents) {
    if (cursor < event.start) {
      const durationMinutes = (event.start.getTime() - cursor.getTime()) / 60_000
      if (durationMinutes >= 30) {
        freeSlots.push({
          start: new Date(cursor),
          end: event.start,
          durationMinutes,
        })
      }
    }
    if (event.end > cursor) {
      cursor = event.end
    }
  }

  // Check gap after last event
  const endTime = new Date(endOfDay)
  if (cursor < endTime) {
    const durationMinutes = (endTime.getTime() - cursor.getTime()) / 60_000
    if (durationMinutes >= 30) {
      freeSlots.push({
        start: new Date(cursor),
        end: endTime,
        durationMinutes,
      })
    }
  }

  return { date, freeSlots, totalEvents: events.length }
}

const availability = await findFreeSlots("2026-03-24")
console.log(`${availability.totalEvents} events, ${availability.freeSlots.length} free slots:`)
for (const slot of availability.freeSlots) {
  console.log(
    `  ${slot.start.toLocaleTimeString()} - ${slot.end.toLocaleTimeString()} ` +
    `(${slot.durationMinutes} min)`
  )
}

dk.close()
```

### Reminder Integration

Sync incomplete reminders into an external task tracker:

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function exportRemindersAsMarkdown() {
  const { lists } = await dk.reminders.lists()
  const { reminders } = await dk.reminders.items({ filter: "incomplete" })

  // Group reminders by list
  const grouped = new Map<string, typeof reminders>()
  for (const reminder of reminders) {
    const list = grouped.get(reminder.list_title) ?? []
    list.push(reminder)
    grouped.set(reminder.list_title, list)
  }

  // Generate markdown
  const lines: string[] = ["# Open Reminders", ""]

  for (const [listTitle, items] of grouped) {
    lines.push(`## ${listTitle}`, "")
    const sorted = items.sort((a, b) => a.priority - b.priority)
    for (const item of sorted) {
      const priority = item.priority === 1 ? " (!!!)"
        : item.priority === 5 ? " (!)"
        : ""
      const due = item.due_date
        ? ` -- due ${new Date(item.due_date).toLocaleDateString()}`
        : ""
      lines.push(`- [ ] ${item.title}${priority}${due}`)
      if (item.notes) {
        lines.push(`  > ${item.notes}`)
      }
    }
    lines.push("")
  }

  return lines.join("\n")
}

const markdown = await exportRemindersAsMarkdown()
console.log(markdown)

dk.close()
```

### Building a Personal CRM

Combine contacts, calendar, and reminders to build a relationship tracker:

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

interface PersonContext {
  contact: {
    name: string
    email: string | null
    phone: string | null
    organization: string
  }
  recentMeetings: {
    title: string
    date: string
    location?: string
  }[]
  pendingReminders: {
    title: string
    due?: string
  }[]
}

async function getPersonContext(name: string): Promise<PersonContext | null> {
  // Step 1: Find the contact
  const { contacts } = await dk.contacts.search({ query: name, limit: 1 })
  if (contacts.length === 0) return null

  const person = contacts[0]
  const fullName = `${person.given_name} ${person.family_name}`.trim()

  // Step 2: Find recent meetings mentioning this person (last 30 days)
  const now = new Date()
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)

  const [eventResult, reminderResult] = await dk.batch(
    dk.calendar.events.prepare({
      start_date: thirtyDaysAgo.toISOString(),
      end_date: now.toISOString(),
    }),
    dk.reminders.items.prepare({ filter: "incomplete" }),
  )

  // Filter events that mention the person's name in title or notes
  const relevantEvents = eventResult.events.filter(
    e =>
      e.title.toLowerCase().includes(name.toLowerCase()) ||
      e.notes?.toLowerCase().includes(name.toLowerCase())
  )

  // Filter reminders that mention the person
  const relevantReminders = reminderResult.reminders.filter(
    r =>
      r.title.toLowerCase().includes(name.toLowerCase()) ||
      r.notes?.toLowerCase().includes(name.toLowerCase())
  )

  return {
    contact: {
      name: fullName,
      email: person.email_addresses[0]?.value ?? null,
      phone: person.phone_numbers[0]?.value ?? null,
      organization: person.organization_name,
    },
    recentMeetings: relevantEvents.map(e => ({
      title: e.title,
      date: e.start_date,
      location: e.location,
    })),
    pendingReminders: relevantReminders.map(r => ({
      title: r.title,
      due: r.due_date,
    })),
  }
}

const ctx = await getPersonContext("Sarah")
if (ctx) {
  console.log(`--- ${ctx.contact.name} (${ctx.contact.organization}) ---`)
  console.log(`Email: ${ctx.contact.email}`)
  console.log(`Phone: ${ctx.contact.phone}`)
  console.log(`\nRecent meetings: ${ctx.recentMeetings.length}`)
  for (const m of ctx.recentMeetings) {
    console.log(`  ${m.title} on ${new Date(m.date).toLocaleDateString()}`)
  }
  console.log(`\nPending reminders: ${ctx.pendingReminders.length}`)
  for (const r of ctx.pendingReminders) {
    console.log(`  ${r.title}${r.due ? ` (due ${new Date(r.due).toLocaleDateString()})` : ""}`)
  }
}

dk.close()
```

### Daily Briefing

Aggregate today's schedule, pending reminders, and birthday contacts into a single summary:

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

async function dailyBriefing() {
  const today = new Date()
  const startOfDay = new Date(today)
  startOfDay.setHours(0, 0, 0, 0)
  const endOfDay = new Date(today)
  endOfDay.setHours(23, 59, 59, 999)

  const [eventResult, reminderResult] = await dk.batch(
    dk.calendar.events.prepare({
      start_date: startOfDay.toISOString(),
      end_date: endOfDay.toISOString(),
    }),
    dk.reminders.items.prepare({ filter: "incomplete" }),
  )

  const allDayEvents = eventResult.events.filter(e => e.is_all_day)
  const timedEvents = eventResult.events
    .filter(e => !e.is_all_day)
    .sort((a, b) => a.start_date.localeCompare(b.start_date))

  // Reminders due today or overdue
  const dueToday = reminderResult.reminders.filter(r => {
    if (!r.due_date) return false
    const due = new Date(r.due_date)
    return due <= endOfDay
  })

  console.log(`=== Daily Briefing for ${today.toLocaleDateString()} ===\n`)

  if (allDayEvents.length > 0) {
    console.log("All-day events:")
    for (const e of allDayEvents) {
      console.log(`  ${e.title} (${e.calendar_title})`)
    }
    console.log()
  }

  console.log(`Schedule (${timedEvents.length} events):`)
  for (const e of timedEvents) {
    const start = new Date(e.start_date).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    })
    const end = new Date(e.end_date).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    })
    const location = e.location ? ` @ ${e.location}` : ""
    console.log(`  ${start} - ${end}  ${e.title}${location}`)
  }

  if (dueToday.length > 0) {
    console.log(`\nDue today (${dueToday.length} reminders):`)
    for (const r of dueToday) {
      const overdue = new Date(r.due_date!) < startOfDay ? " [OVERDUE]" : ""
      console.log(`  - ${r.title} (${r.list_title})${overdue}`)
    }
  }
}

await dailyBriefing()
dk.close()
```
