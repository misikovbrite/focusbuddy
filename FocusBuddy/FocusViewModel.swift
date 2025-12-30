import SwiftUI
import Combine

class FocusViewModel: ObservableObject {
    @Published var robotState: RobotState = .focused
    @Published var focusStats = FocusStats()
    @Published var attentionState = AttentionState()

    let cameraManager = CameraManager()
    var settings: AppSettings?

    private var stateTimer: Timer?
    private var motivationTimer: Timer?
    private var wasDistracted = false
    private var noFaceStartTime: Date?
    private var currentContext: AppContext = .unknown
    private var lastMotivationalNotification: Date?

    // Настройки времени (в секундах)
    var warningThreshold: TimeInterval = 2.0
    var distractedThreshold: TimeInterval = 4.0

    init() {
        cameraManager.requestAuthorization()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startMonitoring()
        }
    }

    // Устанавливаем настройки и связываем с AttentionState
    func configure(with settings: AppSettings) {
        self.settings = settings
        self.attentionState.settings = settings
    }

    func startMonitoring() {
        stateTimer?.invalidate()
        motivationTimer?.invalidate()

        // Обновляем состояние 2 раза в секунду вместо 3+
        stateTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateState()
        }

        if let timer = stateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        // Проверяем мотивационные уведомления каждые 5 минут
        motivationTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkMotivationalNotification()
        }
    }

    private func checkMotivationalNotification() {
        guard let settings = settings else { return }

        // Не отправляем слишком часто
        if let last = lastMotivationalNotification,
           Date().timeIntervalSince(last) < 600 { // Минимум 10 минут между уведомлениями
            return
        }

        // Отправляем мотивацию если фокус хороший
        if focusStats.focusPercentage > 80 && focusStats.focusedTime > 600 { // 10+ минут в фокусе
            settings.sendMotivationalNotification()
            lastMotivationalNotification = Date()
        }
    }

    func stopMonitoring() {
        stateTimer?.invalidate()
        stateTimer = nil
        motivationTimer?.invalidate()
        motivationTimer = nil
        cameraManager.stopSession()
    }

    private func updateState() {
        // Определяем контекст (какое приложение активно)
        currentContext = AppContext.detect()

        // Если на перерыве Pomodoro — отвлекающие сайты OK
        if let settings = settings, settings.pomodoroState == .onBreak {
            // На перерыве не ругаемся
            if attentionState.mood == .angry || attentionState.mood == .worried {
                attentionState.setMood(.happy)
            }
            focusStats.addFocusedTime(0.5)
            updateLegacyState()
            return
        }

        // Если открыто отвлекающее приложение — сразу бесимся! (работает всегда)
        if currentContext.isDistracting {
            attentionState.forceDistracted()
            updateLegacyState()
            focusStats.addDistractedTime(0.5)
            // Записываем игнорирование
            settings?.recordIgnore()
            return
        }

        // Camera face tracking only works during active Pomodoro session
        let isPomodoroActive = settings?.pomodoroState == .working

        if isPomodoroActive {
            // Pomodoro active — track face and attention
            let isFaceVisible = cameraManager.isFaceDetected
            let headAngle = cameraManager.headAngle

            // Определяем смотрит ли на экран с учётом контекста
            let isLookingAtScreen: Bool
            if currentContext.allowedLookAway {
                // В митинге/видео — можно смотреть в сторону
                isLookingAtScreen = isFaceVisible
            } else {
                isLookingAtScreen = isFaceVisible && headAngle < 0.4
            }

            // Обновляем уровень внимания (плавно)
            attentionState.updateAttention(
                faceVisible: isFaceVisible,
                lookingAtScreen: isLookingAtScreen,
                headAngle: headAngle
            )

            // Статистика (интервал 0.5 сек)
            if attentionState.level > 0.6 {
                focusStats.addFocusedTime(0.5)
            } else if attentionState.level < 0.3 {
                focusStats.addDistractedTime(0.5)
            }
        } else {
            // Pomodoro not active — robot stays neutral/happy, no face tracking
            if attentionState.mood != .happy && attentionState.mood != .neutral {
                attentionState.setMood(.neutral)
            }
        }

        // Обновляем старый robotState для совместимости
        updateLegacyState()
    }

    private func updateLegacyState() {
        let previousState = robotState

        switch attentionState.mood {
        case .happy, .proud, .love, .celebrating:
            if wasDistracted {
                robotState = .welcomeBack
                wasDistracted = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    if self?.robotState == .welcomeBack {
                        self?.robotState = .focused
                    }
                }
            } else if robotState != .welcomeBack {
                robotState = .focused
            }
        case .neutral, .sleepy, .surprised:
            if robotState != .welcomeBack {
                robotState = .focused
            }
        case .concerned, .skeptical:
            robotState = .warning
        case .worried, .angry:
            robotState = .warning
        case .sad:
            robotState = .distracted
            wasDistracted = true
        }

        if previousState != robotState {
            focusStats.recordStateChange(to: robotState)

            // Звуки
            switch robotState {
            case .warning:
                SoundManager.shared.playWarningSound()
            case .distracted:
                SoundManager.shared.playDistractedSound()
            case .welcomeBack:
                SoundManager.shared.playWelcomeBackSound()
            default:
                break
            }
        }
    }

    func resetStats() {
        focusStats = FocusStats()
        attentionState.attentionHistory.removeAll()
    }

    deinit {
        stateTimer?.invalidate()
    }
}

// MARK: - Статистика

struct FocusStats {
    var focusedTime: TimeInterval = 0
    var distractedTime: TimeInterval = 0
    var distractionCount: Int = 0

    var focusPercentage: Double {
        let total = focusedTime + distractedTime
        guard total > 0 else { return 100 }
        return (focusedTime / total) * 100
    }

    var formattedFocusedTime: String {
        formatTime(focusedTime)
    }

    var formattedDistractedTime: String {
        formatTime(distractedTime)
    }

    mutating func addFocusedTime(_ seconds: TimeInterval) {
        focusedTime += seconds
    }

    mutating func addDistractedTime(_ seconds: TimeInterval) {
        distractedTime += seconds
    }

    mutating func recordStateChange(to state: RobotState) {
        if state == .distracted {
            distractionCount += 1
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
