import Foundation
import Observation

@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var currentUser: AuthUser?
    var isLoading = false
    var errorMessage: String?

    private let network = NetworkService.shared
    private let auth = AuthService.shared

    init() {
        Task {
            isAuthenticated = await auth.isAuthenticated()
            currentUser = await auth.currentUser
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await auth.login(email: email, password: password, network: network)
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func register(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await auth.register(email: email, password: password, displayName: displayName, network: network)
            currentUser = user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() async {
        await auth.logout(network: network)
        currentUser = nil
        isAuthenticated = false
    }
}
