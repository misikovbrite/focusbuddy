import SwiftUI

// MARK: - Уровень внимания (0.0 - 1.0)

class AttentionState: ObservableObject {
    @Published var level: Double = 1.0  // 1.0 = полный фокус, 0.0 = отвлёкся
    @Published var mood: RobotMood = .happy
    @Published var isBored: Bool = false
    @Published var isBlinking: Bool = false
    @Published var eyeOpenness: Double = 1.0  // 1.0 = открыты, 0.0 = закрыты

    // История для паттернов
    var attentionHistory: [AttentionRecord] = []

    // Текущая сессия
    var sessionStart: Date = Date()
    var lastDistraction: Date?

    // Grace period — не ругаемся сразу, даём время вернуться
    var lookAwayStart: Date?
    let baseGracePeriod: TimeInterval = 2.0  // Базовые 2 секунды "прощения"

    // Для плавных переходов
    var targetLevel: Double = 1.0
    let levelSmoothingFactor: Double = 0.15  // Насколько быстро level приближается к target

    // Ссылка на настройки для памяти робота
    weak var settings: AppSettings?

    // Эффективный grace period с учётом strictness
    private var effectiveGracePeriod: TimeInterval {
        let multiplier = settings?.strictnessMode.gracePeriodMultiplier ?? 1.0
        return baseGracePeriod * multiplier
    }

    // Множитель decay с учётом strictness
    private var decayMultiplier: Double {
        return settings?.strictnessMode.attentionDecayMultiplier ?? 1.0
    }

    func updateAttention(faceVisible: Bool, lookingAtScreen: Bool, headAngle: Double) {
        let previousLevel = level

        // Учитываем время суток — ночью робот более снисходителен
        let timeMultiplier = TimeOfDay.current.robotEnergyLevel

        if faceVisible && lookingAtScreen {
            // Смотрит на экран — сбрасываем grace period
            lookAwayStart = nil
            // Постепенно восстанавливаем внимание (быстрее чем падает)
            targetLevel = min(1.0, targetLevel + 0.2)
        } else if faceVisible && !lookingAtScreen {
            // Смотрит в сторону — проверяем grace period
            if lookAwayStart == nil {
                lookAwayStart = Date()
            }

            let lookAwayDuration = Date().timeIntervalSince(lookAwayStart ?? Date())

            if lookAwayDuration < effectiveGracePeriod {
                // Ещё в grace period — не снижаем, но и не повышаем
                // Робот показывает что заметил, но пока не ругается
            } else {
                // Grace period прошёл — теперь снижаем
                let anglePenalty = min(headAngle / 0.5, 1.0) * 0.08
                targetLevel = max(0.0, targetLevel - (0.04 + anglePenalty) * timeMultiplier * decayMultiplier)
            }
        } else {
            // Не видно лица — тоже grace period
            if lookAwayStart == nil {
                lookAwayStart = Date()
            }

            let awayDuration = Date().timeIntervalSince(lookAwayStart ?? Date())

            if awayDuration < effectiveGracePeriod * 1.5 {
                // Больший grace period когда лица не видно (может пьёт кофе)
            } else {
                // Снижаем уровень (ночью медленнее)
                targetLevel = max(0.0, targetLevel - 0.08 * timeMultiplier * decayMultiplier)
            }
        }

        // Плавно приближаем level к targetLevel
        level = level + (targetLevel - level) * levelSmoothingFactor

        // Обновляем настроение с учётом времени суток
        updateMood()

        // Записываем историю
        if abs(previousLevel - level) > 0.1 {
            recordAttention()
        }
    }

    // Принудительно устанавливаем "отвлёкся" — для отвлекающих приложений
    func forceDistracted() {
        level = 0.1
        lastDistraction = Date()
        isBored = false  // Не скучает — активно недоволен!

        // Если часто игнорируют — робот становится грустнее вместо злого
        let ignoreCount = settings?.ignoreCount ?? 0
        if ignoreCount > 10 {
            mood = .sad  // Уже не злится, а грустит — устал
        } else if ignoreCount > 5 {
            mood = .skeptical  // Скептически смотрит — «опять?»
        } else {
            mood = .angry  // Злится на отвлекающие приложения
        }
    }

