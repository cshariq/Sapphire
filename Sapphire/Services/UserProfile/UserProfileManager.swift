//
//  UserProfileManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Contacts
import EventKit
import CoreLocation

@MainActor
class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    @Published var profile: PersonalProfile?
    @Published var isEnabled: Bool = false
    @Published var autoDiscoveryEnabled: Bool = true

    private let encryptionManager = EncryptionManager.shared
    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()

    private let profileKey = "user_profile_data"
    private let enabledKey = "user_profile_enabled"
    private let autoDiscoveryKey = "user_profile_auto_discovery"

    private init() {
        loadProfile()
    }

    // MARK: - Profile Management

    private func loadProfile() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        autoDiscoveryEnabled = UserDefaults.standard.bool(forKey: autoDiscoveryKey)

        guard isEnabled else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            if let encryptedData = UserDefaults.standard.data(forKey: self.profileKey),
               let decrypted = try? self.encryptionManager.decrypt(encryptedData),
               let profile = try? JSONDecoder().decode(PersonalProfile.self, from: decrypted) {
                await MainActor.run {
                    self.profile = profile
                }
            } else {
                await MainActor.run {
                    self.profile = PersonalProfile()
                }
            }
        }
    }

    func saveProfile() {
        guard let profile = profile else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            do {
                let encoded = try JSONEncoder().encode(profile)
                let encrypted = try self.encryptionManager.encrypt(encoded)
                UserDefaults.standard.set(encrypted, forKey: self.profileKey)

                print(" User profile saved securely")
            } catch {
                print(" Failed to save user profile: \(error)")
            }
        }
    }

    func enable() {
        isEnabled = true
        UserDefaults.standard.set(true, forKey: enabledKey)

        if profile == nil {
            profile = PersonalProfile()
        }

        if autoDiscoveryEnabled {
            Task {
                await discoverUserInformation()
            }
        }
    }

    func disable(clearData: Bool = false) {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: enabledKey)

        if clearData {
            profile = nil
            UserDefaults.standard.removeObject(forKey: profileKey)
        }
    }

    func updateProfile(_ updatedProfile: PersonalProfile) {
        self.profile = updatedProfile
        saveProfile()
    }

    // MARK: - Auto-Discovery

    func discoverUserInformation() async {
        guard isEnabled, autoDiscoveryEnabled else { return }

        var discoveredProfile = profile ?? PersonalProfile()
        discoveredProfile.lastUpdated = Date()

        await discoverFromContacts(&discoveredProfile)
        await discoverFromSystem(&discoveredProfile)
        await discoverFromCalendar(&discoveredProfile)

        self.profile = discoveredProfile
        saveProfile()
    }

    // MARK: - Contact Discovery

    private func discoverFromContacts(_ profile: inout PersonalProfile) async {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        guard status == .authorized || status == .notDetermined else {
            print("ℹ️ Contacts access not authorized")
            return
        }

        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { return }
        }

        do {
            let keysToFetch = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactNicknameKey,
                CNContactBirthdayKey,
                CNContactPhoneNumbersKey,
                CNContactEmailAddressesKey,
                CNContactPostalAddressesKey,
            ] as [CNKeyDescriptor]

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var meContact: CNContact?

            try contactStore.enumerateContacts(with: request) { contact, stop in
                if meContact == nil ||
                   (!contact.givenName.isEmpty && !contact.familyName.isEmpty) {
                    meContact = contact
                }
            }

            if let contact = meContact {
                if profile.firstName.isEmpty {
                    profile.firstName = contact.givenName
                }
                if profile.lastName.isEmpty {
                    profile.lastName = contact.familyName
                }
                if profile.nickname.isEmpty {
                    profile.nickname = contact.nickname
                }

                if profile.birthday == nil, let birthday = contact.birthday {
                    var components = DateComponents()
                    components.year = birthday.year
                    components.month = birthday.month
                    components.day = birthday.day
                    if let date = Calendar.current.date(from: components) {
                        profile.birthday = date
                    }
                }

                if profile.phoneNumber.isEmpty, let phone = contact.phoneNumbers.first {
                    profile.phoneNumber = phone.value.stringValue
                }

                if profile.email.isEmpty, let email = contact.emailAddresses.first {
                    profile.email = email.value as String
                }

                if profile.address.isEmpty, let address = contact.postalAddresses.first {
                    let addr = address.value
                    var addressString = ""
                    if !addr.street.isEmpty { addressString += addr.street + ", " }
                    if !addr.city.isEmpty { addressString += addr.city + ", " }
                    if !addr.state.isEmpty { addressString += addr.state + " " }
                    if !addr.postalCode.isEmpty { addressString += addr.postalCode }
                    profile.address = addressString.trimmingCharacters(in: .whitespaces)
                }

                profile.discoverySource.insert(.contacts)
                print(" Discovered user info from Contacts")
            }
        } catch {
            print(" Failed to fetch contacts: \(error)")
        }
    }

    // MARK: - System Discovery

    private func discoverFromSystem(_ profile: inout PersonalProfile) async {
        if profile.firstName.isEmpty {
            let fullName = NSFullUserName()
            if !fullName.isEmpty {
                let components = fullName.components(separatedBy: " ")
                if components.count > 0 {
                    profile.firstName = components[0]
                }
                if components.count > 1 {
                    profile.lastName = components.dropFirst().joined(separator: " ")
                }
                profile.discoverySource.insert(.system)
            }
        }

        profile.preferredLanguage = Locale.current.languageCode ?? "en"
        profile.region = Locale.current.regionCode ?? "US"

        profile.timezone = TimeZone.current.identifier

        print(" Discovered system information")
    }

    // MARK: - Calendar Discovery

    private func discoverFromCalendar(_ profile: inout PersonalProfile) async {
        let status = EKEventStore.authorizationStatus(for: .event)

        guard status == .authorized || status == .notDetermined else {
            print("ℹ️ Calendar access not authorized")
            return
        }

        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { return }
        }

        if profile.birthday == nil {
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .year, value: -50, to: Date())!
            let endDate = calendar.date(byAdding: .year, value: 1, to: Date())!

            let predicate = eventStore.predicateForEvents(
                withStart: startDate,
                end: endDate,
                calendars: nil
            )

            let events = eventStore.events(matching: predicate)

            for event in events {
                if event.title?.lowercased().contains("birthday") == true ||
                   event.calendar.title.lowercased().contains("birthday") {
                    if let eventDate = event.startDate {
                        profile.birthday = eventDate
                        profile.discoverySource.insert(.calendar)
                        break
                    }
                }
            }
        }

        print(" Checked calendar for birthday")
    }

    // MARK: - AI Context Generation

    func generateAIContext() -> String? {
        guard isEnabled, let profile = profile else { return nil }

        var context = "# User Profile\n\n"

        if !profile.firstName.isEmpty {
            context += "Name: \(profile.fullName)\n"
        }

        if !profile.nickname.isEmpty {
            context += "Preferred name: \(profile.nickname)\n"
        }

        if let age = profile.age {
            context += "Age: \(age)\n"
        }

        if let gender = profile.gender {
            context += "Gender: \(gender.rawValue)\n"
        }

        if !profile.email.isEmpty {
            context += "Email: \(profile.email)\n"
        }

        if !profile.phoneNumber.isEmpty {
            context += "Phone: \(profile.phoneNumber)\n"
        }

        if !profile.address.isEmpty {
            context += "Address: \(profile.address)\n"
        }

        if !profile.region.isEmpty {
            context += "Region: \(profile.region)\n"
        }

        if !profile.timezone.isEmpty {
            context += "Timezone: \(profile.timezone)\n"
        }

        if !profile.preferredLanguage.isEmpty {
            context += "Language: \(profile.preferredLanguage)\n"
        }

        if !profile.occupation.isEmpty {
            context += "Occupation: \(profile.occupation)\n"
        }

        if !profile.customFields.isEmpty {
            context += "\nAdditional Information:\n"
            for (key, value) in profile.customFields {
                context += "- \(key): \(value)\n"
            }
        }

        return context
    }

    // MARK: - Permission Requests

    func requestContactsPermission() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        if status == .authorized {
            return true
        }

        return await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func requestCalendarPermission() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        if status == .authorized {
            return true
        }

        return await withCheckedContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - User Profile Model

struct PersonalProfile: Codable, Equatable {
    var firstName: String = ""
    var lastName: String = ""
    var nickname: String = ""
    var birthday: Date?
    var gender: Gender?

    var email: String = ""
    var phoneNumber: String = ""
    var address: String = ""

    var region: String = ""
    var timezone: String = ""
    var preferredLanguage: String = ""

    var occupation: String = ""
    var company: String = ""

    var customFields: [String: String] = [:]

    var lastUpdated: Date = Date()
    var discoverySource: Set<DiscoverySource> = []

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var age: Int? {
        guard let birthday = birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
    }

    var displayName: String {
        if !nickname.isEmpty {
            return nickname
        } else if !firstName.isEmpty {
            return firstName
        } else {
            return "User"
        }
    }

    enum Gender: String, Codable, CaseIterable {
        case male = "Male"
        case female = "Female"
        case nonBinary = "Non-binary"
        case preferNotToSay = "Prefer not to say"
        case other = "Other"
    }

    enum DiscoverySource: String, Codable {
        case manual = "Manual"
        case contacts = "Contacts"
        case calendar = "Calendar"
        case system = "System"
        case icloud = "iCloud"
    }
}