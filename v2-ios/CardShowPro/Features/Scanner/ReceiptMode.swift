import SwiftUI

/// Whether the scanner shows the result sheet + success overlay on every scan
/// (`withReceipt`), or rips through high-confidence scans with just a brief
/// toast (`fast`).
///
/// Picked once on `LogActionPickerView` before scanning, applied for the whole
/// scanning session.
enum ReceiptMode: String, CaseIterable, Identifiable {
    case withReceipt
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .withReceipt: return "WITH RECEIPT"
        case .fast:        return "FAST · NO RECEIPT"
        }
    }

    var subtitle: String {
        switch self {
        case .withReceipt: return "Confirm price + save receipt each scan"
        case .fast:        return "Rip through scans, brief toast only"
        }
    }

    var icon: String {
        switch self {
        case .withReceipt: return "doc.text.fill"
        case .fast:        return "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .withReceipt: return Theme.Colors.amber
        case .fast:        return Theme.Colors.green
        }
    }
}