    // Для дебага — установить конкретное настроение
    func setMood(_ newMood: RobotMood) {
        mood = newMood
    }

    private func updateMood() {
        let timeOfDay = TimeOfDay.current

        // Проверяем, идёт ли Pomodoro работа
        let isWorking = settings?.pomodoroState == .working

        // Ночью робот становится сонным — НО только если не в режиме работы Pomodoro
        if timeOfDay == .night && level > 0.5 && !isWorking {
            mood = .sleepy
            isBored = false
            return
        }

        switch level {
        case 0.8...1.0:
            // Утром — особенно бодрый, или во время Pomodoro работы
            if timeOfDay == .morning || isWorking {
                mood = .proud  // Гордый что работаешь!
            } else {
                mood = .happy
            }
            isBored = false
        case 0.6..<0.8:
            mood = .neutral
            isBored = false
        case 0.4..<0.6:
            mood = .concerned
            isBored = true
        case 0.2..<0.4:
            mood = .worried
            isBored = true
        default:
            mood = .sad
            isBored = true
            lastDistraction = Date()
        }
    }

    private func recordAttention() {
        let record = AttentionRecord(
            timestamp: Date(),
            level: level,
            mood: mood
        )
        attentionHistory.append(record)

        // Храним только последние 1000 записей
        if attentionHistory.count > 1000 {
            attentionHistory.removeFirst(100)
        }
    }

    // Анализ паттернов
    func getAverageAttention(lastMinutes: Int) -> Double {
        let cutoff = Date().addingTimeInterval(-Double(lastMinutes * 60))
        let recent = attentionHistory.filter { $0.timestamp > cutoff }
        guard !recent.isEmpty else { return level }
        return recent.map { $0.level }.reduce(0, +) / Double(recent.count)
    }

    func getDistractionFrequency(lastMinutes: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(lastMinutes * 60))
        let recent = attentionHistory.filter { $0.timestamp > cutoff }
        return recent.filter { $0.level < 0.4 }.count
    }
}

// MARK: - Настроение робота

enum RobotMood: String, CaseIterable {
    // Основные состояния
    case happy      // 😊 Всё отлично
    case neutral    // 😐 Норм
    case concerned  // 🤔 Начинает беспокоиться
    case worried    // 😟 Волнуется
    case sad        // 😢 Грустит

    // Расширенные эмоции
    case proud      // 😌 Гордость — долго в фокусе
    case surprised  // 😲 Удивление — резко вернулся
    case sleepy     // 😴 Сонливость — поздно вечером
    case angry      // 😠 Возмущение — Instagram и т.п.
    case skeptical  // 🤨 Скептицизм — туда-сюда переключаешься
    case love       // 🥰 Любовь — редкое событие
    case celebrating // 🎉 Празднует — streak/достижение

    var eyeScale: Double {
        switch self {
        case .happy: return 1.0
        case .neutral: return 0.95
        case .concerned: return 0.9
        case .worried: return 0.85
        case .sad: return 0.75
        case .proud: return 0.85  // Прищуренные от довольства
        case .surprised: return 1.3  // Широко открытые
        case .sleepy: return 0.5  // Полузакрытые
        case .angry: return 0.7  // Сощуренные от злости
        case .skeptical: return 0.9
        case .love: return 1.1
        case .celebrating: return 1.2
        }
    }

    var eyeColor: Color {
        switch self {
        case .happy: return .green
        case .neutral: return .green.opacity(0.8)
        case .concerned: return .yellow
        case .worried: return .orange
        case .sad: return .red
        case .proud: return Color(red: 0.4, green: 0.8, blue: 0.4)  // Тёплый зелёный
        case .surprised: return .cyan
        case .sleepy: return .cyan  // Яркий голубой как у surprised
        case .angry: return .red
        case .skeptical: return .yellow
        case .love: return .pink
        case .celebrating: return Color(red: 1.0, green: 0.8, blue: 0.0)  // Золотой
        }
    }

