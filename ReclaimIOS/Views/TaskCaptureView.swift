import SwiftUI
import PhotosUI
import ReclaimKit

/// AI task capture: type/dictate/paste (or scan) free text, let the on-device
/// model turn it into a structured task, refine it conversationally, then add.
///
/// Requires iOS 26 (Foundation Models). Presented only behind an availability
/// check; if the model isn't ready it explains why instead of failing.
@available(iOS 26, *)
struct TaskCaptureView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case input, review }
    @State private var phase: Phase = .input

    @State private var note = ""
    @State private var isBusy = false
    @State private var isReadingImage = false
    @State private var errorText: String?

    // Editable draft (suggestions the user confirms).
    @State private var title = ""
    @State private var priority: Priority = .p3
    @State private var durationHours: Double = 1
    @State private var hasDue = false
    @State private var due = Date()

    // Multi-turn refinement.
    @State private var refineText = ""
    @State private var captureSession: TaskCaptureSession?

    // Image capture.
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Group {
                if let reason = ReclaimIntelligence.unavailableReason {
                    unavailableView(reason)
                } else if phase == .input {
                    inputForm
                } else {
                    reviewForm
                }
            }
            .navigationTitle(phase == .review ? "Review Task" : "AI Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await readImage(from: item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in Task { await runOCR(on: image) } }
                    .ignoresSafeArea()
            }
        }
    }

    @State private var showPhotoPicker = false

    // MARK: Input

    private var inputForm: some View {
        Form {
            Section {
                TextField("e.g. \"Draft the Q3 board deck, about 3 hours, before Friday's standup\"",
                          text: $note, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Describe the task")
            } footer: {
                Text("Type, dictate (tap the mic on the keyboard), paste, or scan text from a photo. The on-device model turns it into a task — nothing leaves your device.")
            }

            Section {
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                    }
                    Button { showPhotoPicker = true } label: { Label("Choose Photo", systemImage: "photo") }
                } label: {
                    Label(isReadingImage ? "Reading text…" : "Scan text from photo", systemImage: "text.viewfinder")
                }
                .disabled(isReadingImage)
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red).font(.callout) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await parse(note) }
            } label: {
                HStack {
                    if isBusy { ProgressView().tint(.white) }
                    Text(isBusy ? "Thinking…" : "Create with AI")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
        }
    }

    // MARK: Review

    private var reviewForm: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $title, axis: .vertical)
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
                Stepper(value: $durationHours, in: 0.25...40, step: 0.25) {
                    HStack { Text("Duration"); Spacer(); Text(Fmt.duration(durationHours)).foregroundStyle(.secondary) }
                }
                Toggle("Due date", isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section {
                HStack {
                    TextField("Refine, e.g. \"make it 2 hours\" or \"due Friday\"", text: $refineText, axis: .vertical)
                    Button {
                        Task { await refine() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(isBusy || refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Refine")
            } footer: {
                Text("The assistant keeps the context of this task, so you can adjust it in plain language.")
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red).font(.callout) }
            }

            Section {
                Button("Start over") { resetToInput() }
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if isBusy { Color.black.opacity(0.05).ignoresSafeArea(); ProgressView() }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await add() }
            } label: {
                Text("Add Task").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
        }
    }

    // MARK: Unavailable

    private func unavailableView(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("AI Capture Unavailable", systemImage: "sparkles")
        } description: {
            Text(reason)
        }
    }

    // MARK: Actions

    private func parse(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isBusy = true; errorText = nil
        defer { isBusy = false }
        do {
            if captureSession == nil { captureSession = TaskCaptureSession() }
            let parsed = try await captureSession!.parse(trimmed)
            apply(parsed)
            phase = .review
        } catch {
            errorText = "Couldn't read that. Try rephrasing. (\(error.localizedDescription))"
        }
    }

    private func refine() async {
        let text = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await parse(text)
        refineText = ""
    }

    private func add() async {
        isBusy = true; defer { isBusy = false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        await vm.createTask(title: trimmed, priority: priority,
                            durationHours: durationHours, due: hasDue ? due : nil)
        dismiss()
    }

    private func apply(_ parsed: ParsedTask) {
        title = parsed.title
        let clamped = min(40, max(0.25, (parsed.estimatedHours / 0.25).rounded() * 0.25))
        durationHours = clamped
        priority = parsed.priority.mapped
        // Only pre-fill a due date the note explicitly stated — never fabricate one.
        if parsed.hasExplicitDueDate, let date = Self.isoDate(parsed.dueISO8601) {
            hasDue = true
            due = date
        } else {
            hasDue = false
        }
    }

    private func resetToInput() {
        phase = .input
        captureSession = nil
        refineText = ""
        errorText = nil
    }

    private func readImage(from item: PhotosPickerItem) async {
        isReadingImage = true; defer { isReadingImage = false; photoItem = nil }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await runOCR(on: image)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runOCR(on image: UIImage) async {
        isReadingImage = true; defer { isReadingImage = false }
        do {
            let text = try await VisionOCR.recognizeText(in: image)
            if text.isEmpty {
                errorText = "No text found in that image."
            } else {
                note = note.isEmpty ? text : note + "\n" + text
                errorText = nil
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private static func isoDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        // The model sometimes emits a local, timezone-less stamp.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: trimmed)
    }
}

@available(iOS 26, *)
private extension ParsedPriority {
    var mapped: Priority {
        switch self {
        case .p1: .p1
        case .p2: .p2
        case .p3: .p3
        case .p4: .p4
        }
    }
}
