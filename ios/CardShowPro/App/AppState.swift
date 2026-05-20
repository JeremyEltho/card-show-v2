import Foundation
import Observation

@Observable
final class AppState {
    var networkReachable: Bool = true
    var syncPending: Int = 0
    var activeShowName: String = ""
}
