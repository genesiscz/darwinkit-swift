# System Data Access Implementation Plan

> **GitHub Issue:** https://github.com/genesiscz/darwinkit-swift/issues/8


> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add read-only access to Contacts, Calendar, and Reminders via `contacts.*`, `calendar.*`, and `reminders.*` JSON-RPC namespaces.

**Architecture:** Three provider protocols (ContactsProvider, CalendarProvider, RemindersProvider) with Apple implementations using CNContactStore and EKEventStore. Three handler classes route JSON-RPC methods to providers. Three TS SDK namespace classes expose typed methods to consumers. Mock providers enable unit testing without system access.

**Tech Stack:** Swift (Contacts framework, EventKit framework), TypeScript (TS SDK namespaces), Swift Testing (`@Test` macros), macOS 14+

---

## Codebase Orientation

### Key Paths

| What | Path |
|------|------|
| Swift sources | `packages/darwinkit-swift/Sources/DarwinKitCore/` |
| Handler pattern | `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CoreMLHandler.swift` |
| Provider pattern | `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CoreMLProvider.swift` |
| Handler registration | `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` |
| Tests | `packages/darwinkit-swift/Tests/DarwinKitCoreTests/` |
| Package manifest | `packages/darwinkit-swift/Package.swift` |
| TS SDK types | `packages/darwinkit/src/types.ts` |
| TS SDK namespaces | `packages/darwinkit/src/namespaces/` |
| TS SDK client | `packages/darwinkit/src/client.ts` |
| TS SDK barrel | `packages/darwinkit/src/index.ts` |

### Architecture Pattern (follow exactly)

1. **Provider protocol** defines framework operations (e.g., `CoreMLProvider`)
2. **Apple implementation** wraps the real framework (e.g., `AppleCoreMLProvider`)
3. **Handler** implements `MethodHandler` protocol, parses JSON-RPC params, delegates to provider
4. **DarwinKit.swift** registers handler in `buildServerWithRouter()` and `buildRouter()`
5. **Mock provider** in test file enables unit testing without real framework access
6. **TS types** in `types.ts` define params/result interfaces + MethodMap entries
7. **TS namespace** class wraps `client.call()` with typed methods

### Protocol Details

The `MethodHandler` protocol (defined in `MethodRouter.swift`):

```swift
public protocol MethodHandler {
    var methods: [String] { get }
    func handle(_ request: JsonRpcRequest) throws -> Any
    func capability(for method: String) -> MethodCapability
}
```

JSON-RPC params are accessed via helper methods on `JsonRpcRequest`:
- `request.requireString("key")` -- throws if missing
- `request.string("key")` -- optional string
- `request.int("key")` -- optional int
- `request.bool("key")` -- optional bool
- `request.stringArray("key")` -- optional string array

Handlers return `[String: Any]` dictionaries that get serialized to JSON automatically via `AnyCodable`.

Error types (from `Protocol.swift`):
- `JsonRpcError.invalidParams("message")` -- missing/bad params
- `JsonRpcError.permissionDenied("message")` -- TCC denied
- `JsonRpcError.frameworkUnavailable("message")` -- framework not available
- `JsonRpcError.internalError("message")` -- unexpected errors

### Test Commands

```bash
# Run all Swift tests
cd packages/darwinkit-swift && swift test

# Run specific test suite
cd packages/darwinkit-swift && swift test --filter ContactsHandlerTests

# TypeScript type-check
cd packages/darwinkit && bunx tsgo --noEmit
```

---

## Task 1: ContactsProvider Protocol + Mock

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/ContactsProvider.swift`
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift`

### Step 1: Write the provider protocol and data structures

Create `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/ContactsProvider.swift`:

```swift
import Contacts
import Foundation

// MARK: - Data Types

public struct ContactInfo {
    public let identifier: String
    public let givenName: String
    public let familyName: String
    public let organizationName: String
    public let emailAddresses: [ContactEmailAddress]
    public let phoneNumbers: [ContactPhoneNumber]
    public let postalAddresses: [ContactPostalAddress]
    public let birthday: String?  // ISO 8601 date (yyyy-MM-dd) or nil
    public let thumbnailImageBase64: String?

    public init(
        identifier: String, givenName: String, familyName: String,
        organizationName: String, emailAddresses: [ContactEmailAddress],
        phoneNumbers: [ContactPhoneNumber], postalAddresses: [ContactPostalAddress],
        birthday: String?, thumbnailImageBase64: String?
    ) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.organizationName = organizationName
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
        self.postalAddresses = postalAddresses
        self.birthday = birthday
        self.thumbnailImageBase64 = thumbnailImageBase64
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "given_name": givenName,
            "family_name": familyName,
            "organization_name": organizationName,
            "email_addresses": emailAddresses.map { $0.toDict() },
            "phone_numbers": phoneNumbers.map { $0.toDict() },
            "postal_addresses": postalAddresses.map { $0.toDict() },
        ]
        if let birthday = birthday {
            dict["birthday"] = birthday
        }
        if let thumb = thumbnailImageBase64 {
            dict["thumbnail_image_base64"] = thumb
        }
        return dict
    }
}

public struct ContactEmailAddress {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public func toDict() -> [String: Any] {
        ["label": label, "value": value]
    }
}

public struct ContactPhoneNumber {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public func toDict() -> [String: Any] {
        ["label": label, "value": value]
    }
}

public struct ContactPostalAddress {
    public let label: String
    public let street: String
    public let city: String
    public let state: String
    public let postalCode: String
    public let country: String

    public init(label: String, street: String, city: String, state: String, postalCode: String, country: String) {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }

    public func toDict() -> [String: Any] {
        [
            "label": label,
            "street": street,
            "city": city,
            "state": state,
            "postal_code": postalCode,
            "country": country,
        ]
    }
}

public struct ContactsAuthorizationResult {
    public let status: String  // "authorized" | "denied" | "restricted" | "notDetermined"
    public let authorized: Bool

    public init(status: String, authorized: Bool) {
        self.status = status
        self.authorized = authorized
    }

    public func toDict() -> [String: Any] {
        ["status": status, "authorized": authorized]
    }
}

// MARK: - Provider Protocol

public protocol ContactsProvider {
    /// Check/request contacts authorization. Returns current status.
    func checkAuthorization() throws -> ContactsAuthorizationResult

    /// List contacts with optional limit. Returns array of contacts.
    func listContacts(limit: Int?) throws -> [ContactInfo]

    /// Get a single contact by identifier.
    func getContact(identifier: String) throws -> ContactInfo

    /// Search contacts by query string (matches name, email, phone).
    func searchContacts(query: String, limit: Int?) throws -> [ContactInfo]
}

// MARK: - Apple Implementation

public final class AppleContactsProvider: ContactsProvider {
    private let store = CNContactStore()

    private let fetchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    public init() {}

    public func checkAuthorization() throws -> ContactsAuthorizationResult {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            return ContactsAuthorizationResult(status: "authorized", authorized: true)
        case .denied:
            return ContactsAuthorizationResult(status: "denied", authorized: false)
        case .restricted:
            return ContactsAuthorizationResult(status: "restricted", authorized: false)
        case .notDetermined:
            // Request access synchronously
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            store.requestAccess(for: .contacts) { success, _ in
                granted = success
                semaphore.signal()
            }
            semaphore.wait()
            let newStatus = granted ? "authorized" : "denied"
            return ContactsAuthorizationResult(status: newStatus, authorized: granted)
        @unknown default:
            return ContactsAuthorizationResult(status: "notDetermined", authorized: false)
        }
    }

    public func listContacts(limit: Int?) throws -> [ContactInfo] {
        try ensureAuthorized()

        let request = CNContactFetchRequest(keysToFetch: fetchKeys)
        request.sortOrder = .givenName

        var contacts: [ContactInfo] = []
        let maxCount = limit ?? Int.max

        try store.enumerateContacts(with: request) { contact, stop in
            contacts.append(self.mapContact(contact))
            if contacts.count >= maxCount {
                stop.pointee = true
            }
        }

        return contacts
    }

    public func getContact(identifier: String) throws -> ContactInfo {
        try ensureAuthorized()

        do {
            let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: fetchKeys)
            return mapContact(contact)
        } catch {
            throw JsonRpcError.invalidParams("Contact not found: \(identifier)")
        }
    }

    public func searchContacts(query: String, limit: Int?) throws -> [ContactInfo] {
        try ensureAuthorized()

        let predicate = CNContact.predicateForContacts(matchingName: query)
        do {
            let results = try store.unifiedContacts(matching: predicate, keysToFetch: fetchKeys)
            let maxCount = limit ?? Int.max
            return Array(results.prefix(maxCount)).map { mapContact($0) }
        } catch {
            throw JsonRpcError.internalError("Contact search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            throw JsonRpcError.permissionDenied(
                "Contacts access not authorized. Call contacts.authorized first. Current status: \(status.rawValue)"
            )
        }
    }

    private func mapContact(_ contact: CNContact) -> ContactInfo {
        let emails = contact.emailAddresses.map { labeled in
            ContactEmailAddress(
                label: CNLabeledValue<NSString>.localizedString(forLabel: labeled.label ?? "other"),
                value: labeled.value as String
            )
        }

        let phones = contact.phoneNumbers.map { labeled in
            ContactPhoneNumber(
                label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: labeled.label ?? "other"),
                value: labeled.value.stringValue
            )
        }

        let addresses = contact.postalAddresses.map { labeled in
            let addr = labeled.value
            return ContactPostalAddress(
                label: CNLabeledValue<CNPostalAddress>.localizedString(forLabel: labeled.label ?? "other"),
                street: addr.street,
                city: addr.city,
                state: addr.state,
                postalCode: addr.postalCode,
                country: addr.country
            )
        }

        var birthdayStr: String? = nil
        if let bday = contact.birthday {
            var components = bday
            components.calendar = Calendar(identifier: .gregorian)
            if let date = components.date {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                birthdayStr = formatter.string(from: date)
            }
        }

        var thumbnailBase64: String? = nil
        if let imageData = contact.thumbnailImageData {
            thumbnailBase64 = imageData.base64EncodedString()
        }

        return ContactInfo(
            identifier: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            organizationName: contact.organizationName,
            emailAddresses: emails,
            phoneNumbers: phones,
            postalAddresses: addresses,
            birthday: birthdayStr,
            thumbnailImageBase64: thumbnailBase64
        )
    }
}
```

