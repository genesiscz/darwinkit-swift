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
