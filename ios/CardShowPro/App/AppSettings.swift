import Foundation
import Observation

/// User-tunable settings that survive across launches via UserDefaults.
/// Singleton so any view can read/mutate without prop-drilling.
///
/// Reads happen once at init (cheap). Writes go straight through on every
/// mutation. Observable, so SwiftUI views that read these properties
/// automatically re-render on change.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Vendor identity

    var vendorName: String {
        didSet { defaults.set(vendorName, forKey: Keys.vendorName) }
    }

    // MARK: - Active show

    var activeShowName: String {
        didSet {
            defaults.set(activeShowName, forKey: Keys.activeShowName)
            rememberRecentShow(activeShowName)
        }
    }

    /// MRU list of shows the vendor has worked. Capped at 8.
    var recentShows: [String] {
        didSet { defaults.set(recentShows, forKey: Keys.recentShows) }
    }

    // MARK: - Scan defaults (raw-backed so they're cheaply Codable)

    var defaultLogModeRaw: String {
        didSet { defaults.set(defaultLogModeRaw, forKey: Keys.defaultLogMode) }
    }

    var defaultReceiptModeRaw: String {
        didSet { defaults.set(defaultReceiptModeRaw, forKey: Keys.defaultReceiptMode) }
    }

    var defaultCondition: String {
        didSet { defaults.set(defaultCondition, forKey: Keys.defaultCondition) }
    }

    /// Daily NET revenue target (in dollars). Powers the home-screen progress
    /// bar. 0 disables the section.
    var dailyTarget: Double {
        didSet { defaults.set(dailyTarget, forKey: Keys.dailyTarget) }
    }

    // MARK: - Typed accessors

    var defaultLogMode: LogMode {
        get { LogMode(rawValue: defaultLogModeRaw) ?? .buy }
        set { defaultLogModeRaw = newValue.rawValue }
    }

    var defaultReceiptMode: ReceiptMode {
        get { ReceiptMode(rawValue: defaultReceiptModeRaw) ?? .withReceipt }
        set { defaultReceiptModeRaw = newValue.rawValue }
    }

    // MARK: - Init

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.vendorName = defaults.string(forKey: Keys.vendorName) ?? ""
        self.activeShowName = defaults.string(forKey: Keys.activeShowName) ?? ""
        self.recentShows = defaults.stringArray(forKey: Keys.recentShows) ?? []
        self.defaultLogModeRaw = defaults.string(forKey: Keys.defaultLogMode) ?? LogMode.buy.rawValue
        self.defaultReceiptModeRaw = defaults.string(forKey: Keys.defaultReceiptMode) ?? ReceiptMode.withReceipt.rawValue
        self.defaultCondition = defaults.string(forKey: Keys.defaultCondition) ?? "near_mint"
        // 0.0 is the UserDefaults default for unset doubles. We use that as
        // the "no target set" sentinel rather than nil to keep the API simple.
        let storedTarget = defaults.double(forKey: Keys.dailyTarget)
        self.dailyTarget = storedTarget > 0 ? storedTarget : 200
    }

    // MARK: - Helpers

    private func rememberRecentShow(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentShows.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        // Avoid an infinite didSet loop: only assign when the array actually changed.
        if list != recentShows { recentShows = list }
    }

    /// Nuke vendor + show settings (used by the Settings → Reset row).
    func resetVendorIdentity() {
        vendorName = ""
        activeShowName = ""
        recentShows = []
    }

    private enum Keys {
        static let vendorName         = "settings.vendorName"
        static let activeShowName     = "settings.activeShowName"
        static let recentShows        = "settings.recentShows"
        static let defaultLogMode     = "settings.defaultLogMode"
        static let defaultReceiptMode = "settings.defaultReceiptMode"
        static let defaultCondition   = "settings.defaultCondition"
        static let dailyTarget        = "settings.dailyTarget"
    }
}