### Step 2: Write the mock provider and test skeleton

Create `packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift`:

```swift
import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockContactsProvider: ContactsProvider {
    var contacts: [ContactInfo] = []
    var authResult = ContactsAuthorizationResult(status: "authorized", authorized: true)
    var shouldThrow: JsonRpcError? = nil

    func checkAuthorization() throws -> ContactsAuthorizationResult {
        if let err = shouldThrow { throw err }
        return authResult
    }

    func listContacts(limit: Int?) throws -> [ContactInfo] {
        if let err = shouldThrow { throw err }
        let maxCount = limit ?? Int.max
        return Array(contacts.prefix(maxCount))
    }

    func getContact(identifier: String) throws -> ContactInfo {
        if let err = shouldThrow { throw err }
        guard let contact = contacts.first(where: { $0.identifier == identifier }) else {
            throw JsonRpcError.invalidParams("Contact not found: \(identifier)")
        }
        return contact
    }

    func searchContacts(query: String, limit: Int?) throws -> [ContactInfo] {
        if let err = shouldThrow { throw err }
        let lowered = query.lowercased()
        let matches = contacts.filter {
            $0.givenName.lowercased().contains(lowered) ||
            $0.familyName.lowercased().contains(lowered)
        }
        let maxCount = limit ?? Int.max
        return Array(matches.prefix(maxCount))
    }
}

// MARK: - Test Helpers

private func makeSampleContact(
    identifier: String = "contact-1",
    givenName: String = "John",
    familyName: String = "Appleseed"
) -> ContactInfo {
    ContactInfo(
        identifier: identifier,
        givenName: givenName,
        familyName: familyName,
        organizationName: "Apple",
        emailAddresses: [ContactEmailAddress(label: "work", value: "john@apple.com")],
        phoneNumbers: [ContactPhoneNumber(label: "mobile", value: "+1-555-0100")],
        postalAddresses: [ContactPostalAddress(
            label: "home", street: "1 Infinite Loop",
            city: "Cupertino", state: "CA", postalCode: "95014", country: "US"
        )],
        birthday: "1976-04-01",
        thumbnailImageBase64: nil
    )
}

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests (placeholder -- handler tests added in Task 2)
```

### Step 3: Verify it compiles

Run: `cd packages/darwinkit-swift && swift build 2>&1 | tail -5`
Expected: Build succeeds (no test runs yet, just compilation)

### Step 4: Commit

```bash
git add \
  packages/darwinkit-swift/Sources/DarwinKitCore/Providers/ContactsProvider.swift \
  packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift
git commit -m "feat(contacts): add ContactsProvider protocol, Apple implementation, and mock"
```

---

## Task 2: ContactsHandler + Unit Tests

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/ContactsHandler.swift`
- Modify: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift`

### Step 1: Write the handler tests

Append to `packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift` (replace the placeholder comment):

```swift
// MARK: - Tests

@Suite("Contacts Handler")
struct ContactsHandlerTests {

    // MARK: - contacts.authorized

    @Test("authorized returns status when authorized")
    func authorizedSuccess() throws {
        let handler = ContactsHandler(provider: MockContactsProvider())
        let request = makeRequest(method: "contacts.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "authorized")
        #expect(result["authorized"] as? Bool == true)
    }

    @Test("authorized returns denied status")
    func authorizedDenied() throws {
        var mock = MockContactsProvider()
        mock.authResult = ContactsAuthorizationResult(status: "denied", authorized: false)
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "denied")
        #expect(result["authorized"] as? Bool == false)
    }

    // MARK: - contacts.list

    @Test("list returns empty array when no contacts")
    func listEmpty() throws {
        let handler = ContactsHandler(provider: MockContactsProvider())
        let request = makeRequest(method: "contacts.list")
        let result = try handler.handle(request) as! [String: Any]
        let contacts = result["contacts"] as! [[String: Any]]

        #expect(contacts.isEmpty)
    }

    @Test("list returns contacts")
    func listWithContacts() throws {
        var mock = MockContactsProvider()
        mock.contacts = [makeSampleContact()]
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.list")
        let result = try handler.handle(request) as! [String: Any]
        let contacts = result["contacts"] as! [[String: Any]]

        #expect(contacts.count == 1)
        #expect(contacts[0]["given_name"] as? String == "John")
        #expect(contacts[0]["family_name"] as? String == "Appleseed")
    }

    @Test("list respects limit param")
    func listWithLimit() throws {
        var mock = MockContactsProvider()
        mock.contacts = [
            makeSampleContact(identifier: "c1", givenName: "Alice"),
            makeSampleContact(identifier: "c2", givenName: "Bob"),
            makeSampleContact(identifier: "c3", givenName: "Charlie"),
        ]
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.list", params: ["limit": 2])
        let result = try handler.handle(request) as! [String: Any]
        let contacts = result["contacts"] as! [[String: Any]]

        #expect(contacts.count == 2)
    }

    // MARK: - contacts.get

    @Test("get returns single contact by identifier")
    func getSuccess() throws {
        var mock = MockContactsProvider()
        mock.contacts = [makeSampleContact(identifier: "abc-123")]
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.get", params: ["identifier": "abc-123"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["identifier"] as? String == "abc-123")
        #expect(result["given_name"] as? String == "John")
    }

    @Test("get throws on missing identifier param")
    func getMissingId() {
        let handler = ContactsHandler(provider: MockContactsProvider())
        let request = makeRequest(method: "contacts.get")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("get throws when contact not found")
    func getNotFound() {
        let handler = ContactsHandler(provider: MockContactsProvider())
        let request = makeRequest(method: "contacts.get", params: ["identifier": "nonexistent"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - contacts.search

    @Test("search finds contacts by name")
    func searchByName() throws {
        var mock = MockContactsProvider()
        mock.contacts = [
            makeSampleContact(identifier: "c1", givenName: "Alice", familyName: "Smith"),
            makeSampleContact(identifier: "c2", givenName: "Bob", familyName: "Jones"),
        ]
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.search", params: ["query": "alice"])
        let result = try handler.handle(request) as! [String: Any]
        let contacts = result["contacts"] as! [[String: Any]]

        #expect(contacts.count == 1)
        #expect(contacts[0]["given_name"] as? String == "Alice")
    }

    @Test("search throws on missing query")
    func searchMissingQuery() {
        let handler = ContactsHandler(provider: MockContactsProvider())
        let request = makeRequest(method: "contacts.search")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("search respects limit")
    func searchWithLimit() throws {
        var mock = MockContactsProvider()
        mock.contacts = [
            makeSampleContact(identifier: "c1", givenName: "Alice", familyName: "A"),
            makeSampleContact(identifier: "c2", givenName: "Alice", familyName: "B"),
            makeSampleContact(identifier: "c3", givenName: "Alice", familyName: "C"),
        ]
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.search", params: ["query": "alice", "limit": 1])
        let result = try handler.handle(request) as! [String: Any]
        let contacts = result["contacts"] as! [[String: Any]]

        #expect(contacts.count == 1)
    }

    // MARK: - Method registration

    @Test("handler registers all 4 contacts methods")
    func methodRegistration() {
        let handler = ContactsHandler(provider: MockContactsProvider())
        let expected: Set<String> = [
            "contacts.authorized", "contacts.list", "contacts.get", "contacts.search"
        ]
        #expect(Set(handler.methods) == expected)
    }

    // MARK: - Error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockContactsProvider()
        mock.shouldThrow = .permissionDenied("Contacts access denied")
        let handler = ContactsHandler(provider: mock)
        let request = makeRequest(method: "contacts.list")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
```