    var pupilSize: Double {
        switch self {
        case .happy: return 1.0
        case .neutral: return 1.0
        case .concerned: return 0.9
        case .worried: return 0.8
        case .sad: return 0.7
        case .proud: return 0.9
        case .surprised: return 1.4  // Расширенные от удивления
        case .sleepy: return 0.6
        case .angry: return 0.6  // Маленькие от злости
        case .skeptical: return 0.85
        case .love: return 1.3  // Большие от любви
        case .celebrating: return 1.2
        }
    }

    // Асимметрия глаз (для скептицизма и др.)
    var leftEyeModifier: Double {
        switch self {
        case .skeptical: return 0.6  // Левый прищурен
        default: return 1.0
        }
    }

    var rightEyeModifier: Double {
        switch self {
        case .skeptical: return 1.1  // Правый открыт
        default: return 1.0
        }
    }

    // Положение бровей (-1 = нахмуренные, 0 = нормальные, 1 = поднятые)
    var browPosition: Double {
        switch self {
        case .happy: return 0.3
        case .neutral: return 0
        case .concerned: return 0.5
        case .worried: return 0.7
        case .sad: return -0.5
        case .proud: return 0.2
        case .surprised: return 1.0
        case .sleepy: return -0.3
        case .angry: return -0.8
        case .skeptical: return 0.3  // Одна бровь поднята
        case .love: return 0.4
        case .celebrating: return 0.8
        }
    }

    // Форма рта (0 = нейтральный, 1 = улыбка, -1 = грусть)
    var mouthShape: Double {
        switch self {
        case .happy: return 0.7
        case .neutral: return 0
        case .concerned: return -0.2
        case .worried: return -0.4
        case .sad: return -0.8
        case .proud: return 0.5
        case .surprised: return 0  // Рот "О"
        case .sleepy: return -0.1
        case .angry: return -0.6
        case .skeptical: return 0.2  // Кривая усмешка
        case .love: return 0.9
        case .celebrating: return 1.0
        }
    }

    // Рот открыт (для удивления, зевка)
    var mouthOpen: Double {
        switch self {
        case .surprised: return 0.8
        case .sleepy: return 0.3  // Зевает
        case .celebrating: return 0.5
        default: return 0
        }
    }

    // Румянец
    var blushIntensity: Double {
        switch self {
        case .love: return 0.8
        case .proud: return 0.3
        case .angry: return 0.5
        case .celebrating: return 0.4
        default: return 0
        }
    }

    // Положение антенны (0 = нормальное, 1 = возбуждённое, -1 = поникшее)
    var antennaPosition: Double {
        switch self {
        case .happy: return 0.3
        case .neutral: return 0
        case .concerned: return -0.2
        case .worried: return -0.4
        case .sad: return -0.8
        case .proud: return 0.5
        case .surprised: return 0.9
        case .sleepy: return -0.6
        case .angry: return 0.7  // Дёргается от злости
        case .skeptical: return 0.2
        case .love: return 0.6
        case .celebrating: return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .happy: return "Счастлив"
        case .neutral: return "Нейтральный"
        case .concerned: return "Обеспокоен"
        case .worried: return "Волнуется"
        case .sad: return "Грустит"
        case .proud: return "Гордится"
        case .surprised: return "Удивлён"
        case .sleepy: return "Сонный"
        case .angry: return "Злится"
        case .skeptical: return "Скептичен"
        case .love: return "Влюблён"
        case .celebrating: return "Празднует"
        }
    }
}

// MARK: - Запись истории

struct AttentionRecord {
    let timestamp: Date
    let level: Double
    let mood: RobotMood
}

// MARK: - Контекст приложения

enum AppContext {
    case working      // IDE, текстовый редактор
    case meeting      // Zoom, Meet, Teams
    case browsing     // Браузер
    case entertainment // YouTube, Netflix
    case distracting  // Instagram, TikTok, Twitter — робот бесится!
    case unknown

