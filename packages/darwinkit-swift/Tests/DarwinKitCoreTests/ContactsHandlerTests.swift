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