### Step 2: Run tests to verify they fail

Run: `cd packages/darwinkit-swift && swift test --filter ContactsHandlerTests 2>&1 | tail -10`
Expected: FAIL -- `ContactsHandler` not found (doesn't exist yet)

### Step 3: Write the handler implementation

Create `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/ContactsHandler.swift`:

```swift
import Foundation

/// Handles all contacts.* methods: list, get, search, authorized.
public final class ContactsHandler: MethodHandler {
    private let provider: ContactsProvider

    public var methods: [String] {
        ["contacts.authorized", "contacts.list", "contacts.get", "contacts.search"]
    }

    public init(provider: ContactsProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "contacts.authorized":
            return try handleAuthorized(request)
        case "contacts.list":
            return try handleList(request)
        case "contacts.get":
            return try handleGet(request)
        case "contacts.search":
            return try handleSearch(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Contacts permission")
    }

    // MARK: - Method Implementations

    private func handleAuthorized(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.checkAuthorization()
        return result.toDict()
    }

    private func handleList(_ request: JsonRpcRequest) throws -> Any {
        let limit = request.int("limit")
        let contacts = try provider.listContacts(limit: limit)
        return ["contacts": contacts.map { $0.toDict() }] as [String: Any]
    }

    private func handleGet(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let contact = try provider.getContact(identifier: identifier)
        return contact.toDict()
    }

    private func handleSearch(_ request: JsonRpcRequest) throws -> Any {
        let query = try request.requireString("query")
        let limit = request.int("limit")
        let contacts = try provider.searchContacts(query: query, limit: limit)
        return ["contacts": contacts.map { $0.toDict() }] as [String: Any]
    }
}
```

### Step 4: Run tests to verify they pass

Run: `cd packages/darwinkit-swift && swift test --filter ContactsHandlerTests 2>&1 | tail -10`
Expected: All 12 tests PASS

### Step 5: Commit

```bash
git add \
  packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/ContactsHandler.swift \
  packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift
git commit -m "feat(contacts): add ContactsHandler with full test coverage"
```

---

## Task 3: CalendarProvider Protocol + Mock

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CalendarProvider.swift`
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift`

### Step 1: Write the provider protocol and data structures

Create `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CalendarProvider.swift`:

```swift
import EventKit
import Foundation

// MARK: - Data Types

public struct CalendarInfo {
    public let identifier: String
    public let title: String
    public let type: String  // "local" | "calDAV" | "exchange" | "subscription" | "birthday"
    public let color: String  // hex color string e.g. "#FF0000"
    public let isImmutable: Bool
    public let allowsContentModifications: Bool

    public init(
        identifier: String, title: String, type: String,
        color: String, isImmutable: Bool, allowsContentModifications: Bool
    ) {
        self.identifier = identifier
        self.title = title
        self.type = type
        self.color = color
        self.isImmutable = isImmutable
        self.allowsContentModifications = allowsContentModifications
    }

    public func toDict() -> [String: Any] {
        [
            "identifier": identifier,
            "title": title,
            "type": type,
            "color": color,
            "is_immutable": isImmutable,
            "allows_content_modifications": allowsContentModifications,
        ]
    }
}

public struct CalendarEventInfo {
    public let identifier: String
    public let title: String
    public let startDate: String  // ISO 8601
    public let endDate: String    // ISO 8601
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let calendarIdentifier: String
    public let calendarTitle: String
    public let url: String?

    public init(
        identifier: String, title: String, startDate: String, endDate: String,
        isAllDay: Bool, location: String?, notes: String?,
        calendarIdentifier: String, calendarTitle: String, url: String?
    ) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.url = url
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "title": title,
            "start_date": startDate,
            "end_date": endDate,
            "is_all_day": isAllDay,
            "calendar_identifier": calendarIdentifier,
            "calendar_title": calendarTitle,
        ]
        if let location = location { dict["location"] = location }
        if let notes = notes { dict["notes"] = notes }
        if let url = url { dict["url"] = url }
        return dict
    }
}

public struct CalendarAuthorizationResult {
    public let status: String  // "fullAccess" | "writeOnly" | "denied" | "restricted" | "notDetermined"
    public let authorized: Bool

    public init(status: String, authorized: Bool) {
        self.status = status
        self.authorized = authorized
    }

    public func toDict() -> [String: Any] {
        ["status": status, "authorized": authorized]
    }
}

// MARK: - Provider Protocol

public protocol CalendarProvider {
    /// Check/request calendar authorization. Returns current status.
    func checkAuthorization() throws -> CalendarAuthorizationResult

    /// List all calendars for events.
    func listCalendars() throws -> [CalendarInfo]

    /// Fetch events in a date range, optionally filtered by calendar identifiers.
    func fetchEvents(startDate: String, endDate: String, calendarIdentifiers: [String]?) throws -> [CalendarEventInfo]

    /// Get a single event by identifier.
    func getEvent(identifier: String) throws -> CalendarEventInfo
}

// MARK: - Apple Implementation

public final class AppleCalendarProvider: CalendarProvider {
    private let store = EKEventStore()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    public func checkAuthorization() throws -> CalendarAuthorizationResult {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            return CalendarAuthorizationResult(status: "fullAccess", authorized: true)
        case .writeOnly:
            return CalendarAuthorizationResult(status: "writeOnly", authorized: false)
        case .denied:
            return CalendarAuthorizationResult(status: "denied", authorized: false)
        case .restricted:
            return CalendarAuthorizationResult(status: "restricted", authorized: false)
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            if #available(macOS 14, *) {
                store.requestFullAccessToEvents { success, _ in
                    granted = success
                    semaphore.signal()
                }
            } else {
                store.requestAccess(to: .event) { success, _ in
                    granted = success
                    semaphore.signal()
                }
            }
            semaphore.wait()
            let newStatus = granted ? "fullAccess" : "denied"
            return CalendarAuthorizationResult(status: newStatus, authorized: granted)
        @unknown default:
            return CalendarAuthorizationResult(status: "notDetermined", authorized: false)
        }
    }

    public func listCalendars() throws -> [CalendarInfo] {
        try ensureAuthorized()
        return store.calendars(for: .event).map { mapCalendar($0) }
    }

    public func fetchEvents(startDate: String, endDate: String, calendarIdentifiers: [String]?) throws -> [CalendarEventInfo] {
        try ensureAuthorized()

        guard let start = isoFormatter.date(from: startDate) else {
            throw JsonRpcError.invalidParams("Invalid start_date ISO 8601 format: \(startDate)")
        }
        guard let end = isoFormatter.date(from: endDate) else {
            throw JsonRpcError.invalidParams("Invalid end_date ISO 8601 format: \(endDate)")
        }

        var calendars: [EKCalendar]? = nil
        if let ids = calendarIdentifiers {
            calendars = ids.compactMap { store.calendar(withIdentifier: $0) }
            if calendars?.isEmpty == true {
                calendars = nil  // fall back to all calendars
            }
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        return events.map { mapEvent($0) }
    }

    public func getEvent(identifier: String) throws -> CalendarEventInfo {
        try ensureAuthorized()

        guard let event = store.event(withIdentifier: identifier) else {
            throw JsonRpcError.invalidParams("Event not found: \(identifier)")
        }

        return mapEvent(event)
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            throw JsonRpcError.permissionDenied(
                "Calendar access not authorized. Call calendar.authorized first."
            )
        }
    }

    private func mapCalendar(_ cal: EKCalendar) -> CalendarInfo {
        let typeName: String
        switch cal.type {
        case .local: typeName = "local"
        case .calDAV: typeName = "calDAV"
        case .exchange: typeName = "exchange"
        case .subscription: typeName = "subscription"
        case .birthday: typeName = "birthday"
        @unknown default: typeName = "unknown"
        }

        let color = cal.cgColor.flatMap { cgColor -> String? in
            guard let components = cgColor.components, cgColor.numberOfComponents >= 3 else { return nil }
            let r = Int(components[0] * 255)
            let g = Int(components[1] * 255)
            let b = Int(components[2] * 255)
            return String(format: "#%02X%02X%02X", r, g, b)
        } ?? "#000000"

        return CalendarInfo(
            identifier: cal.calendarIdentifier,
            title: cal.title,
            type: typeName,
            color: color,
            isImmutable: cal.isImmutable,
            allowsContentModifications: cal.allowsContentModifications
        )
    }

    private func mapEvent(_ event: EKEvent) -> CalendarEventInfo {
        CalendarEventInfo(
            identifier: event.eventIdentifier,
            title: event.title ?? "",
            startDate: isoFormatter.string(from: event.startDate),
            endDate: isoFormatter.string(from: event.endDate),
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            url: event.url?.absoluteString
        )
    }
}
```

### Step 2: Write the mock provider and test helpers

Create `packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift`:

```swift
import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockCalendarProvider: CalendarProvider {
    var calendars: [CalendarInfo] = []
    var events: [CalendarEventInfo] = []
    var authResult = CalendarAuthorizationResult(status: "fullAccess", authorized: true)
    var shouldThrow: JsonRpcError? = nil

    func checkAuthorization() throws -> CalendarAuthorizationResult {
        if let err = shouldThrow { throw err }
        return authResult
    }

    func listCalendars() throws -> [CalendarInfo] {
        if let err = shouldThrow { throw err }
        return calendars
    }

    func fetchEvents(startDate: String, endDate: String, calendarIdentifiers: [String]?) throws -> [CalendarEventInfo] {
        if let err = shouldThrow { throw err }
        if let ids = calendarIdentifiers {
            return events.filter { ids.contains($0.calendarIdentifier) }
        }
        return events
    }

    func getEvent(identifier: String) throws -> CalendarEventInfo {
        if let err = shouldThrow { throw err }
        guard let event = events.first(where: { $0.identifier == identifier }) else {
            throw JsonRpcError.invalidParams("Event not found: \(identifier)")
        }
        return event
    }
}

// MARK: - Test Helpers

private func makeSampleCalendar(
    identifier: String = "cal-1",
    title: String = "Personal"
) -> CalendarInfo {
    CalendarInfo(
        identifier: identifier, title: title, type: "local",
        color: "#FF0000", isImmutable: false, allowsContentModifications: true
    )
}

private func makeSampleEvent(
    identifier: String = "evt-1",
    title: String = "Team Meeting",
    calendarIdentifier: String = "cal-1"
) -> CalendarEventInfo {
    CalendarEventInfo(
        identifier: identifier, title: title,
        startDate: "2026-03-22T10:00:00.000Z",
        endDate: "2026-03-22T11:00:00.000Z",
        isAllDay: false, location: "Conference Room A",
        notes: "Discuss quarterly goals",
        calendarIdentifier: calendarIdentifier,
        calendarTitle: "Personal", url: nil
    )
}

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests (placeholder -- handler tests added in Task 4)
```

### Step 3: Verify it compiles

Run: `cd packages/darwinkit-swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

### Step 4: Commit

```bash
git add \
  packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CalendarProvider.swift \
  packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift
git commit -m "feat(calendar): add CalendarProvider protocol, Apple implementation, and mock"
```

---

## Task 4: CalendarHandler + Unit Tests

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CalendarHandler.swift`
- Modify: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift`

### Step 1: Write the handler tests

Append to `packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift` (replace the placeholder comment):

```swift
// MARK: - Tests

@Suite("Calendar Handler")
struct CalendarHandlerTests {

    // MARK: - calendar.authorized

    @Test("authorized returns fullAccess status")
    func authorizedSuccess() throws {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "fullAccess")
        #expect(result["authorized"] as? Bool == true)
    }

    @Test("authorized returns denied status")
    func authorizedDenied() throws {
        var mock = MockCalendarProvider()
        mock.authResult = CalendarAuthorizationResult(status: "denied", authorized: false)
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "denied")
        #expect(result["authorized"] as? Bool == false)
    }

    // MARK: - calendar.calendars

    @Test("calendars returns empty array when none exist")
    func calendarsEmpty() throws {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.calendars")
        let result = try handler.handle(request) as! [String: Any]
        let calendars = result["calendars"] as! [[String: Any]]

        #expect(calendars.isEmpty)
    }

    @Test("calendars returns calendar list")
    func calendarsWithEntries() throws {
        var mock = MockCalendarProvider()
        mock.calendars = [makeSampleCalendar()]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.calendars")
        let result = try handler.handle(request) as! [String: Any]
        let calendars = result["calendars"] as! [[String: Any]]

        #expect(calendars.count == 1)
        #expect(calendars[0]["title"] as? String == "Personal")
        #expect(calendars[0]["type"] as? String == "local")
    }

    // MARK: - calendar.events

    @Test("events returns events in date range")
    func eventsSuccess() throws {
        var mock = MockCalendarProvider()
        mock.events = [makeSampleEvent()]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.events", params: [
            "start_date": "2026-03-22T00:00:00.000Z",
            "end_date": "2026-03-23T00:00:00.000Z",
        ])
        let result = try handler.handle(request) as! [String: Any]
        let events = result["events"] as! [[String: Any]]

        #expect(events.count == 1)
        #expect(events[0]["title"] as? String == "Team Meeting")
    }

    @Test("events throws on missing start_date")
    func eventsMissingStart() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.events", params: [
            "end_date": "2026-03-23T00:00:00.000Z"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("events throws on missing end_date")
    func eventsMissingEnd() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.events", params: [
            "start_date": "2026-03-22T00:00:00.000Z"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("events filters by calendar_identifiers")
    func eventsFilterByCalendar() throws {
        var mock = MockCalendarProvider()
        mock.events = [
            makeSampleEvent(identifier: "e1", calendarIdentifier: "cal-1"),
            makeSampleEvent(identifier: "e2", calendarIdentifier: "cal-2"),
        ]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.events", params: [
            "start_date": "2026-03-22T00:00:00.000Z",
            "end_date": "2026-03-23T00:00:00.000Z",
            "calendar_identifiers": ["cal-1"],
        ])
        let result = try handler.handle(request) as! [String: Any]
        let events = result["events"] as! [[String: Any]]

        #expect(events.count == 1)
        #expect(events[0]["identifier"] as? String == "e1")
    }

    // MARK: - calendar.event

    @Test("event returns single event by identifier")
    func eventSuccess() throws {
        var mock = MockCalendarProvider()
        mock.events = [makeSampleEvent(identifier: "evt-abc")]
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.event", params: ["identifier": "evt-abc"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["identifier"] as? String == "evt-abc")
        #expect(result["title"] as? String == "Team Meeting")
    }

    @Test("event throws on missing identifier")
    func eventMissingId() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.event")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("event throws when not found")
    func eventNotFound() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let request = makeRequest(method: "calendar.event", params: ["identifier": "nonexistent"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - Method registration

    @Test("handler registers all 4 calendar methods")
    func methodRegistration() {
        let handler = CalendarHandler(provider: MockCalendarProvider())
        let expected: Set<String> = [
            "calendar.authorized", "calendar.calendars", "calendar.events", "calendar.event"
        ]
        #expect(Set(handler.methods) == expected)
    }

    // MARK: - Error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockCalendarProvider()
        mock.shouldThrow = .permissionDenied("Calendar access denied")
        let handler = CalendarHandler(provider: mock)
        let request = makeRequest(method: "calendar.calendars")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
```

### Step 2: Run tests to verify they fail

Run: `cd packages/darwinkit-swift && swift test --filter CalendarHandlerTests 2>&1 | tail -10`
Expected: FAIL -- `CalendarHandler` not found

### Step 3: Write the handler implementation

Create `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CalendarHandler.swift`:

```swift
import Foundation

/// Handles all calendar.* methods: authorized, calendars, events, event.
public final class CalendarHandler: MethodHandler {
    private let provider: CalendarProvider

    public var methods: [String] {
        ["calendar.authorized", "calendar.calendars", "calendar.events", "calendar.event"]
    }

    public init(provider: CalendarProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "calendar.authorized":
            return try handleAuthorized(request)
        case "calendar.calendars":
            return try handleCalendars(request)
        case "calendar.events":
            return try handleEvents(request)
        case "calendar.event":
            return try handleEvent(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Calendar permission (macOS 14+)")
    }

    // MARK: - Method Implementations

    private func handleAuthorized(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.checkAuthorization()
        return result.toDict()
    }

    private func handleCalendars(_ request: JsonRpcRequest) throws -> Any {
        let calendars = try provider.listCalendars()
        return ["calendars": calendars.map { $0.toDict() }] as [String: Any]
    }

    private func handleEvents(_ request: JsonRpcRequest) throws -> Any {
        let startDate = try request.requireString("start_date")
        let endDate = try request.requireString("end_date")
        let calendarIdentifiers = request.stringArray("calendar_identifiers")
        let events = try provider.fetchEvents(
            startDate: startDate, endDate: endDate,
            calendarIdentifiers: calendarIdentifiers
        )
        return ["events": events.map { $0.toDict() }] as [String: Any]
    }

    private func handleEvent(_ request: JsonRpcRequest) throws -> Any {
        let identifier = try request.requireString("identifier")
        let event = try provider.getEvent(identifier: identifier)
        return event.toDict()
    }
}
```

### Step 4: Run tests to verify they pass

Run: `cd packages/darwinkit-swift && swift test --filter CalendarHandlerTests 2>&1 | tail -10`
Expected: All 12 tests PASS

### Step 5: Commit

```bash
git add \
  packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CalendarHandler.swift \
  packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift
git commit -m "feat(calendar): add CalendarHandler with full test coverage"
```

---

## Task 5: RemindersProvider Protocol + Mock

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/RemindersProvider.swift`
- Create: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift`

### Step 1: Write the provider protocol and data structures

Create `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/RemindersProvider.swift`:

```swift
import EventKit
import Foundation

// MARK: - Data Types

public struct ReminderListInfo {
    public let identifier: String
    public let title: String
    public let color: String  // hex color string

    public init(identifier: String, title: String, color: String) {
        self.identifier = identifier
        self.title = title
        self.color = color
    }

    public func toDict() -> [String: Any] {
        ["identifier": identifier, "title": title, "color": color]
    }
}

public struct ReminderInfo {
    public let identifier: String
    public let title: String
    public let isCompleted: Bool
    public let completionDate: String?  // ISO 8601 or nil
    public let dueDate: String?         // ISO 8601 or nil
    public let priority: Int            // 0 = none, 1 = high, 5 = medium, 9 = low
    public let notes: String?
    public let listIdentifier: String
    public let listTitle: String

    public init(
        identifier: String, title: String, isCompleted: Bool,
        completionDate: String?, dueDate: String?, priority: Int,
        notes: String?, listIdentifier: String, listTitle: String
    ) {
        self.identifier = identifier
        self.title = title
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
        self.listIdentifier = listIdentifier
        self.listTitle = listTitle
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "identifier": identifier,
            "title": title,
            "is_completed": isCompleted,
            "priority": priority,
            "list_identifier": listIdentifier,
            "list_title": listTitle,
        ]
        if let completionDate = completionDate { dict["completion_date"] = completionDate }
        if let dueDate = dueDate { dict["due_date"] = dueDate }
        if let notes = notes { dict["notes"] = notes }
        return dict
    }
}

public struct RemindersAuthorizationResult {
    public let status: String  // "fullAccess" | "denied" | "restricted" | "notDetermined"
    public let authorized: Bool

    public init(status: String, authorized: Bool) {
        self.status = status
        self.authorized = authorized
    }

    public func toDict() -> [String: Any] {
        ["status": status, "authorized": authorized]
    }
}

// MARK: - Provider Protocol

public protocol RemindersProvider {
    /// Check/request reminders authorization.
    func checkAuthorization() throws -> RemindersAuthorizationResult

    /// List all reminder lists (calendars of type .reminder).
    func listReminderLists() throws -> [ReminderListInfo]

    /// Fetch reminders with optional filter. Filter can be "completed", "incomplete", or nil for all.
    /// Optionally filter by list identifiers.
    func fetchReminders(filter: String?, listIdentifiers: [String]?) throws -> [ReminderInfo]
}

// MARK: - Apple Implementation

public final class AppleRemindersProvider: RemindersProvider {
    private let store = EKEventStore()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    public func checkAuthorization() throws -> RemindersAuthorizationResult {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess:
            return RemindersAuthorizationResult(status: "fullAccess", authorized: true)
        case .denied:
            return RemindersAuthorizationResult(status: "denied", authorized: false)
        case .restricted:
            return RemindersAuthorizationResult(status: "restricted", authorized: false)
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            if #available(macOS 14, *) {
                store.requestFullAccessToReminders { success, _ in
                    granted = success
                    semaphore.signal()
                }
            } else {
                store.requestAccess(to: .reminder) { success, _ in
                    granted = success
                    semaphore.signal()
                }
            }
            semaphore.wait()
            let newStatus = granted ? "fullAccess" : "denied"
            return RemindersAuthorizationResult(status: newStatus, authorized: granted)
        @unknown default:
            return RemindersAuthorizationResult(status: "notDetermined", authorized: false)
        }
    }

    public func listReminderLists() throws -> [ReminderListInfo] {
        try ensureAuthorized()
        return store.calendars(for: .reminder).map { cal in
            let color = cal.cgColor.flatMap { cgColor -> String? in
                guard let components = cgColor.components, cgColor.numberOfComponents >= 3 else { return nil }
                let r = Int(components[0] * 255)
                let g = Int(components[1] * 255)
                let b = Int(components[2] * 255)
                return String(format: "#%02X%02X%02X", r, g, b)
            } ?? "#000000"

            return ReminderListInfo(
                identifier: cal.calendarIdentifier,
                title: cal.title,
                color: color
            )
        }
    }

    public func fetchReminders(filter: String?, listIdentifiers: [String]?) throws -> [ReminderInfo] {
        try ensureAuthorized()

        var calendars: [EKCalendar]? = nil
        if let ids = listIdentifiers {
            calendars = ids.compactMap { store.calendar(withIdentifier: $0) }
            if calendars?.isEmpty == true {
                calendars = nil
            }
        }

        let predicate: NSPredicate
        switch filter {
        case "completed":
            predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil, ending: nil, calendars: calendars
            )
        case "incomplete":
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: calendars
            )
        default:
            predicate = store.predicateForReminders(in: calendars)
        }

        // fetchReminders is callback-based -- bridge to sync
        let semaphore = DispatchSemaphore(value: 0)
        var reminders: [EKReminder]? = nil

        store.fetchReminders(matching: predicate) { result in
            reminders = result
            semaphore.signal()
        }

        semaphore.wait()

        return (reminders ?? []).map { mapReminder($0) }
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else {
            throw JsonRpcError.permissionDenied(
                "Reminders access not authorized. Call reminders.authorized first."
            )
        }
    }

    private func mapReminder(_ reminder: EKReminder) -> ReminderInfo {
        var dueDateStr: String? = nil
        if let components = reminder.dueDateComponents,
           let date = Calendar.current.date(from: components) {
            dueDateStr = isoFormatter.string(from: date)
        }

        var completionDateStr: String? = nil
        if let date = reminder.completionDate {
            completionDateStr = isoFormatter.string(from: date)
        }

        return ReminderInfo(
            identifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            isCompleted: reminder.isCompleted,
            completionDate: completionDateStr,
            dueDate: dueDateStr,
            priority: reminder.priority,
            notes: reminder.notes,
            listIdentifier: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title
        )
    }
}
```

### Step 2: Write the mock provider and test helpers

Create `packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift`:

```swift
import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockRemindersProvider: RemindersProvider {
    var lists: [ReminderListInfo] = []
    var reminders: [ReminderInfo] = []
    var authResult = RemindersAuthorizationResult(status: "fullAccess", authorized: true)
    var shouldThrow: JsonRpcError? = nil

    func checkAuthorization() throws -> RemindersAuthorizationResult {
        if let err = shouldThrow { throw err }
        return authResult
    }

    func listReminderLists() throws -> [ReminderListInfo] {
        if let err = shouldThrow { throw err }
        return lists
    }

    func fetchReminders(filter: String?, listIdentifiers: [String]?) throws -> [ReminderInfo] {
        if let err = shouldThrow { throw err }

        var result = reminders

        // Filter by list
        if let ids = listIdentifiers {
            result = result.filter { ids.contains($0.listIdentifier) }
        }

        // Filter by completion status
        switch filter {
        case "completed":
            result = result.filter { $0.isCompleted }
        case "incomplete":
            result = result.filter { !$0.isCompleted }
        default:
            break
        }

        return result
    }
}

