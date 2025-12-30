import SwiftUI
import UserNotifications

class AppSettings: ObservableObject {
    // Main settings
    @Published var warningDelay: TimeInterval = 2.0
    @Published var distractedDelay: TimeInterval = 4.0
    @Published var soundEnabled: Bool = true
    @Published var sensitivity: Double = 0.4
    @Published var isPaused: Bool = false

    // Strictness mode
    @Published var strictnessMode: StrictnessMode = .normal

    // Onboarding
    @Published var hasCompletedOnboarding: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var hasSeenWakeUpAnimation: Bool = false

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
    @Published var totalSessionsCompleted: Int = 0
    @Published var firstLaunchDate: Date?

    // Pomodoro Statistics
    @Published var pomodoroStats: PomodoroStatistics = PomodoroStatistics()
    @Published var dailyStats: [DailyFocusStats] = []

    init() {
        loadSettings()
        requestNotificationPermission()

        // First launch detection
        if firstLaunchDate == nil {
            firstLaunchDate = Date()
            showOnboarding = true
            saveSettings()
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showOnboarding = false
        saveSettings()
    }

    func markWakeUpAnimationSeen() {
        hasSeenWakeUpAnimation = true
        saveSettings()
    }

    func incrementSessionsCompleted() {
        totalSessionsCompleted += 1
        saveSettings()
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
            // Record completed pomodoro
            recordCompletedPomodoro()
            startBreak()
        } else if pomodoroState == .onBreak {
            // Record break time
            pomodoroStats.totalBreakMinutes += pomodoroBreakMinutes
            saveSettings()

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

    // MARK: - Statistics Recording

    func recordCompletedPomodoro() {
        // Update total stats
        pomodoroStats.totalPomodorosCompleted += 1
        pomodoroStats.totalWorkMinutes += pomodoroWorkMinutes

        // Update streak
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = pomodoroStats.lastPomodoroDate {
            let lastDay = Calendar.current.startOfDay(for: lastDate)
            let daysDiff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if daysDiff == 0 {
                // Same day — continue streak
            } else if daysDiff == 1 {
                // Next day — increment streak
                pomodoroStats.currentStreak += 1
            } else {
                // Missed days — reset streak
                pomodoroStats.currentStreak = 1
            }
        } else {
            pomodoroStats.currentStreak = 1
        }

        // Update longest streak
        if pomodoroStats.currentStreak > pomodoroStats.longestStreak {
            pomodoroStats.longestStreak = pomodoroStats.currentStreak
        }

        pomodoroStats.lastPomodoroDate = Date()

        // Weekly stats
        let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
        if let currentWeekStart = weekStart {
            if pomodoroStats.weekStartDate != currentWeekStart {
                // New week — reset weekly counter
                pomodoroStats.weekStartDate = currentWeekStart
                pomodoroStats.weeklyPomodorosCompleted = 1
            } else {
                pomodoroStats.weeklyPomodorosCompleted += 1
            }
        }

        // Daily stats
        updateDailyStats()

        // Check for best day
        let todayKey = DailyFocusStats.todayKey()
        if let todayStats = dailyStats.first(where: { $0.dateString == todayKey }) {
            if todayStats.pomodorosCompleted > pomodoroStats.bestDayPomodorosCount {
                pomodoroStats.bestDayPomodorosCount = todayStats.pomodorosCompleted
                pomodoroStats.bestDayDate = Date()
            }
        }

        totalSessionsCompleted += 1
        saveSettings()
    }

    private func updateDailyStats() {
        let todayKey = DailyFocusStats.todayKey()

        if let index = dailyStats.firstIndex(where: { $0.dateString == todayKey }) {
            dailyStats[index].pomodorosCompleted += 1
            dailyStats[index].focusMinutes += pomodoroWorkMinutes
        } else {
            var newDay = DailyFocusStats(dateString: todayKey)
            newDay.pomodorosCompleted = 1
            newDay.focusMinutes = pomodoroWorkMinutes
            dailyStats.append(newDay)
        }

        // Keep only last 30 days
        if dailyStats.count > 30 {
            dailyStats = Array(dailyStats.suffix(30))
        }
    }

    func recordDistraction() {
        let todayKey = DailyFocusStats.todayKey()

        if let index = dailyStats.firstIndex(where: { $0.dateString == todayKey }) {
            dailyStats[index].distractionCount += 1
        } else {
            var newDay = DailyFocusStats(dateString: todayKey)
            newDay.distractionCount = 1
            dailyStats.append(newDay)
        }
        saveSettings()
    }

    func getTodayStats() -> DailyFocusStats? {
        let todayKey = DailyFocusStats.todayKey()
        return dailyStats.first(where: { $0.dateString == todayKey })
    }

    func getWeekStats() -> [DailyFocusStats] {
        let calendar = Calendar.current
        let today = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        return dailyStats.filter { stat in
            if let date = stat.date {
                return date >= weekAgo
            }
            return false
        }.sorted { $0.dateString < $1.dateString }
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

    // MARK: - Robot personality comments

    func getGreeting() -> String? {
        let hour = Calendar.current.component(.hour, from: Date())

        // Check if first session today
        if let lastDate = lastSessionDate {
            let isNewDay = !Calendar.current.isDateInToday(lastDate)
            if isNewDay {
                if hour < 7 {
                    return "Wow, you're up early! Let's be productive."
                } else if hour < 10 {
                    return "Good morning! Ready to focus?"
                } else if hour > 22 {
                    return "Working late? I'll keep you company."
                }
            }
        }

        // Check days since first launch
        if let firstDate = firstLaunchDate {
            let daysSinceFirst = Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
            if daysSinceFirst == 7 {
                return "One week together! Great progress."
            } else if daysSinceFirst == 30 {
                return "A whole month! You're amazing."
            }
        }

        // Sessions milestones
        if totalSessionsCompleted == 10 {
            return "10 sessions done! Keep it up!"
        } else if totalSessionsCompleted == 50 {
            return "50 sessions! You're a focus master."
        } else if totalSessionsCompleted == 100 {
            return "100 sessions! Incredible dedication!"
        }

        return nil
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
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(hasSeenWakeUpAnimation, forKey: "hasSeenWakeUpAnimation")
        UserDefaults.standard.set(strictnessMode.rawValue, forKey: "strictnessMode")
        UserDefaults.standard.set(totalSessionsCompleted, forKey: "totalSessionsCompleted")
        UserDefaults.standard.set(firstLaunchDate, forKey: "firstLaunchDate")

        // Save Pomodoro Statistics
        if let statsData = try? JSONEncoder().encode(pomodoroStats) {
            UserDefaults.standard.set(statsData, forKey: "pomodoroStats")
        }

        // Save Daily Stats
        if let dailyData = try? JSONEncoder().encode(dailyStats) {
            UserDefaults.standard.set(dailyData, forKey: "dailyStats")
        }
    }

    private func loadSettings() {
        whitelistedSites = UserDefaults.standard.stringArray(forKey: "whitelistedSites") ?? []
        ignoreCount = UserDefaults.standard.integer(forKey: "ignoreCount")
        totalFocusStreak = UserDefaults.standard.integer(forKey: "totalFocusStreak")
        lastSessionDate = UserDefaults.standard.object(forKey: "lastSessionDate") as? Date
        pomodoroEnabled = UserDefaults.standard.bool(forKey: "pomodoroEnabled")
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        hasSeenWakeUpAnimation = UserDefaults.standard.bool(forKey: "hasSeenWakeUpAnimation")
        totalSessionsCompleted = UserDefaults.standard.integer(forKey: "totalSessionsCompleted")
        firstLaunchDate = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date

        if let modeRaw = UserDefaults.standard.string(forKey: "strictnessMode"),
           let mode = StrictnessMode(rawValue: modeRaw) {
            strictnessMode = mode
        }

        let workMin = UserDefaults.standard.integer(forKey: "pomodoroWorkMinutes")
        if workMin > 0 { pomodoroWorkMinutes = workMin }

        let breakMin = UserDefaults.standard.integer(forKey: "pomodoroBreakMinutes")
        if breakMin > 0 { pomodoroBreakMinutes = breakMin }

        // Load Pomodoro Statistics
        if let statsData = UserDefaults.standard.data(forKey: "pomodoroStats"),
           let stats = try? JSONDecoder().decode(PomodoroStatistics.self, from: statsData) {
            pomodoroStats = stats
        }

        // Load Daily Stats
        if let dailyData = UserDefaults.standard.data(forKey: "dailyStats"),
           let daily = try? JSONDecoder().decode([DailyFocusStats].self, from: dailyData) {
            dailyStats = daily
        }
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

// MARK: - Strictness Mode

enum StrictnessMode: String, CaseIterable {
    case chill = "chill"
    case normal = "normal"
    case strict = "strict"

    var displayName: String {
        switch self {
        case .chill: return "Chill"
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }

    var description: String {
        switch self {
        case .chill: return "Relaxed monitoring, rare warnings"
        case .normal: return "Balanced feedback"
        case .strict: return "Strict focus tracking"
        }
    }

    var icon: String {
        switch self {
        case .chill: return "leaf.fill"
        case .normal: return "circle.fill"
        case .strict: return "bolt.fill"
        }
    }

    // How long before robot starts warning (grace period multiplier)
    var gracePeriodMultiplier: Double {
        switch self {
        case .chill: return 2.0    // 2x longer grace period
        case .normal: return 1.0
        case .strict: return 0.5   // Half the grace period
        }
    }

    // How quickly attention drops
    var attentionDecayMultiplier: Double {
        switch self {
        case .chill: return 0.5    // Slower decay
        case .normal: return 1.0
        case .strict: return 1.5   // Faster decay
        }
    }

    // Volume of warning sounds
    var soundVolume: Float {
        switch self {
        case .chill: return 0.5    // Quieter
        case .normal: return 1.0
        case .strict: return 1.2   // Slightly louder
        }
    }
}

// MARK: - Pomodoro Statistics

struct PomodoroStatistics: Codable {
    var totalPomodorosCompleted: Int = 0
    var totalWorkMinutes: Int = 0
    var totalBreakMinutes: Int = 0
    var longestStreak: Int = 0
    var currentStreak: Int = 0
    var lastPomodoroDate: Date?

    // Weekly stats
    var weeklyPomodorosCompleted: Int = 0
    var weekStartDate: Date?

    // Best day
    var bestDayPomodorosCount: Int = 0
    var bestDayDate: Date?

    var averageDailyPomodoros: Double {
        guard let firstDate = weekStartDate else { return 0 }
        let days = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 1)
        return Double(weeklyPomodorosCompleted) / Double(days)
    }

    var totalFocusHours: Double {
        Double(totalWorkMinutes) / 60.0
    }
}

struct DailyFocusStats: Codable, Identifiable {
    var id: String { dateString }
    let dateString: String  // "2025-01-15"
    var pomodorosCompleted: Int = 0
    var focusMinutes: Int = 0
    var distractionCount: Int = 0
    var efficiencyPercent: Double = 100

    var date: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
