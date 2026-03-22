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