// MARK: - Test Helpers

private func makeSampleList(
    identifier: String = "list-1",
    title: String = "Groceries"
) -> ReminderListInfo {
    ReminderListInfo(identifier: identifier, title: title, color: "#34C759")
}

private func makeSampleReminder(
    identifier: String = "rem-1",
    title: String = "Buy milk",
    isCompleted: Bool = false,
    listIdentifier: String = "list-1"
) -> ReminderInfo {
    ReminderInfo(
        identifier: identifier, title: title,
        isCompleted: isCompleted,
        completionDate: isCompleted ? "2026-03-21T15:30:00.000Z" : nil,
        dueDate: "2026-03-22T17:00:00.000Z",
        priority: 0,
        notes: nil,
        listIdentifier: listIdentifier,
        listTitle: "Groceries"
    )
}

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests (placeholder -- handler tests added in Task 6)
```

### Step 3: Verify it compiles

Run: `cd packages/darwinkit-swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

### Step 4: Commit

```bash
git add \
  packages/darwinkit-swift/Sources/DarwinKitCore/Providers/RemindersProvider.swift \
  packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift
git commit -m "feat(reminders): add RemindersProvider protocol, Apple implementation, and mock"
```

---

## Task 6: RemindersHandler + Unit Tests

**Files:**
- Create: `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/RemindersHandler.swift`
- Modify: `packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift`

