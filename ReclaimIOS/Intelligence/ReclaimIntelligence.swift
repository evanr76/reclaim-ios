import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device intelligence powered by Apple's Foundation Models framework.
///
/// Everything here is gated on iOS 26 (where the framework ships) *and* runtime
/// model availability (device eligibility + Apple Intelligence enabled + model
/// downloaded). Callers must check `isAvailable` / `unavailableReason` and fall
/// back gracefully — the app is fully usable without any of this.
enum ReclaimIntelligence {

    /// Whether the on-device model can be used right now.
    static var isAvailable: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// A user-facing reason the model can't be used, or `nil` when it's ready.
    static var unavailableReason: String? {
        guard #available(iOS 26, *) else {
            return "On-device intelligence requires iOS 26 or later."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use on-device features."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable:
            return "On-device intelligence is unavailable right now."
        }
    }
}

// MARK: - Guided-generation schemas

/// Priority as inferred from free text. Mapped to `Priority` at the call site.
@available(iOS 26, *)
@Generable
enum ParsedPriority {
    case p1, p2, p3, p4
}

/// A single task extracted from free text (or OCR'd text) by the model.
///
/// Note on due dates: we deliberately capture *whether a deadline was explicitly
/// stated* separately from the date itself. Reclaim schedules by priority, so we
/// never fabricate a due date — the UI only pre-fills one when `hasExplicitDueDate`
/// is true, and even then the user confirms it.
@available(iOS 26, *)
@Generable
struct ParsedTask {
    @Guide(description: "A short, action-oriented task title. Do NOT put dates, times, or durations in the title.")
    var title: String

    @Guide(description: "Estimated effort to complete, in hours, as a decimal such as 0.5, 1, or 2. Make a reasonable estimate when the text doesn't say.")
    var estimatedHours: Double

    @Guide(description: "Priority implied by the text. Use p3 by default; use p1/p2 only when the text signals urgency, and p4 when it reads as low priority.")
    var priority: ParsedPriority

    @Guide(description: "True only when the text explicitly names a deadline or due date/time.")
    var hasExplicitDueDate: Bool

    @Guide(description: "When (and only when) a deadline is explicitly stated, its absolute date-time in ISO 8601, e.g. 2026-07-31T17:00:00. Otherwise an empty string.")
    var dueISO8601: String
}

// MARK: - Multi-turn task capture

/// Owns a single `LanguageModelSession` so the user can refine a parse across
/// several turns ("make it 2 hours", "actually P1", "due Friday") with full
/// context retained by the session.
@available(iOS 26, *)
@MainActor
final class TaskCaptureSession {
    private let session: LanguageModelSession

    init(now: Date = Date()) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let nowString = iso.string(from: now)
        session = LanguageModelSession(instructions: """
            You turn short notes into a single structured task for a task manager.
            The current date and time is \(nowString); interpret any relative dates \
            (\"tomorrow\", \"Friday\") against it.
            Keep the title concise and action-oriented.
            Never invent a deadline that the note doesn't clearly state.
            When the user follows up, treat it as a refinement of the same task and \
            keep everything they didn't change.
            """)
    }

    /// Parse (or, on later calls, refine) the task. Reusing the session is what
    /// makes the follow-ups context-aware.
    func parse(_ text: String) async throws -> ParsedTask {
        var options = GenerationOptions()
        options.temperature = 0.2   // low: this is extraction, not creativity
        return try await session.respond(to: text,
                                         generating: ParsedTask.self,
                                         options: options).content
    }
}

// MARK: - Daily briefing

/// Generates a short natural-language "here's your day" briefing. One-shot, so
/// it uses a fresh session each time. The caller formats the context lines so
/// this stays decoupled from the API models.
@available(iOS 26, *)
enum BriefingGenerator {
    /// - Parameters:
    ///   - taskLines: pre-formatted "P1 · Ship deck · 2h · due Fri" style lines.
    ///   - nowLine: what's scheduled right now, or nil.
    ///   - nextLine: the next upcoming block, or nil.
    static func generate(taskLines: [String], nowLine: String?, nextLine: String?) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You are a concise personal planning assistant.
            Write a short, friendly briefing of 2–4 sentences (prose, no bullet lists) \
            that orients the person for the day: what to focus on and what's most urgent.
            Be specific but brief. Do not invent tasks, times, or deadlines beyond what's given.
            """)

        var prompt = "Here is my day.\n"
        if let nowLine { prompt += "Happening now: \(nowLine)\n" }
        if let nextLine { prompt += "Up next: \(nextLine)\n" }
        if taskLines.isEmpty {
            prompt += "I have no open tasks.\n"
        } else {
            prompt += "Open tasks:\n" + taskLines.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        prompt += "Write my briefing."

        return try await session.respond(to: prompt).content
    }
}
