import Foundation
import AuthenticationServices
import Observation

/// The signed-in Apple account, as returned by Sign in with Apple.
///
/// `userIdentifier` is Apple's stable, app-scoped pseudonymous ID. It is not a
/// secret, but it is personal data, so it never gets logged.
struct AccountProfile: Codable, Equatable {
    var userIdentifier: String
    var displayName: String?
    var email: String?
    var signedInAt: Date

    var initial: String {
        if let first = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).first {
            return String(first).uppercased()
        }
        return "A"
    }

    var initialsForBadge: String {
        guard let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return "" }
        let parts = name.split(separator: " ")
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

enum AuthError: LocalizedError {
    case unsupportedCredential
    case missingIdentity

    var errorDescription: String? {
        switch self {
        case .unsupportedCredential:
            return "不支持的登录方式，请使用「通过 Apple 登录」。"
        case .missingIdentity:
            return "未能获取 Apple 账户标识，请重试。"
        }
    }
}

/// Holds the Sign in with Apple session and persists the profile across launches.
///
/// Apple only returns `fullName` / `email` on the **first** authorization for a
/// given app + Apple ID, so later sign-ins merge into the stored profile instead
/// of overwriting it with `nil`.
@MainActor
@Observable
final class AuthService {

    private(set) var profile: AccountProfile?
    private(set) var lastError: String?

    var isSignedIn: Bool { profile != nil }

    private let storageKey = "wristai.account.profile"

    init() {
        load()

        #if DEBUG
        // Preview / UI-test hook: launch with `-WristAIDemoLogin` to skip Apple
        // sign-in. Debug builds only, and it never overwrites a real profile.
        if profile == nil,
           ProcessInfo.processInfo.arguments.contains("-WristAIDemoLogin") {
            profile = AccountProfile(
                userIdentifier: "demo.user",
                displayName: "测试用户",
                email: "demo@privaterelay.appleid.com",
                signedInAt: .now
            )
        }
        #endif
    }

    // MARK: - Sign in

    /// Call from `SignInWithAppleButton`'s completion handler.
    func handle(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            do {
                try apply(authorization)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        case .failure(let error):
            // A user cancelling is a normal outcome, not an error worth shouting about.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                lastError = nil
                return
            }
            lastError = error.localizedDescription
        }
    }

    private func apply(_ authorization: ASAuthorization) throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.unsupportedCredential
        }
        guard !credential.user.isEmpty else {
            throw AuthError.missingIdentity
        }

        let formatter = PersonNameComponentsFormatter()
        let newName: String? = credential.fullName.map { formatter.string(from: $0) }
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let current = profile

        profile = AccountProfile(
            userIdentifier: credential.user,
            displayName: newName ?? current?.displayName,
            email: credential.email ?? current?.email,
            signedInAt: .now
        )
        save()
    }

    /// Re-verify the stored credential is still valid with Apple.
    func refreshCredentialState() async {
        guard let identifier = profile?.userIdentifier else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: identifier)
            if state == .revoked || state == .notFound {
                signOut()
            }
        } catch {
            // Transient failure: keep the session rather than dumping the user out.
        }
    }

    // MARK: - Sign out

    func signOut() {
        profile = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Persistence

    private func save() {
        guard let profile, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AccountProfile.self, from: data) else { return }
        profile = decoded
    }
}