### Step 1: Write the handler tests

Append to `packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift` (replace the placeholder comment):

```swift
// MARK: - Tests

@Suite("Reminders Handler")
struct RemindersHandlerTests {

    // MARK: - reminders.authorized

    @Test("authorized returns fullAccess status")
    func authorizedSuccess() throws {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let request = makeRequest(method: "reminders.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "fullAccess")
        #expect(result["authorized"] as? Bool == true)
    }

    @Test("authorized returns denied status")
    func authorizedDenied() throws {
        var mock = MockRemindersProvider()
        mock.authResult = RemindersAuthorizationResult(status: "denied", authorized: false)
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.authorized")
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["status"] as? String == "denied")
        #expect(result["authorized"] as? Bool == false)
    }

    // MARK: - reminders.lists

    @Test("lists returns empty array when none exist")
    func listsEmpty() throws {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let request = makeRequest(method: "reminders.lists")
        let result = try handler.handle(request) as! [String: Any]
        let lists = result["lists"] as! [[String: Any]]

        #expect(lists.isEmpty)
    }

    @Test("lists returns reminder lists")
    func listsWithEntries() throws {
        var mock = MockRemindersProvider()
        mock.lists = [makeSampleList()]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.lists")
        let result = try handler.handle(request) as! [String: Any]
        let lists = result["lists"] as! [[String: Any]]

        #expect(lists.count == 1)
        #expect(lists[0]["title"] as? String == "Groceries")
        #expect(lists[0]["color"] as? String == "#34C759")
    }

    // MARK: - reminders.items

    @Test("items returns all reminders by default")
    func itemsAll() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", isCompleted: false),
            makeSampleReminder(identifier: "r2", isCompleted: true),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items")
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 2)
    }

    @Test("items filters by completed")
    func itemsCompleted() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", isCompleted: false),
            makeSampleReminder(identifier: "r2", isCompleted: true),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items", params: ["filter": "completed"])
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 1)
        #expect(items[0]["is_completed"] as? Bool == true)
    }

    @Test("items filters by incomplete")
    func itemsIncomplete() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", isCompleted: false),
            makeSampleReminder(identifier: "r2", isCompleted: true),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items", params: ["filter": "incomplete"])
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 1)
        #expect(items[0]["is_completed"] as? Bool == false)
    }

    @Test("items filters by list_identifiers")
    func itemsByList() throws {
        var mock = MockRemindersProvider()
        mock.reminders = [
            makeSampleReminder(identifier: "r1", listIdentifier: "list-1"),
            makeSampleReminder(identifier: "r2", listIdentifier: "list-2"),
        ]
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.items", params: [
            "list_identifiers": ["list-1"]
        ])
        let result = try handler.handle(request) as! [String: Any]
        let items = result["reminders"] as! [[String: Any]]

        #expect(items.count == 1)
        #expect(items[0]["identifier"] as? String == "r1")
    }

    // MARK: - Method registration

    @Test("handler registers all 3 reminders methods")
    func methodRegistration() {
        let handler = RemindersHandler(provider: MockRemindersProvider())
        let expected: Set<String> = [
            "reminders.authorized", "reminders.lists", "reminders.items"
        ]
        #expect(Set(handler.methods) == expected)
    }

    // MARK: - Error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockRemindersProvider()
        mock.shouldThrow = .permissionDenied("Reminders access denied")
        let handler = RemindersHandler(provider: mock)
        let request = makeRequest(method: "reminders.lists")

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
```

