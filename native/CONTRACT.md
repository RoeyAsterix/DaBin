# Internal implementation contract

Source directory: Sources/DaBin. All Swift files compile in one target, Swift 5 mode, macOS 14+.

Initial coordination contract. Current implementation uses a versioned Core Data store; Capture is ObservableObject. See IMPLEMENTATION_NOTES.md for the toolchain fallback.
- enum CaptureKind: String, Codable, CaseIterable { link,text,image,video,pdf,document,ai,file }
- enum CaptureFilter: String, CaseIterable, Identifiable { all,links,files,media }; id:String; title:String; includes(_ kind:CaptureKind)->Bool
- final class Capture: ObservableObject, Identifiable with id:UUID, capturedAt:Date, captureDay:String, captureTimeZoneID:String, captureUTCOffsetSeconds:Int, kindRaw:String, originalURL:String?, originalText:String?, attachmentRelativePath:String?, originalFilename:String?, contentType:String?, byteCount:Int64?, title:String, previewDescription:String, thumbnailRelativePath:String?, previewState:String, previewError:String?, comment:String, reminderAt:Date?, reminderTimeZoneID:String?, reminderRevision:Int, notificationState:String, createdAt:Date, updatedAt:Date; computed kind:CaptureKind.
- @MainActor final class CaptureStore: ObservableObject, @Published private(set) var captures:[Capture], @Published var error:String?; let root:URL; init(root:URL? = nil) throws (real Core Data container, optional isolated root)
- capture(text:String, at:Date = Date(), timeZone:TimeZone = .current) throws -> [Capture]
- importFile(_ source:URL, at:Date = Date(), timeZone:TimeZone = .current, originalName:String? = nil) async throws -> Capture
- importData(_ data:Data, filename:String, at:Date = Date(), timeZone:TimeZone = .current) async throws -> Capture
- update(_ capture:Capture, comment:String, reminderAt:Date?, reminderTimeZoneID:String?) throws; bumps revision if reminder changes; preserves captured fields
- save() throws; managedURL(for capture:Capture)->URL?; refresh() throws
- enum CaptureCalendar { static func dayString(_ date:Date, timeZone:TimeZone = .current)->String }
- enum CaptureSearch { static func groups(captures:[Capture], query:String, filter:CaptureFilter)->[SearchGroup] }
- struct SearchGroup: Identifiable { let day:String; let entries:[SearchEntry]; var id:String {day} }
- struct SearchEntry: Identifiable { let capture:Capture; let isMatch:Bool; var id:UUID {capture.id} }

Services agent owns PreviewService.swift, ReminderService.swift.
- @MainActor final class PreviewService { init(store:CaptureStore); var enabled:Bool {get set}; func process(_ captures:[Capture]); func cancelNetwork() }
- Thumbnail paths must be relative to store.root. Only derived preview fields modified.
- @MainActor final class ReminderService: NSObject, UNUserNotificationCenterDelegate, ObservableObject { init(store:CaptureStore); @Published var status:String?; var onOpenCapture:((UUID)->Void)?; func reconcile() async; func saveReminder(for capture:Capture) async; func clearForCapture(_ id:UUID) async }
- User permission only after explicit reminder save. Serialized revision-aware scheduling. No private content in alerts.

UI agent owns BoardView.swift, AppState.swift.
- enum BoardRoute { daily, search, detail, reminders, settings }
- @MainActor final class AppState: ObservableObject { let store:CaptureStore; let previews:PreviewService; let reminders:ReminderService; @Published var route:BoardRoute; @Published var selectedDay:Date; @Published var filter:CaptureFilter; @Published var query:String; @Published var selectedCapture:Capture?; @Published var status:String?; var onDismiss:(()->Void)?; func openDaily(); func openSearch(); func openCapture(_ id:UUID, focus:String? = nil); func didCapture(_ captures:[Capture]); }
- struct BoardView: View { @ObservedObject var state:AppState }
- UI uses existing robot asset only if needed. No capture composer, drop area or add button.

Root owns AppDelegate/main, CornerController.swift, RobotView.swift, InputService.swift, build scripts, project, final integration/QA.
