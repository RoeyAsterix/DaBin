import SwiftUI

/// Shared native task controls, used by cards, detail and Explorer. Countdown
/// ticks are presentation only; TaskFocusCoordinator owns durable expiry.
@MainActor
struct TaskFocusControls: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var compact = true
    @Environment(\.daBinAccent) private var accent
    @State private var showDuration = false
    @State private var showSchedule = false
    @State private var hours = "0"
    @State private var minutes = "25"
    @State private var scheduleDate = Date()
    @State private var scheduleTime = ""
    @State private var error: String?

    private var session: TaskFocusSession? { capture.taskPlanning?.focusSession }
    private var running: Bool { session?.isRunning == true && !capture.isCompleted }
    private var scheduleLabel: String {
        guard let day = capture.taskPlanning?.plannedDay else { return "Schedule" }
        let today = CaptureCalendar.dayString(Date())
        let tomorrow = CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let label = day == today ? "Today" : day == tomorrow ? "Tomorrow" : day
        return label + (capture.taskPlanning?.plannedTime.map { " · \($0)" } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 12) {
            if !compact {
                Label("Focus session", systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                countdown(large: true).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { focusControl; Spacer(minLength: 0); scheduleControl }
                VStack(alignment: .leading, spacing: 6) { focusControl; scheduleControl }
            }
            if !compact {
                HStack {
                    Text(capture.isCompleted ? "Task complete" : running ? "Focusing · task remains open" : session?.remainingSeconds == 0 ? "Time’s up · ready to restart" : "Start when you’re ready")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { _ = state.resetTaskFocus(capture) } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                        .disabled(capture.taskPlanning?.effortMinutes == nil)
                        .accessibilityLabel("Reset focus to configured duration")
                }
            }
        }
    }

    private var focusControl: some View {
                HStack(spacing: 2) {
                    Button(action: openDuration) {
                        HStack(spacing: 5) {
                            if !compact { Image(systemName: "timer").foregroundStyle(Palette.muted) }
                            if compact { countdown(large: false) }
                            else { Text("Duration").font(.system(size: 12)) }
                        }.padding(.horizontal, 7).frame(minHeight: 32)
                    }.buttonStyle(.plain).accessibilityLabel("Set focus duration")
                        .accessibilityIdentifier("task-focus-duration-\(capture.id.uuidString)")
                        .buddyHelp("Set hours and minutes")
                        .popover(isPresented: $showDuration, arrowEdge: .bottom) { durationForm }
                    Button {
                        if capture.taskPlanning?.effortMinutes == nil { openDuration() }
                        else { _ = state.toggleTaskFocus(capture) }
                    } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(running ? accent.opacity(0.12) : accent, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(running ? accent : Palette.background)
                    }.buttonStyle(.plain).disabled(capture.isCompleted)
                        .accessibilityLabel(running ? "Pause focus session" : "Start or restart focus session")
                        .accessibilityIdentifier("task-focus-play-\(capture.id.uuidString)")
                        .buddyHelp(running ? "Pause focus" : "Start focus")
                }.padding(2).background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 1))
    }
    private var scheduleControl: some View {
                Button(action: openSchedule) {
                    Label(scheduleLabel, systemImage: "calendar")
                        .font(.system(size: 12)).lineLimit(compact ? 1 : 2)
                        .padding(.horizontal, 6).frame(minHeight: 34)
                }.buttonStyle(.plain).foregroundStyle(accent)
                    .accessibilityLabel("Schedule task: \(scheduleLabel)")
                    .accessibilityIdentifier("task-focus-schedule-\(capture.id.uuidString)")
                    .buddyHelp("Choose when to work, separate from a reminder")
                    .popover(isPresented: $showSchedule, arrowEdge: .bottom) { scheduleForm }
    }

    private func countdown(large: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1, paused: !running || !state.isBoardVisible)) { context in
            let seconds = session?.remaining(at: context.date) ?? TimeInterval((capture.taskPlanning?.effortMinutes ?? 0) * 60)
            Text(capture.taskPlanning?.effortMinutes == nil && !large ? "Set time" : TaskFocusSession.clock(seconds))
                .font(.system(size: large ? 36 : 12, weight: .regular, design: .monospaced))
                .monospacedDigit().fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(capture.taskPlanning?.effortMinutes == nil ? "No focus duration set" : "Focus time remaining \(TaskFocusSession.clock(seconds))")
        }
    }

    private func openDuration() {
        let total = capture.taskPlanning?.effortMinutes ?? 25
        hours = String(total / 60); minutes = String(total % 60)
        error = nil; showDuration = true
    }
    private func openSchedule() {
        scheduleDate = capture.taskPlanning?.plannedDay.flatMap { TaskPlanningPolicy.date(for: $0) } ?? Date()
        scheduleTime = capture.taskPlanning?.plannedTime ?? ""
        error = nil; showSchedule = true
    }
    private var durationForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Focus duration", systemImage: "timer").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 10) {
                durationField("Hours", text: $hours)
                Text(":").font(.system(size: 28, design: .monospaced)).foregroundStyle(Palette.muted)
                durationField("Minutes", text: $minutes)
            }
            HStack(spacing: 8) {
                ForEach([25, 45, 60], id: \.self) { value in
                    Button("\(value)m") { hours = String(value / 60); minutes = String(value % 60); error = nil }
                        .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 32)
                }
            }
            Text("1 minute–168 hours. This is separate from reminders.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.task).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { showDuration = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { saveDuration(start: false) }
                Button("Start") { saveDuration(start: true) }.buttonStyle(.borderedProminent).disabled(capture.isCompleted)
            }.controlSize(.small)
        }.padding(16).frame(width: 288).onExitCommand { showDuration = false }
    }
    private func durationField(_ title: String, text: Binding<String>) -> some View {
        VStack(spacing: 5) {
            TextField(title, text: text).font(.system(size: 28, design: .monospaced))
                .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 92)
                .accessibilityLabel("Focus duration \(title.lowercased())")
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
    private func saveDuration(start: Bool) {
        guard let hour = Int(hours), let minute = Int(minutes), TaskFocusSession.duration(hours: hour, minutes: minute) != nil else {
            error = "Enter whole hours and minutes (0–59), up to 168 hours."; return
        }
        if state.configureTaskFocus(capture, hours: hour, minutes: minute, start: start) { showDuration = false }
        else { error = "Could not save. Your entries are still here; try again." }
    }
    private var scheduleForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Work schedule", systemImage: "calendar").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                Button("Today") { quickSchedule(0) }.buttonStyle(.bordered)
                Button("Tomorrow") { quickSchedule(1) }.buttonStyle(.bordered)
                Button("Clear") {
                    if state.scheduleTask(capture, day: nil) { showSchedule = false }
                    else { error = "Could not save. Try again." }
                }.buttonStyle(.bordered)
            }.controlSize(.small)
            DatePicker("Work on", selection: $scheduleDate, displayedComponents: .date).datePickerStyle(.field)
            HStack {
                Text("Local time").font(.system(size: 12))
                Spacer()
                TextField("HH:MM · optional", text: $scheduleTime).textFieldStyle(.roundedBorder)
                    .frame(width: 140).accessibilityLabel("Optional local planned time in HH:MM")
            }
            Text("Planning never changes the receipt date, deadline or notification reminder.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.task).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { showSchedule = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save schedule") {
                    let time = scheduleTime.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard time.isEmpty || TaskPlanningPolicy.isValidLocalTime(time) else { error = "Use local time as HH:MM, such as 09:30."; return }
                    if state.scheduleTask(capture, day: CaptureCalendar.dayString(scheduleDate), time: time.isEmpty ? nil : time) { showSchedule = false }
                    else { error = "Could not save. Your entries are still here; try again." }
                }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
        }.padding(16).frame(width: 288).onExitCommand { showSchedule = false }
    }
    private func quickSchedule(_ offset: Int) {
        let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        if state.scheduleTask(capture, day: CaptureCalendar.dayString(day), time: capture.taskPlanning?.plannedTime) { showSchedule = false }
        else { error = "Could not save. Try again." }
    }
}