### Step 2: Run tests to verify they fail

Run: `cd packages/darwinkit-swift && swift test --filter RemindersHandlerTests 2>&1 | tail -10`
Expected: FAIL -- `RemindersHandler` not found

### Step 3: Write the handler implementation

Create `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/RemindersHandler.swift`:

```swift
import Foundation

/// Handles all reminders.* methods: authorized, lists, items.
public final class RemindersHandler: MethodHandler {
    private let provider: RemindersProvider

    public var methods: [String] {
        ["reminders.authorized", "reminders.lists", "reminders.items"]
    }

    public init(provider: RemindersProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "reminders.authorized":
            return try handleAuthorized(request)
        case "reminders.lists":
            return try handleLists(request)
        case "reminders.items":
            return try handleItems(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        MethodCapability(available: true, note: "Requires Reminders permission (macOS 14+)")
    }

    // MARK: - Method Implementations

    private func handleAuthorized(_ request: JsonRpcRequest) throws -> Any {
        let result = try provider.checkAuthorization()
        return result.toDict()
    }

    private func handleLists(_ request: JsonRpcRequest) throws -> Any {
        let lists = try provider.listReminderLists()
        return ["lists": lists.map { $0.toDict() }] as [String: Any]
    }

    private func handleItems(_ request: JsonRpcRequest) throws -> Any {
        let filter = request.string("filter")
        let listIdentifiers = request.stringArray("list_identifiers")
        let reminders = try provider.fetchReminders(filter: filter, listIdentifiers: listIdentifiers)
        return ["reminders": reminders.map { $0.toDict() }] as [String: Any]
    }
}
```

### Step 4: Run tests to verify they pass

Run: `cd packages/darwinkit-swift && swift test --filter RemindersHandlerTests 2>&1 | tail -10`
Expected: All 9 tests PASS

### Step 5: Commit

```bash
git add \
  packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/RemindersHandler.swift \
  packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift
git commit -m "feat(reminders): add RemindersHandler with full test coverage"
```

---

## Task 7: Register All Handlers in DarwinKit.swift

**Files:**
- Modify: `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift`

### Step 1: Add the three new handler registrations

In `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift`, modify `buildServerWithRouter()` and `buildRouter()` to register the new handlers.

In `buildServerWithRouter()`, add after the `router.register(AuthHandler())` line:

```swift
    router.register(ContactsHandler(provider: AppleContactsProvider()))
    router.register(CalendarHandler(provider: AppleCalendarProvider()))
    router.register(RemindersHandler(provider: AppleRemindersProvider()))
```

In `buildRouter()`, add after the `router.register(AuthHandler())` line:

```swift
    router.register(ContactsHandler(provider: AppleContactsProvider()))
    router.register(CalendarHandler(provider: AppleCalendarProvider()))
    router.register(RemindersHandler(provider: AppleRemindersProvider()))
```

The full updated file should look like:

