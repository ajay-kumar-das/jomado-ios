import Foundation

struct CompanionPushRegistrationDiagnostics: Equatable {
    enum State: String {
        case notConfigured
        case waitingForToken
        case registered
        case failed
    }

    var state: State = .notConfigured
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?

    var detail: String {
        switch state {
        case .notConfigured:
            return "Remote Live Activity delivery is off because no production registration endpoint is configured. Local notifications remain the authoritative reminder path."
        case .waitingForToken:
            return "Remote delivery is configured and waiting for iOS to issue a push-to-start token."
        case .registered:
            return "This installation's ActivityKit routing token is registered. No hydration history, schedule, response time, or content preference is sent."
        case .failed:
            return "Remote companion registration failed. Local notifications are unaffected and remain the delivery fallback."
        }
    }
}

actor CompanionPushRegistrationService {
    static let shared = CompanionPushRegistrationService()

    private let defaults = UserDefaults.standard
    private let session: URLSession
    private let endpoint: URL?

    init(bundle: Bundle = .main) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)

        let raw = (bundle.object(forInfoDictionaryKey: "JomadoCompanionRegistrationEndpoint") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil {
            self.endpoint = url
        } else {
            self.endpoint = nil
        }
    }

    func diagnostics(tokenAvailable: Bool) -> CompanionPushRegistrationDiagnostics {
        guard endpoint != nil else {
            return .init(state: .notConfigured)
        }
        guard tokenAvailable else {
            return .init(state: .waitingForToken)
        }
        let error = defaults.string(forKey: "companionPushRegistrationLastError")
        let success = defaults.object(forKey: "companionPushRegistrationLastSuccessAt") as? Date
        return .init(
            state: error == nil && success != nil ? .registered : (error == nil ? .waitingForToken : .failed),
            lastAttemptAt: defaults.object(forKey: "companionPushRegistrationLastAttemptAt") as? Date,
            lastSuccessAt: success,
            lastError: error
        )
    }

    /// Registers only APNs routing metadata. Never add routine times, hydration
    /// history, completion state, content preferences, or analytics to this payload.
    func register(pushToStartToken: String) async {
        guard let endpoint else { return }
        guard !pushToStartToken.isEmpty else { return }

        let installationID: String
        if let existing = defaults.string(forKey: "companionInstallationID") {
            installationID = existing
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: "companionInstallationID")
            installationID = created
        }

        let body = RegistrationRequest(
            schemaVersion: 1,
            installationID: installationID,
            pushToStartToken: pushToStartToken
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        do {
            request.httpBody = try JSONEncoder().encode(body)
            defaults.set(Date(), forKey: "companionPushRegistrationLastAttemptAt")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RegistrationError.rejected((response as? HTTPURLResponse)?.statusCode)
            }
            defaults.set(Date(), forKey: "companionPushRegistrationLastSuccessAt")
            defaults.removeObject(forKey: "companionPushRegistrationLastError")
        } catch {
            defaults.set(String(describing: error), forKey: "companionPushRegistrationLastError")
        }
    }

    private struct RegistrationRequest: Encodable {
        let schemaVersion: Int
        let installationID: String
        let pushToStartToken: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case installationID = "installation_id"
            case pushToStartToken = "push_to_start_token"
        }
    }

    private enum RegistrationError: Error, CustomStringConvertible {
        case rejected(Int?)
        var description: String {
            switch self {
            case .rejected(let code): return "registration_rejected_\(code.map(String.init) ?? "unknown")"
            }
        }
    }
}
