import SwiftUI
import ReclaimKit

/// Shared display formatting for dates and durations.
enum Fmt {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dayOnly.string(from: date)
    }
    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relative.localizedString(for: date, relativeTo: Date())
    }
    static func duration(_ hours: Double?) -> String {
        guard let hours, hours > 0 else { return "—" }
        let total = Int((hours * 60).rounded()); let h = total / 60; let m = total % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .p1: return .red
        case .p2: return .orange
        case .p3: return .blue
        case .p4: return .secondary
        }
    }
}