```swift
import ArgumentParser
import DarwinKitCore
import Foundation

@main
struct DarwinKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "darwinkit",
        abstract: "Expose Apple's on-device ML frameworks via JSON-RPC over stdio.",
        version: JsonRpcServer.version,
        subcommands: [Serve.self, Query.self],
        defaultSubcommand: Serve.self
    )
}

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run in server mode -- reads JSON-RPC from stdin, writes responses to stdout."
    )

    mutating func run() {
        let server = buildServerWithRouter()
        server.start()
    }
}

struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a single JSON-RPC request and exit."
    )

    @Argument(help: "JSON-RPC request string")
    var json: String

    mutating func run() throws {
        let router = buildRouter()

        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8) else {
            throw ValidationError("Invalid UTF-8 input")
        }

        let request = try decoder.decode(JsonRpcRequest.self, from: data)
        let result = try router.dispatch(request)

        let response = JsonRpcResponse.success(id: request.id, result: result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let output = try encoder.encode(response)
        print(String(data: output, encoding: .utf8)!)
    }
}

/// Build server and router together so handlers can receive the server as NotificationSink.
func buildServerWithRouter() -> JsonRpcServer {
    let router = MethodRouter()
    let server = JsonRpcServer(router: router)

    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(CloudHandler(notificationSink: server))
    router.register(AuthHandler())
    router.register(ContactsHandler(provider: AppleContactsProvider()))
    router.register(CalendarHandler(provider: AppleCalendarProvider()))
    router.register(RemindersHandler(provider: AppleRemindersProvider()))

    return server
}

/// Central router factory -- all handlers registered here (for single-shot Query mode).
func buildRouter() -> MethodRouter {
    let router = MethodRouter()
    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    router.register(CoreMLHandler(provider: AppleCoreMLProvider()))
    router.register(CloudHandler())
    router.register(AuthHandler())
    router.register(ContactsHandler(provider: AppleContactsProvider()))
    router.register(CalendarHandler(provider: AppleCalendarProvider()))
    router.register(RemindersHandler(provider: AppleRemindersProvider()))
    return router
}
```

### Step 2: Verify it builds

Run: `cd packages/darwinkit-swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

### Step 3: Run all tests to make sure nothing is broken

Run: `cd packages/darwinkit-swift && swift test 2>&1 | tail -15`
Expected: All tests pass (including previously existing tests)

### Step 4: Commit

```bash
git add packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift
git commit -m "feat: register Contacts, Calendar, Reminders handlers in server"
```

---

## Task 8: TS SDK Types

**Files:**
- Modify: `packages/darwinkit/src/types.ts`

### Step 1: Add type definitions for all three namespaces

Append the following sections to `packages/darwinkit/src/types.ts` **before** the `MethodMap` interface (i.e., before the `// MethodMap` comment):

```typescript
// ---------------------------------------------------------------------------
// Contacts
// ---------------------------------------------------------------------------

export interface ContactEmailAddress {
  label: string
  value: string
}
export interface ContactPhoneNumber {
  label: string
  value: string
}
export interface ContactPostalAddress {
  label: string
  street: string
  city: string
  state: string
  postal_code: string
  country: string
}

export interface ContactInfo {
  identifier: string
  given_name: string
  family_name: string
  organization_name: string
  email_addresses: ContactEmailAddress[]
  phone_numbers: ContactPhoneNumber[]
  postal_addresses: ContactPostalAddress[]
  birthday?: string
  thumbnail_image_base64?: string
}

export interface ContactsAuthorizedResult {
  status: "authorized" | "denied" | "restricted" | "notDetermined"
  authorized: boolean
}
export interface ContactsListParams {
  limit?: number
}
export interface ContactsListResult {
  contacts: ContactInfo[]
}
export interface ContactsGetParams {
  identifier: string
}
export interface ContactsSearchParams {
  query: string
  limit?: number
}
export interface ContactsSearchResult {
  contacts: ContactInfo[]
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

export interface CalendarInfo {
  identifier: string
  title: string
  type: "local" | "calDAV" | "exchange" | "subscription" | "birthday" | "unknown"
  color: string
  is_immutable: boolean
  allows_content_modifications: boolean
}

export interface CalendarEventInfo {
  identifier: string
  title: string
  start_date: string
  end_date: string
  is_all_day: boolean
  location?: string
  notes?: string
  calendar_identifier: string
  calendar_title: string
  url?: string
}

export interface CalendarAuthorizedResult {
  status: "fullAccess" | "writeOnly" | "denied" | "restricted" | "notDetermined"
  authorized: boolean
}
export interface CalendarCalendarsResult {
  calendars: CalendarInfo[]
}
export interface CalendarEventsParams {
  start_date: string
  end_date: string
  calendar_identifiers?: string[]
}
export interface CalendarEventsResult {
  events: CalendarEventInfo[]
}
export interface CalendarEventParams {
  identifier: string
}

// ---------------------------------------------------------------------------
// Reminders
// ---------------------------------------------------------------------------

export interface ReminderListInfo {
  identifier: string
  title: string
  color: string
}

export interface ReminderInfo {
  identifier: string
  title: string
  is_completed: boolean
  completion_date?: string
  due_date?: string
  priority: number
  notes?: string
  list_identifier: string
  list_title: string
}

export interface RemindersAuthorizedResult {
  status: "fullAccess" | "denied" | "restricted" | "notDetermined"
  authorized: boolean
}
export interface RemindersListsResult {
  lists: ReminderListInfo[]
}
export interface RemindersItemsParams {
  filter?: "completed" | "incomplete"
  list_identifiers?: string[]
}
export interface RemindersItemsResult {
  reminders: ReminderInfo[]
}
```

### Step 2: Add MethodMap entries

Add the following entries to the `MethodMap` interface in `packages/darwinkit/src/types.ts`, inside the interface body (after the `coreml.embed_contextual_batch` entry):

```typescript
  // Contacts
  "contacts.authorized": {
    params: Record<string, never>
    result: ContactsAuthorizedResult
  }
  "contacts.list": {
    params: ContactsListParams
    result: ContactsListResult
  }
  "contacts.get": {
    params: ContactsGetParams
    result: ContactInfo
  }
  "contacts.search": {
    params: ContactsSearchParams
    result: ContactsSearchResult
  }
  // Calendar
  "calendar.authorized": {
    params: Record<string, never>
    result: CalendarAuthorizedResult
  }
  "calendar.calendars": {
    params: Record<string, never>
    result: CalendarCalendarsResult
  }
  "calendar.events": {
    params: CalendarEventsParams
    result: CalendarEventsResult
  }
  "calendar.event": {
    params: CalendarEventParams
    result: CalendarEventInfo
  }
  // Reminders
  "reminders.authorized": {
    params: Record<string, never>
    result: RemindersAuthorizedResult
  }
  "reminders.lists": {
    params: Record<string, never>
    result: RemindersListsResult
  }
  "reminders.items": {
    params: RemindersItemsParams
    result: RemindersItemsResult
  }
```

### Step 3: Run type-check

Run: `cd packages/darwinkit && bunx tsgo --noEmit 2>&1 | tail -5`
Expected: No errors

### Step 4: Commit

```bash
git add packages/darwinkit/src/types.ts
git commit -m "feat(sdk): add Contacts, Calendar, Reminders types and MethodMap entries"
```

---

## Task 9: TS SDK Contacts Namespace

**Files:**
- Create: `packages/darwinkit/src/namespaces/contacts.ts`

### Step 1: Write the namespace class

Create `packages/darwinkit/src/namespaces/contacts.ts`:

```typescript
import type { DarwinKitClient } from "../client.js"
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

export class Contacts {
  readonly list: {
    (
      params?: ContactsListParams,
      options?: { timeout?: number },
    ): Promise<ContactsListResult>
    prepare(params?: ContactsListParams): PreparedCall<"contacts.list">
  }
  readonly get: {
    (
      params: ContactsGetParams,
      options?: { timeout?: number },
    ): Promise<ContactInfo>
    prepare(params: ContactsGetParams): PreparedCall<"contacts.get">
  }
  readonly search: {
    (
      params: ContactsSearchParams,
      options?: { timeout?: number },
    ): Promise<ContactsSearchResult>
    prepare(params: ContactsSearchParams): PreparedCall<"contacts.search">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.list = method(client, "contacts.list") as Contacts["list"]
    this.get = method(client, "contacts.get") as Contacts["get"]
    this.search = method(client, "contacts.search") as Contacts["search"]
  }

  authorized(options?: { timeout?: number }): Promise<ContactsAuthorizedResult> {
    return this.client.call(
      "contacts.authorized",
      {} as Record<string, never>,
      options,
    )
  }

  prepareAuthorized(): PreparedCall<"contacts.authorized"> {
    return {
      method: "contacts.authorized",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as ContactsAuthorizedResult,
    }
  }
}
```

### Step 2: Run type-check

Run: `cd packages/darwinkit && bunx tsgo --noEmit 2>&1 | tail -5`
Expected: No errors

### Step 3: Commit

```bash
git add packages/darwinkit/src/namespaces/contacts.ts
git commit -m "feat(sdk): add Contacts namespace class"
```

---

## Task 10: TS SDK Calendar Namespace

**Files:**
- Create: `packages/darwinkit/src/namespaces/calendar.ts`

