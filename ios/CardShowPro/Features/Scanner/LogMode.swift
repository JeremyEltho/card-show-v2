import SwiftUI

/// Vendor action context the scanner runs under. Selected from LogActionPickerView,
/// passed into ScannerView, used by ScanResultSheet to skip the action picker.
enum LogMode: String, CaseIterable, Identifiable {
    case buy, sell, trade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buy:   return "BUY"
        case .sell:  return "SELL"
        case .trade: return "TRADE"
        }
    }

    var subtitle: String {
        switch self {
        case .buy:   return "Picked up from a customer"
        case .sell:  return "Sold to a customer"
        case .trade: return "Trade in or trade out"
        }
    }

    var icon: String {
        switch self {
        case .buy:   return "arrow.down.circle.fill"
        case .sell:  return "arrow.up.circle.fill"
        case .trade: return "arrow.left.arrow.right.circle.fill"
        }
    }

    /// Maps to the inventory-item status field used by SwiftData.
    var inventoryStatus: String {
        switch self {
        case .buy:   return "bought"
        case .sell:  return "sold"
        case .trade: return "traded"
        }
    }

    /// Theme tint colour — drives the scanner mode badge and the result-sheet primary button.
    var tint: Color {
        switch self {
        case .buy:   return Theme.Colors.blue
        case .sell:  return Theme.Colors.green
        case .trade: return Theme.Colors.amber
        }
    }
}