    // Отвлекающие сайты (проверяем в браузере)
    static let distractingSites = [
        "instagram", "tiktok", "twitter", "x.com",
        "facebook", "vk.com", "vk ", "reddit",
        "tinder", "bumble", "hinge",
        "9gag", "pikabu", "telegram",
        "youtube", "netflix", "twitch"
    ]

    // Отвлекающие приложения
    static let distractingApps = [
        "instagram", "tiktok", "twitter",
        "facebook", "messenger", "telegram",
        "whatsapp", "discord", "slack",
        "vk", "reddit"
    ]

    // Ссылка на настройки для проверки белого списка
    static var settings: AppSettings?

    static func detect() -> AppContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return .unknown
        }

        let appName = frontApp.localizedName?.lowercased() ?? ""
        let bundleId = frontApp.bundleIdentifier?.lowercased() ?? ""

        // Проверяем белый список — если сайт в белом списке, не считаем отвлекающим
        if let settings = settings {
            // Проверка приложений в белом списке
            for site in settings.whitelistedSites {
                if appName.contains(site) || bundleId.contains(site) {
                    return .working  // В белом списке — считаем работой
                }
            }
        }

        // Отвлекающие приложения — робот бесится!
        for app in distractingApps {
            if appName.contains(app) || bundleId.contains(app) {
                return .distracting
            }
        }

        // Митинги
        if appName.contains("zoom") || appName.contains("meet") ||
           appName.contains("teams") || appName.contains("facetime") ||
           bundleId.contains("zoom") || bundleId.contains("teams") {
            return .meeting
        }

        // IDE и редакторы
        if appName.contains("xcode") || appName.contains("code") ||
           appName.contains("sublime") || appName.contains("idea") ||
           appName.contains("vim") || appName.contains("terminal") ||
           appName.contains("iterm") || appName.contains("phpstorm") ||
           appName.contains("webstorm") || appName.contains("cursor") {
            return .working
        }

        // Развлечения
        if appName.contains("youtube") || appName.contains("netflix") ||
           appName.contains("twitch") || appName.contains("spotify") {
            return .entertainment
        }

        // Браузер — проверяем название окна на отвлекающие сайты
        if appName.contains("safari") {
            if let tabTitle = getSafariTabTitle()?.lowercased() {
                // Сначала проверяем белый список
                if let settings = settings {
                    for site in settings.whitelistedSites {
                        if tabTitle.contains(site) {
                            return .working
                        }
                    }
                }
                // Потом проверяем отвлекающие
                for site in distractingSites {
                    if tabTitle.contains(site) {
                        return .distracting
                    }
                }
            }
            return .browsing
        }

        if appName.contains("chrome") || appName.contains("firefox") || appName.contains("arc") {
            if let windowTitle = getActiveWindowTitle()?.lowercased() {
                // Сначала проверяем белый список
                if let settings = settings {
                    for site in settings.whitelistedSites {
                        if windowTitle.contains(site) {
                            return .working
                        }
                    }
                }
                // Потом проверяем отвлекающие
                for site in distractingSites {
                    if windowTitle.contains(site) {
                        return .distracting
                    }
                }
            }
            return .browsing
        }

        return .unknown
    }

    // Получаем заголовок вкладки Safari напрямую
    private static func getSafariTabTitle() -> String? {
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                return name of front document
            end if
        end tell
        return ""
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.stringValue
            }
        }
        return nil
    }

    // Получаем заголовок активного окна через AppleScript
    private static func getActiveWindowTitle() -> String? {
        let script = """
        tell application "System Events"
            set frontApp to first process whose frontmost is true
            try
                set windowTitle to name of first window of frontApp
                return windowTitle
            on error
                return ""
            end try
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return result.stringValue
            }
        }
        return nil
    }

    var allowedLookAway: Bool {
        switch self {
        case .meeting: return true
        case .entertainment: return true
        default: return false
        }
    }

    var strictness: Double {
        switch self {
        case .working: return 1.0
        case .browsing: return 0.8
        case .meeting: return 0.3
        case .entertainment: return 0.2
        case .distracting: return 1.5  // Повышенная строгость!
        case .unknown: return 0.7
        }
    }

    var isDistracting: Bool {
        self == .distracting
    }
}