### Step 1: Write the namespace class

Create `packages/darwinkit/src/namespaces/calendar.ts`:

```typescript
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
```

### Step 2: Run type-check

Run: `cd packages/darwinkit && bunx tsgo --noEmit 2>&1 | tail -5`
Expected: No errors

### Step 3: Commit

```bash
git add packages/darwinkit/src/namespaces/calendar.ts
git commit -m "feat(sdk): add Calendar namespace class"
```

---

## Task 11: TS SDK Reminders Namespace

**Files:**
- Create: `packages/darwinkit/src/namespaces/reminders.ts`

### Step 1: Write the namespace class

Create `packages/darwinkit/src/namespaces/reminders.ts`:

```typescript
import type { DarwinKitClient } from "../client.js"
import type {
  MethodMap,
  MethodName,
  PreparedCall,
  RemindersAuthorizedResult,
  RemindersListsResult,
  RemindersItemsParams,
  RemindersItemsResult,
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

export class Reminders {
  readonly items: {
    (
      params?: RemindersItemsParams,
      options?: { timeout?: number },
    ): Promise<RemindersItemsResult>
    prepare(params?: RemindersItemsParams): PreparedCall<"reminders.items">
  }

  private client: DarwinKitClient

  constructor(client: DarwinKitClient) {
    this.client = client
    this.items = method(client, "reminders.items") as Reminders["items"]
  }

  authorized(options?: { timeout?: number }): Promise<RemindersAuthorizedResult> {
    return this.client.call(
      "reminders.authorized",
      {} as Record<string, never>,
      options,
    )
  }

  lists(options?: { timeout?: number }): Promise<RemindersListsResult> {
    return this.client.call(
      "reminders.lists",
      {} as Record<string, never>,
      options,
    )
  }

  prepareAuthorized(): PreparedCall<"reminders.authorized"> {
    return {
      method: "reminders.authorized",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as RemindersAuthorizedResult,
    }
  }

  prepareLists(): PreparedCall<"reminders.lists"> {
    return {
      method: "reminders.lists",
      params: {} as Record<string, never>,
      __brand: undefined as unknown as RemindersListsResult,
    }
  }
}
```

### Step 2: Run type-check

Run: `cd packages/darwinkit && bunx tsgo --noEmit 2>&1 | tail -5`
Expected: No errors

### Step 3: Commit

```bash
git add packages/darwinkit/src/namespaces/reminders.ts
git commit -m "feat(sdk): add Reminders namespace class"
```

---

## Task 12: Wire TS SDK Namespaces into Client + Barrel Exports

**Files:**
- Modify: `packages/darwinkit/src/client.ts`
- Modify: `packages/darwinkit/src/index.ts`

### Step 1: Add namespace imports and properties to client.ts

In `packages/darwinkit/src/client.ts`, add these imports after the existing namespace imports (after the `import { CoreML }` line):

```typescript
import { Contacts } from "./namespaces/contacts.js"
import { Calendar } from "./namespaces/calendar.js"
import { Reminders } from "./namespaces/reminders.js"
```

Add these properties to the `DarwinKit` class, after the existing `readonly coreml: CoreML` line:

```typescript
  readonly contacts: Contacts
  readonly calendar: Calendar
  readonly reminders: Reminders
```

Add these initializations in the constructor, after `this.coreml = new CoreML(this)`:

```typescript
    this.contacts = new Contacts(this)
    this.calendar = new Calendar(this)
    this.reminders = new Reminders(this)
```

### Step 2: Add barrel exports to index.ts

In `packages/darwinkit/src/index.ts`, add namespace exports after the existing `export { CoreML }` line:

```typescript
export { Contacts } from "./namespaces/contacts.js"
export { Calendar } from "./namespaces/calendar.js"
export { Reminders } from "./namespaces/reminders.js"
```

Add type exports to the existing `export type { ... }` block. After the `CoreMLOkResult,` line and before `// Notifications`:

```typescript
  // Contacts
  ContactEmailAddress,
  ContactPhoneNumber,
  ContactPostalAddress,
  ContactInfo,
  ContactsAuthorizedResult,
  ContactsListParams,
  ContactsListResult,
  ContactsGetParams,
  ContactsSearchParams,
  ContactsSearchResult,
  // Calendar
  CalendarInfo,
  CalendarEventInfo,
  CalendarAuthorizedResult,
  CalendarCalendarsResult,
  CalendarEventsParams,
  CalendarEventsResult,
  CalendarEventParams,
  // Reminders
  ReminderListInfo,
  ReminderInfo,
  RemindersAuthorizedResult,
  RemindersListsResult,
  RemindersItemsParams,
  RemindersItemsResult,
```

### Step 3: Run type-check

Run: `cd packages/darwinkit && bunx tsgo --noEmit 2>&1 | tail -5`
Expected: No errors

### Step 4: Commit

```bash
git add \
  packages/darwinkit/src/client.ts \
  packages/darwinkit/src/index.ts
git commit -m "feat(sdk): wire Contacts, Calendar, Reminders into client and barrel exports"
```

---

## Task 13: Run Full Test Suite + Final Verification

### Step 1: Run all Swift tests

Run: `cd packages/darwinkit-swift && swift test 2>&1 | tail -20`
Expected: All tests pass (existing + 33 new tests across 3 handler suites)

### Step 2: Run TypeScript type-check

Run: `cd packages/darwinkit && bunx tsgo --noEmit 2>&1 | tail -5`
Expected: No errors

### Step 3: Verify all new methods appear in handler registration

Run: `cd packages/darwinkit-swift && swift build 2>&1 | tail -3`
Expected: Build succeeds

### Step 4: Final commit (if any cleanup needed)

If everything passes, no additional commit needed. If any fixes were required, commit them:

```bash
git add -A
git commit -m "fix: resolve issues from final verification pass"
```

---

## Summary of Files Created/Modified

### New Files (12 total)

| File | Purpose |
|------|---------|
| `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/ContactsProvider.swift` | Provider protocol + Apple implementation |
| `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/ContactsHandler.swift` | JSON-RPC handler for contacts.* |
| `packages/darwinkit-swift/Tests/DarwinKitCoreTests/ContactsHandlerTests.swift` | Mock + unit tests |
| `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/CalendarProvider.swift` | Provider protocol + Apple implementation |
| `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/CalendarHandler.swift` | JSON-RPC handler for calendar.* |
| `packages/darwinkit-swift/Tests/DarwinKitCoreTests/CalendarHandlerTests.swift` | Mock + unit tests |
| `packages/darwinkit-swift/Sources/DarwinKitCore/Providers/RemindersProvider.swift` | Provider protocol + Apple implementation |
| `packages/darwinkit-swift/Sources/DarwinKitCore/Handlers/RemindersHandler.swift` | JSON-RPC handler for reminders.* |
| `packages/darwinkit-swift/Tests/DarwinKitCoreTests/RemindersHandlerTests.swift` | Mock + unit tests |
| `packages/darwinkit/src/namespaces/contacts.ts` | TS SDK namespace |
| `packages/darwinkit/src/namespaces/calendar.ts` | TS SDK namespace |
| `packages/darwinkit/src/namespaces/reminders.ts` | TS SDK namespace |

### Modified Files (3 total)

| File | Change |
|------|--------|
| `packages/darwinkit-swift/Sources/DarwinKit/DarwinKit.swift` | Register 3 new handlers |
| `packages/darwinkit/src/types.ts` | Add types + MethodMap entries |
| `packages/darwinkit/src/client.ts` | Add namespace properties |
| `packages/darwinkit/src/index.ts` | Add barrel exports |

### Test Count

- ContactsHandlerTests: 12 tests
- CalendarHandlerTests: 12 tests
- RemindersHandlerTests: 9 tests
- **Total: 33 new tests**

### JSON-RPC Methods (11 total)

| Method | Namespace | Description |
|--------|-----------|-------------|
| `contacts.authorized` | contacts | Check/request contacts permission |
| `contacts.list` | contacts | List all contacts (optional limit) |
| `contacts.get` | contacts | Get contact by identifier |
| `contacts.search` | contacts | Search by name |
| `calendar.authorized` | calendar | Check/request calendar permission |
| `calendar.calendars` | calendar | List all calendars |
| `calendar.events` | calendar | Fetch events in date range |
| `calendar.event` | calendar | Get event by identifier |
| `reminders.authorized` | reminders | Check/request reminders permission |
| `reminders.lists` | reminders | List reminder lists |
| `reminders.items` | reminders | Fetch reminders (with filter) |
