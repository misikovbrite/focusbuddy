import SwiftUI
import UserNotifications

class AppSettings: ObservableObject {
    // Main settings
    @Published var warningDelay: TimeInterval = 2.0
    @Published var distractedDelay: TimeInterval = 4.0
    @Published var soundEnabled: Bool = true
    @Published var sensitivity: Double = 0.4
    @Published var isPaused: Bool = false

    // Pomodoro
    @Published var pomodoroEnabled: Bool = false
    @Published var pomodoroWorkMinutes: Int = 25
    @Published var pomodoroBreakMinutes: Int = 5
    @Published var pomodoroState: PomodoroState = .idle
    @Published var pomodoroTimeRemaining: TimeInterval = 0
    private var pomodoroTimer: Timer?

    // Whitelist (allowed even if normally distracting)
    @Published var whitelistedSites: [String] = []

    // Robot memory
    @Published var ignoreCount: Int = 0
    @Published var totalFocusStreak: Int = 0
    @Published var lastSessionDate: Date?

    init() {
        loadSettings()
        requestNotificationPermission()
    }

    // MARK: - Pomodoro

    func startPomodoro() {
        pomodoroState = .working
        pomodoroTimeRemaining = TimeInterval(pomodoroWorkMinutes * 60)
        startPomodoroTimer()
    }

    func startBreak() {
        pomodoroState = .onBreak
        pomodoroTimeRemaining = TimeInterval(pomodoroBreakMinutes * 60)
        startPomodoroTimer()
        sendNotification(title: "Break time!", body: "Robot allows \(pomodoroBreakMinutes) minutes of rest.")
    }

    func stopPomodoro() {
        pomodoroState = .idle
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroTimeRemaining = 0
    }

    private func startPomodoroTimer() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.pomodoroTimeRemaining > 0 {
                self.pomodoroTimeRemaining -= 1
            } else {
                self.pomodoroTimerFinished()
            }
        }
    }

    private func pomodoroTimerFinished() {
        pomodoroTimer?.invalidate()

        if pomodoroState == .working {
            startBreak()
        } else if pomodoroState == .onBreak {
            pomodoroState = .working
            pomodoroTimeRemaining = TimeInterval(pomodoroWorkMinutes * 60)
            startPomodoroTimer()
            sendNotification(title: "Break is over!", body: "Time to focus again.")
        }
    }

    var pomodoroTimeFormatted: String {
        let minutes = Int(pomodoroTimeRemaining) / 60
        let seconds = Int(pomodoroTimeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Whitelist

    func addToWhitelist(_ site: String) {
        let cleaned = site.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty && !whitelistedSites.contains(cleaned) {
            whitelistedSites.append(cleaned)
            saveSettings()
        }
    }

    func removeFromWhitelist(_ site: String) {
        whitelistedSites.removeAll { $0 == site }
        saveSettings()
    }

    func isWhitelisted(_ site: String) -> Bool {
        let lower = site.lowercased()
        return whitelistedSites.contains { lower.contains($0) }
    }

    // MARK: - Robot memory

    func recordIgnore() {
        ignoreCount += 1
        saveSettings()
    }

    func resetIgnoreCount() {
        ignoreCount = 0
        saveSettings()
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func sendMotivationalNotification() {
        let messages = [
            ("Great work!", "You've been focused for \(pomodoroWorkMinutes) minutes!"),
            ("Keep it up!", "Robot is proud of you!"),
            ("Peak productivity!", "Almost time for a break!"),
            ("Awesome!", "You're doing great, keep going!")
        ]
        let message = messages.randomElement()!
        sendNotification(title: message.0, body: message.1)
    }

    // MARK: - Save/Load

    private func saveSettings() {
        UserDefaults.standard.set(whitelistedSites, forKey: "whitelistedSites")
        UserDefaults.standard.set(ignoreCount, forKey: "ignoreCount")
        UserDefaults.standard.set(totalFocusStreak, forKey: "totalFocusStreak")
        UserDefaults.standard.set(lastSessionDate, forKey: "lastSessionDate")
        UserDefaults.standard.set(pomodoroEnabled, forKey: "pomodoroEnabled")
        UserDefaults.standard.set(pomodoroWorkMinutes, forKey: "pomodoroWorkMinutes")
        UserDefaults.standard.set(pomodoroBreakMinutes, forKey: "pomodoroBreakMinutes")
    }

    private func loadSettings() {
        whitelistedSites = UserDefaults.standard.stringArray(forKey: "whitelistedSites") ?? []
        ignoreCount = UserDefaults.standard.integer(forKey: "ignoreCount")
        totalFocusStreak = UserDefaults.standard.integer(forKey: "totalFocusStreak")
        lastSessionDate = UserDefaults.standard.object(forKey: "lastSessionDate") as? Date
        pomodoroEnabled = UserDefaults.standard.bool(forKey: "pomodoroEnabled")

        let workMin = UserDefaults.standard.integer(forKey: "pomodoroWorkMinutes")
        if workMin > 0 { pomodoroWorkMinutes = workMin }

        let breakMin = UserDefaults.standard.integer(forKey: "pomodoroBreakMinutes")
        if breakMin > 0 { pomodoroBreakMinutes = breakMin }
    }
}

// MARK: - Pomodoro State

enum PomodoroState: String {
    case idle
    case working
    case onBreak

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .onBreak: return "On Break"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .working: return .green
        case .onBreak: return .blue
        }
    }
}

// MARK: - Time of Day

enum TimeOfDay {
    case morning    // 6:00 - 12:00
    case afternoon  // 12:00 - 18:00
    case evening    // 18:00 - 22:00
    case night      // 22:00 - 6:00

    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<22: return .evening
        default: return .night
        }
    }

    var robotEnergyLevel: Double {
        switch self {
        case .morning: return 1.0
        case .afternoon: return 0.9
        case .evening: return 0.7
        case .night: return 0.5
        }
    }

    var greeting: String {
        switch self {
        case .morning: return "Good morning!"
        case .afternoon: return "Have a productive day!"
        case .evening: return "Good evening!"
        case .night: return "It's getting late..."
        }
    }
}
