import SwiftUI
import AppKit
import Carbon

@main
struct FocusBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var eyesWindow: NSWindow?
    var viewModel: FocusViewModel?
    @Published var settings = AppSettings()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = FocusViewModel()
        viewModel?.configure(with: settings)

        // Связываем настройки с AppContext для проверки белого списка
        AppContext.settings = settings

        setupMenuBarEyes()
        setupStatusBarMenu()
        setupGlobalHotkeys()

        // Скрываем из дока
        NSApp.setActivationPolicy(.accessory)
    }

    func setupGlobalHotkeys() {
        // Глобальная горячая клавиша: Cmd+Shift+F для паузы/возобновления
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+Shift+F (F = keyCode 3)
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 3 {
                DispatchQueue.main.async {
                    self?.togglePause()
                }
            }
            // Cmd+Shift+P для Pomodoro (P = keyCode 35)
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 35 {
                DispatchQueue.main.async {
                    if self?.settings.pomodoroState == .idle {
                        self?.settings.startPomodoro()
                    } else {
                        self?.settings.stopPomodoro()
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "FocusBuddy")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        let statsItem = NSMenuItem(title: "Statistics", action: nil, keyEquivalent: "")
        statsItem.submenu = createStatsSubmenu()
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func createStatsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        if let vm = viewModel {
            submenu.addItem(NSMenuItem(title: "Focused: \(vm.focusStats.formattedFocusedTime)", action: nil, keyEquivalent: ""))
            submenu.addItem(NSMenuItem(title: "Distractions: \(vm.focusStats.distractionCount)", action: nil, keyEquivalent: ""))
            submenu.addItem(NSMenuItem(title: "Focus: \(String(format: "%.0f%%", vm.focusStats.focusPercentage))", action: nil, keyEquivalent: ""))
        }
        return submenu
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "FocusBuddy — Settings"
            settingsWindow?.center()
        }

        let settingsView = SettingsView(settings: settings, viewModel: viewModel!)
        settingsWindow?.contentView = NSHostingView(rootView: settingsView)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func togglePause() {
        settings.isPaused.toggle()
        if settings.isPaused {
            viewModel?.stopMonitoring()
        } else {
            viewModel?.startMonitoring()
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func setupMenuBarEyes() {
        // Один монолитный элемент — расширенный notch
        let notchWidth: CGFloat = 180
        let extensionWidth: CGFloat = 40  // Уменьшил на 20%
        let totalWidth = notchWidth + extensionWidth * 2
        let height: CGFloat = 32

        // Увеличенный размер окна для анимации расширения
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 170

        eyesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: maxWidth, height: maxHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = eyesWindow, let viewModel = viewModel else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false

        // Позиция — центрируем относительно notch (с учётом увеличенного окна)
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let x = screenFrame.midX - maxWidth / 2
            let y = screenFrame.maxY - maxHeight
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let notchView = NSHostingView(rootView: ExtendedNotchView(
            viewModel: viewModel,
            settings: settings,
            baseWidth: totalWidth,
            baseHeight: height,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onTogglePause: { [weak self] in
                self?.togglePause()
            },
            onStartPomodoro: { [weak self] in
                self?.settings.startPomodoro()
            },
            onStopPomodoro: { [weak self] in
                self?.settings.stopPomodoro()
            }
        ))
        window.contentView = notchView
        window.orderFrontRegardless()
    }
}

// MARK: - Окно настроек

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: FocusViewModel
    @State private var showDebug = false
    @State private var newWhitelistSite = ""

    var body: some View {
        TabView {
            // Main settings
            mainSettingsTab
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

            // Pomodoro
            pomodoroTab
                .tabItem {
                    Label("Pomodoro", systemImage: "timer")
                }

            // Whitelist
            whitelistTab
                .tabItem {
                    Label("Whitelist", systemImage: "checkmark.shield")
                }

            // Debug panel
            debugTab
                .tabItem {
                    Label("Debug", systemImage: "ant")
                }
        }
        .frame(width: 380, height: 520)
    }

    var mainSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Timing
                GroupBox("Timing") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Warning after: \(String(format: "%.1f", settings.warningDelay)) sec")
                                .font(.caption)
                            Slider(value: $settings.warningDelay, in: 1...5, step: 0.5)
                        }

                        VStack(alignment: .leading) {
                            Text("Distracted after: \(String(format: "%.1f", settings.distractedDelay)) sec")
                                .font(.caption)
                            Slider(value: $settings.distractedDelay, in: 2...10, step: 0.5)
                        }
                    }
                    .padding(8)
                }

                // Sound
                GroupBox("Sound") {
                    Toggle("Enable sounds", isOn: $settings.soundEnabled)
                        .padding(8)
                }

                // Sensitivity
                GroupBox("Sensitivity") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How far you need to look away:")
                            .font(.caption)
                        HStack {
                            Text("Low")
                                .font(.caption2)
                            Slider(value: $settings.sensitivity, in: 0.3...0.7, step: 0.1)
                            Text("High")
                                .font(.caption2)
                        }
                    }
                    .padding(8)
                }

                // Statistics
                GroupBox("Session") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Focused:")
                            Spacer()
                            Text(viewModel.focusStats.formattedFocusedTime)
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Distractions:")
                            Spacer()
                            Text("\(viewModel.focusStats.distractionCount)")
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Efficiency:")
                            Spacer()
                            Text(String(format: "%.0f%%", viewModel.focusStats.focusPercentage))
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(8)
                }

                // Reset button
                Button("Reset Statistics") {
                    viewModel.resetStats()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .onChange(of: settings.warningDelay) { _, new in
            viewModel.warningThreshold = new
        }
        .onChange(of: settings.distractedDelay) { _, new in
            viewModel.distractedThreshold = new
        }
    }

    // MARK: - Pomodoro Tab

    var pomodoroTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Статус Pomodoro
                GroupBox {
                    VStack(spacing: 12) {
                        // Большой таймер
                        Text(settings.pomodoroTimeFormatted)
                            .font(.system(size: 48, weight: .light, design: .monospaced))
                            .foregroundColor(settings.pomodoroState.color)

                        // Статус
                        HStack {
                            Circle()
                                .fill(settings.pomodoroState.color)
                                .frame(width: 8, height: 8)
                            Text(settings.pomodoroState.displayName)
                                .font(.headline)
                        }

                        // Control buttons
                        HStack(spacing: 12) {
                            if settings.pomodoroState == .idle {
                                Button("Start") {
                                    settings.startPomodoro()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            } else {
                                Button("Stop") {
                                    settings.stopPomodoro()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)

                                if settings.pomodoroState == .working {
                                    Button("Break") {
                                        settings.startBreak()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                }

                // Time settings
                GroupBox("Duration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Work:")
                            Spacer()
                            Stepper("\(settings.pomodoroWorkMinutes) min",
                                    value: $settings.pomodoroWorkMinutes,
                                    in: 5...60, step: 5)
                        }

                        HStack {
                            Text("Break:")
                            Spacer()
                            Stepper("\(settings.pomodoroBreakMinutes) min",
                                    value: $settings.pomodoroBreakMinutes,
                                    in: 1...30, step: 1)
                        }
                    }
                    .padding(8)
                }

                // Info
                GroupBox("How it works") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• During work, robot monitors your focus")
                            .font(.caption)
                        Text("• During breaks, distractions are allowed")
                            .font(.caption)
                        Text("• Notifications remind you when to switch")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(8)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Whitelist Tab

    var whitelistTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Add site
                GroupBox("Add Site") {
                    HStack {
                        TextField("e.g. notion", text: $newWhitelistSite)
                            .textFieldStyle(.roundedBorder)

                        Button("Add") {
                            if !newWhitelistSite.isEmpty {
                                settings.addToWhitelist(newWhitelistSite)
                                newWhitelistSite = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newWhitelistSite.isEmpty)
                    }
                    .padding(8)
                }

                // Current list
                GroupBox("Allowed Sites") {
                    if settings.whitelistedSites.isEmpty {
                        Text("Empty. Add sites that shouldn't be considered distracting.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(settings.whitelistedSites, id: \.self) { site in
                                HStack {
                                    Text(site)
                                    Spacer()
                                    Button {
                                        settings.removeFromWhitelist(site)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                        .padding(8)
                    }
                }

                // Default distracting list
                GroupBox("Distracting by Default") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instagram, TikTok, Twitter/X, Facebook, VK, Reddit, Telegram, YouTube, Netflix, Twitch")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("\nAdd a site to whitelist to prevent robot warnings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }

    var debugTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Emotion Test")
                    .font(.headline)

                Text("Click on an emotion to see it on the robot:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Сетка эмоций
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ForEach(RobotMood.allCases, id: \.self) { mood in
                        EmotionButton(
                            mood: mood,
                            isSelected: viewModel.attentionState.mood == mood
                        ) {
                            viewModel.attentionState.setMood(mood)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Current state
                GroupBox("Current State") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Emotion:")
                            Spacer()
                            Text(viewModel.attentionState.mood.displayName)
                                .foregroundColor(viewModel.attentionState.mood.eyeColor)
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Attention level:")
                            Spacer()
                            Text(String(format: "%.0f%%", viewModel.attentionState.level * 100))
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Bored:")
                            Spacer()
                            Text(viewModel.attentionState.isBored ? "Yes" : "No")
                                .fontWeight(.medium)
                        }
                    }
                    .padding(8)
                }

                // Robot preview
                GroupBox("Preview") {
                    HStack {
                        Spacer()
                        RobotFace(
                            mood: viewModel.attentionState.mood,
                            eyeOffset: .zero,
                            isBlinking: false,
                            eyeSquint: 1.0,
                            antennaGlow: true,
                            headTilt: 0,
                            bounce: 0
                        )
                        .scaleEffect(2.5)
                        .frame(height: 80)
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                }
            }
            .padding(20)
        }
    }
}

// Кнопка для расширенной панели — старый стиль
struct ExpandedButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(width: 60, height: 36)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// Минималистичная кнопка в стиле Dynamic Island
struct MinimalButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.6))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.white.opacity(isHovered ? 0.15 : 0.08))
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// Кнопка эмоции для дебаг-панели
struct EmotionButton: View {
    let mood: RobotMood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(mood.eyeColor)
                    .frame(width: 24, height: 24)
                    .shadow(color: mood.eyeColor.opacity(0.5), radius: isSelected ? 4 : 0)

                Text(mood.displayName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Расширенный Notch (монолитный элемент)

struct ExtendedNotchView: View {
    @ObservedObject var viewModel: FocusViewModel
    @ObservedObject var settings: AppSettings
    let baseWidth: CGFloat
    let baseHeight: CGFloat
    var onOpenSettings: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onStartPomodoro: (() -> Void)?
    var onStopPomodoro: (() -> Void)?

    @StateObject private var mouseTracker = MouseTracker()
    @State private var isBlinking: Bool = false
    @State private var bounce: CGFloat = 0
    @State private var headTilt: Double = 0
    @State private var antennaGlow: Bool = false
    @State private var blinkTimer: Timer?
    @State private var idleTimer: Timer?
    @State private var easterEggTimer: Timer?
    @State private var isHovered: Bool = false
    @State private var eyeSquint: CGFloat = 0  // Прищур глаз (0 = открыты, 1 = закрыты)
    @State private var breathe: CGFloat = 0  // Дыхание
    @State private var lookAroundOffset: CGFloat = 0  // Оглядывание
    @State private var isWinking: Bool = false  // Подмигивание
    @State private var showLoveEasterEgg: Bool = false  // Сердечки при двойном клике
    @State private var isExpanded: Bool = false  // Расширенная панель
    @State private var clickOutsideMonitor: Any?  // Монитор кликов вне панели

    private let notchBlack = Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

    // Размеры при наведении и расширении
    private var currentWidth: CGFloat {
        if isExpanded { return 380 }
        return isHovered ? baseWidth * 1.04 : baseWidth
    }
    private var currentHeight: CGFloat {
        if isExpanded { return 160 }
        return isHovered ? baseHeight * 1.04 : baseHeight
    }

    // Куда смотрят глаза — зависит от настроения и поведения
    private var effectiveEyeOffset: CGSize {
        let mood = viewModel.attentionState.mood

        // При warning/distracted/angry — смотрит прямо на пользователя
        if mood == .concerned || mood == .worried || mood == .sad || mood == .angry || mood == .skeptical {
            return .zero
        }

        // При сонливости — глаза вниз
        if mood == .sleepy {
            return CGSize(width: 0, height: 0.5)
        }

        // Иначе — следует за мышкой или смотрит в случайную сторону
        if mouseTracker.isFollowingMouse {
            return CGSize(
                width: mouseTracker.offset.width + lookAroundOffset,
                height: mouseTracker.offset.height
            )
        } else {
            return mouseTracker.randomLookOffset
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Монолитная форма — ОДИН элемент который растягивается ВНИЗ
                NotchWithEars(earRadius: isExpanded ? 16 : 6, bottomRadius: isExpanded ? 24 : 10)
                    .fill(notchBlack)
                    .frame(width: currentWidth, height: currentHeight)

                // Содержимое внутри
                ZStack {
                    VStack(spacing: 0) {
                        // Верхняя часть — таймер слева (только когда свёрнуто)
                        HStack {
                            if settings.pomodoroState != .idle && !isExpanded {
                                Text(settings.pomodoroTimeFormatted)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.leading, 6)
                            }
                            Spacer()
                        }
                        .frame(height: baseHeight)
                        .opacity(isExpanded ? 0 : 1)

                        // Расширенный контент — появляется плавно
                        if isExpanded {
                            expandedContent
                        }
                    }

                    // Робот — один, анимированный, перемещается из правого верхнего угла в центр
                    RobotFace(
                        mood: showLoveEasterEgg ? .love : viewModel.attentionState.mood,
                        eyeOffset: effectiveEyeOffset,
                        isBlinking: isBlinking,
                        isWinking: isWinking,
                        eyeSquint: eyeSquint,
                        antennaGlow: antennaGlow,
                        headTilt: headTilt,
                        bounce: bounce + breathe
                    )
                    .scaleEffect(isExpanded ? 2.5 : 1.0)
                    .offset(
                        x: isExpanded ? 0 : (currentWidth / 2 - 24),
                        y: isExpanded ? -10 : (-currentHeight / 2 + baseHeight / 2)
                    )
                }
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 400, height: 170, alignment: .top)
        .onTapGesture(count: 2) {
            // Двойной клик — пасхалка с сердечками
            triggerLoveEasterEgg()
        }
        .onTapGesture(count: 1) {
            // Одиночный клик — расширяем/сворачиваем панель
            toggleExpanded()
        }
            .contextMenu {
                // Быстрое меню по правому клику
                Button {
                    onTogglePause?()
                } label: {
                    Label(viewModel.settings?.isPaused == true ? "Resume" : "Pause",
                          systemImage: viewModel.settings?.isPaused == true ? "play.fill" : "pause.fill")
                }

                Divider()

                if viewModel.settings?.pomodoroState == .idle {
                    Button {
                        onStartPomodoro?()
                    } label: {
                        Label("Start Pomodoro", systemImage: "timer")
                    }
                } else {
                    Button {
                        onStopPomodoro?()
                    } label: {
                        Label("Stop Pomodoro", systemImage: "stop.fill")
                    }
                }

                Divider()

                Button {
                    onOpenSettings?()
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
            }
        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1), value: isHovered)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onHover { hovering in
            isHovered = hovering
            // При наведении — радостно щурится (закрывает глазки от удовольствия)
            withAnimation(.easeInOut(duration: 0.25)) {
                eyeSquint = hovering ? 0.3 : 0  // 0.3 = прищур, 0 = открыты
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: viewModel.attentionState.mood) { _, newMood in
            reactToMood(newMood)
        }
        .onChange(of: viewModel.cameraManager.isWaving) { _, isWaving in
            if isWaving {
                waveBack()
            }
        }
        .onChange(of: viewModel.cameraManager.isShowingStop) { _, isShowingStop in
            if isShowingStop {
                handleStopGesture()
            }
        }
    }

    // MARK: - Расширенный контент (минималистичный стиль Dynamic Island)

    var expandedContent: some View {
        VStack(spacing: 16) {
            // Статистика — фокус, (робот между ними — он перемещается сюда), отвлечения
            HStack(spacing: 20) {
                // Время в фокусе
                VStack(spacing: 2) {
                    Text(viewModel.focusStats.formattedFocusedTime)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundColor(.white)
                    Text("focused")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }

                // Место для робота (он перемещается сюда из верхней части)
                Spacer()
                    .frame(width: 70, height: 55)

                // Отвлечения
                VStack(spacing: 2) {
                    Text("\(viewModel.focusStats.distractionCount)")
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .foregroundColor(.white)
                    Text("distractions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.top, 8)

            // Кнопки — минималистичные
            HStack(spacing: 12) {
                MinimalButton(icon: settings.isPaused ? "play.fill" : "pause.fill") {
                    onTogglePause?()
                    collapsePanel()
                }

                if settings.pomodoroState == .idle {
                    MinimalButton(icon: "timer") {
                        onStartPomodoro?()
                        collapsePanel()
                    }
                } else {
                    MinimalButton(icon: "stop.fill") {
                        onStopPomodoro?()
                        collapsePanel()
                    }
                }

                MinimalButton(icon: "gearshape") {
                    onOpenSettings?()
                    collapsePanel()
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func startAnimations() {
        blinkTimer?.invalidate()
        idleTimer?.invalidate()
        easterEggTimer?.invalidate()

        // Запускаем таймер редких пасхалок
        startEasterEggTimer()

        // Моргание — случайное, естественное
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            if Double.random(in: 0...1) < 0.7 {
                blink()
            }
            // Иногда двойное моргание
            if Double.random(in: 0...1) < 0.15 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    blink()
                }
            }
        }

        // Пульсация антенны
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            antennaGlow = true
        }

        // Микро-дыхание — едва заметное движение вверх-вниз
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            breathe = 0.3
        }

        // Периодические живые действия
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let random = Double.random(in: 0...1)

            if viewModel.attentionState.isBored {
                // Скучает — оглядывается
                if random < 0.4 {
                    lookAround()
                } else if random < 0.7 {
                    // Наклон головы от скуки
                    withAnimation(.easeInOut(duration: 0.5)) {
                        headTilt = Double.random(in: -5...5)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            headTilt = 0
                        }
                    }
                }
            } else if random < 0.2 {
                // Иногда оглядывается даже когда не скучает
                lookAround()
            }
        }
    }

    private func lookAround() {
        // Глаза смотрят в сторону
        withAnimation(.easeInOut(duration: 0.3)) {
            lookAroundOffset = CGFloat.random(in: -1.5...1.5)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.3)) {
                lookAroundOffset = 0
            }
        }
    }

    private func blink() {
        isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isBlinking = false
        }
    }

    private func toggleExpanded() {
        if isExpanded {
            collapsePanel()
        } else {
            expandPanel()
        }
    }

    private func expandPanel() {
        // Очень эластичная анимация в стиле Dynamic Island
        withAnimation(.spring(response: 0.6, dampingFraction: 0.5, blendDuration: 0)) {
            isExpanded = true
        }

        // Добавляем монитор кликов вне панели
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [self] event in
            // Клик вне панели — сворачиваем
            DispatchQueue.main.async {
                collapsePanel()
            }
        }
    }

    private func collapsePanel() {
        // Убираем монитор
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        // Плавная эластичная анимация закрытия
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
            isExpanded = false
        }
    }

    private func wink() {
        // Подмигивание с небольшим наклоном головы
        withAnimation(.easeInOut(duration: 0.15)) {
            isWinking = true
            headTilt = 3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isWinking = false
                headTilt = 0
            }
        }
    }

    private func triggerLoveEasterEgg() {
        // Пасхалка с сердечками + романтичный звук
        SoundManager.shared.playLoveSound()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            showLoveEasterEgg = true
            bounce = -3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showLoveEasterEgg = false
                bounce = 0
            }
        }
    }

    private func waveBack() {
        // Robot waves back and toggles Pomodoro!

        // Toggle Pomodoro
        if settings.pomodoroState == .idle {
            settings.startPomodoro()
            SoundManager.shared.playPomodoroStart()
        } else {
            settings.stopPomodoro()
            SoundManager.shared.playPomodoroEnd()
        }

        // Wave animation - tilt head left-right repeatedly
        let waveDuration = 0.2

        // First wave
        withAnimation(.easeInOut(duration: waveDuration)) {
            headTilt = -15
            bounce = -2
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + waveDuration) {
            withAnimation(.easeInOut(duration: waveDuration)) {
                self.headTilt = 15
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + waveDuration * 2) {
            withAnimation(.easeInOut(duration: waveDuration)) {
                self.headTilt = -15
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + waveDuration * 3) {
            withAnimation(.easeInOut(duration: waveDuration)) {
                self.headTilt = 15
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + waveDuration * 4) {
            withAnimation(.easeInOut(duration: waveDuration)) {
                self.headTilt = -10
            }
        }

        // Return to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + waveDuration * 5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.headTilt = 0
                self.bounce = 0
            }
        }
    }

    private func handleStopGesture() {
        // Toggle between active monitoring and passive/chill mode
        if settings.pomodoroState == .working {
            // Switch to break - robot chills out, stops strict monitoring
            settings.startBreak()
        } else if settings.pomodoroState == .onBreak {
            // Back to work mode
            settings.pomodoroState = .working
            settings.pomodoroTimeRemaining = TimeInterval(settings.pomodoroWorkMinutes * 60)
            SoundManager.shared.playPomodoroStart()
        } else {
            // If idle, just toggle a chill mode flag
            settings.isPaused.toggle()
        }

        // Play click for feedback
        SoundManager.shared.playClick()

        // Robot reaction - close eyes briefly like "okay, I understand"
        withAnimation(.easeInOut(duration: 0.15)) {
            eyeSquint = 1.0  // Close eyes
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.eyeSquint = 0
            }
        }

        // Small nod
        withAnimation(.easeInOut(duration: 0.2)) {
            bounce = 3
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.bounce = 0
            }
        }
    }

    private func startEasterEggTimer() {
        easterEggTimer?.invalidate()
        easterEggTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [self] _ in
            // Редкие пасхалки — примерно раз в 10 минут
            if Double.random(in: 0...1) < 0.1 {
                let easterEgg = Int.random(in: 0...2)
                switch easterEgg {
                case 0:
                    // Подмигивание
                    wink()
                case 1:
                    // Удивление
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                        viewModel.attentionState.setMood(.surprised)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        // Возвращаем нормальное настроение
                    }
                default:
                    // Короткое празднование
                    if viewModel.focusStats.focusPercentage > 80 {
                        withAnimation(.spring()) {
                            viewModel.attentionState.setMood(.celebrating)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            viewModel.attentionState.setMood(.happy)
                        }
                    }
                }
            }
        }
    }

    private func reactToMood(_ mood: RobotMood) {
        switch mood {
        case .happy:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                bounce = -2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring()) { bounce = 0 }
            }
        case .proud:
            // Гордо приподнимается
            withAnimation(.easeInOut(duration: 0.5)) {
                bounce = -1
                headTilt = 3
            }
        case .surprised:
            // Подпрыгивает от удивления
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                bounce = -3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring()) { bounce = 0 }
            }
        case .sleepy:
            // Медленно "засыпает"
            withAnimation(.easeInOut(duration: 0.8)) {
                bounce = 1
                headTilt = -8
            }
        case .angry:
            // Трясётся от злости
            withAnimation(.easeInOut(duration: 0.05).repeatCount(8, autoreverses: true)) {
                headTilt = 4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation { headTilt = 0 }
            }
        case .skeptical:
            // Наклоняет голову скептически
            withAnimation(.easeInOut(duration: 0.3)) {
                headTilt = 10
            }
        case .love:
            // Покачивается от счастья
            withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)) {
                headTilt = 5
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation { headTilt = 0 }
            }
        case .celebrating:
            // Прыгает от радости
            withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                bounce = -4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
                    bounce = -2
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring()) { bounce = 0 }
            }
        case .concerned:
            withAnimation(.easeInOut(duration: 0.15).repeatCount(2, autoreverses: true)) {
                headTilt = 6
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { headTilt = 0 }
            }
        case .worried:
            withAnimation(.easeInOut(duration: 0.06).repeatCount(6, autoreverses: true)) {
                bounce = -1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation { bounce = 0 }
            }
        case .sad:
            withAnimation(.easeInOut(duration: 0.4)) {
                bounce = 1
                headTilt = -4
            }
        case .neutral:
            withAnimation(.easeInOut(duration: 0.3)) {
                bounce = 0
                headTilt = 0
            }
        }
    }
}

// Форма notch с острыми ушками
struct NotchWithEars: Shape {
    let earRadius: CGFloat
    var bottomRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Начинаем слева сверху
        path.move(to: CGPoint(x: 0, y: 0))

        // Левое ушко — острый угол с небольшим скруглением
        path.addLine(to: CGPoint(x: 0, y: earRadius * 0.7))
        path.addQuadCurve(
            to: CGPoint(x: earRadius, y: earRadius),
            control: CGPoint(x: 0, y: earRadius)
        )

        // Левая сторона вниз до нижнего угла
        path.addLine(to: CGPoint(x: earRadius, y: rect.height - bottomRadius))

        // Левый нижний угол (скруглённый)
        path.addQuadCurve(
            to: CGPoint(x: earRadius + bottomRadius, y: rect.height),
            control: CGPoint(x: earRadius, y: rect.height)
        )

        // Нижняя сторона
        path.addLine(to: CGPoint(x: rect.width - earRadius - bottomRadius, y: rect.height))

        // Правый нижний угол (скруглённый)
        path.addQuadCurve(
            to: CGPoint(x: rect.width - earRadius, y: rect.height - bottomRadius),
            control: CGPoint(x: rect.width - earRadius, y: rect.height)
        )

        // Правая сторона вверх до ушка
        path.addLine(to: CGPoint(x: rect.width - earRadius, y: earRadius))

        // Правое ушко — острый угол с небольшим скруглением
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: earRadius * 0.7),
            control: CGPoint(x: rect.width, y: earRadius)
        )
        path.addLine(to: CGPoint(x: rect.width, y: 0))

        path.closeSubpath()
        return path
    }
}

// Форма расширения notch справа — с плавным переходом как у настоящего notch
struct NotchShapeRight: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let earRadius: CGFloat = 8  // Радиус "ушка" — плавный переход сверху

        // Начинаем сверху слева — прямой угол (стык с notch)
        path.move(to: CGPoint(x: 0, y: 0))

        // Верхняя сторона
        path.addLine(to: CGPoint(x: rect.width - earRadius, y: 0))

        // "Ушко" справа сверху — плавный переход вниз
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: earRadius),
            control: CGPoint(x: rect.width, y: 0)
        )

        // Правая сторона вниз
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - earRadius))

        // Правый нижний угол — скруглённый
        path.addQuadCurve(
            to: CGPoint(x: rect.width - earRadius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )

        // Нижняя сторона — прямой угол слева снизу
        path.addLine(to: CGPoint(x: 0, y: rect.height))

        path.closeSubpath()
        return path
    }
}

// Левое "ухо" — симметричное пустое расширение
struct NotchLeftEar: View {
    private let notchBlack = Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

    var body: some View {
        NotchShapeLeft()
            .fill(notchBlack)
            .frame(width: 52, height: 36)
    }
}

// Форма левого расширения — зеркальная правому
struct NotchShapeLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let earRadius: CGFloat = 8

        // Начинаем сверху справа — прямой угол (стык с notch)
        path.move(to: CGPoint(x: rect.width, y: 0))

        // Верхняя сторона влево
        path.addLine(to: CGPoint(x: earRadius, y: 0))

        // "Ушко" слева сверху — плавный переход вниз
        path.addQuadCurve(
            to: CGPoint(x: 0, y: earRadius),
            control: CGPoint(x: 0, y: 0)
        )

        // Левая сторона вниз
        path.addLine(to: CGPoint(x: 0, y: rect.height - earRadius))

        // Левый нижний угол — скруглённый
        path.addQuadCurve(
            to: CGPoint(x: earRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )

        // Нижняя сторона — прямой угол справа снизу
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))

        path.closeSubpath()
        return path
    }
}

// MARK: - Лицо робота с эмоциями

struct RobotFace: View {
    let mood: RobotMood
    let eyeOffset: CGSize
    let isBlinking: Bool
    var isWinking: Bool = false
    let eyeSquint: CGFloat
    let antennaGlow: Bool
    let headTilt: Double
    let bounce: CGFloat

    private let notchBlack = Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

    var body: some View {
        ZStack {
            // Антенна с реакцией на настроение
            VStack(spacing: 0) {
                Circle()
                    .fill(mood.eyeColor)
                    .frame(width: 4, height: 4)
                    .shadow(color: mood.eyeColor.opacity(antennaGlow ? 0.9 : 0.5), radius: antennaGlow ? 4 : 2)

                Rectangle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 1, height: 3)
            }
            .offset(y: -11 + CGFloat(mood.antennaPosition) * -2)
            .rotationEffect(.degrees(mood == .angry ? Double.random(in: -5...5) : 0))

            // Голова робота
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: 0.18))
                .frame(width: 26, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(white: 0.25), lineWidth: 0.5)
                )

            // Румянец (щёки)
            if mood.blushIntensity > 0 {
                HStack(spacing: 18) {
                    Circle()
                        .fill(Color.pink.opacity(mood.blushIntensity * 0.5))
                        .frame(width: 4, height: 4)
                        .blur(radius: 1)
                    Circle()
                        .fill(Color.pink.opacity(mood.blushIntensity * 0.5))
                        .frame(width: 4, height: 4)
                        .blur(radius: 1)
                }
                .offset(y: 2)
            }

            // Экран с глазами и лицом
            RoundedRectangle(cornerRadius: 3)
                .fill(notchBlack)
                .frame(width: 22, height: 12)
                .overlay(
                    VStack(spacing: 1) {
                        // Брови
                        HStack(spacing: 6) {
                            RobotBrow(mood: mood, isLeft: true)
                            RobotBrow(mood: mood, isLeft: false)
                        }
                        .offset(y: -1)

                        // Глаза
                        HStack(spacing: 4) {
                            RobotEye(
                                mood: mood,
                                mouseOffset: eyeOffset,
                                isBlinking: isBlinking || isWinking,  // Левый глаз закрывается при подмигивании
                                squint: eyeSquint,
                                isLeft: true
                            )
                            RobotEye(
                                mood: mood,
                                mouseOffset: eyeOffset,
                                isBlinking: isBlinking,  // Правый глаз остаётся открытым
                                squint: eyeSquint,
                                isLeft: false
                            )
                        }

                        // Рот
                        RobotMouth(mood: mood)
                            .offset(y: 0.5)
                    }
                )

            // Эффект сердечек при mood == .love
            if mood == .love {
                HeartParticles()
            }

            // Эффект конфетти при mood == .celebrating
            if mood == .celebrating {
                CelebrationParticles()
            }
        }
        .rotationEffect(.degrees(headTilt))
        .offset(y: bounce)
        .animation(.easeInOut(duration: 0.3), value: mood)
    }
}

// MARK: - Бровь робота

struct RobotBrow: View {
    let mood: RobotMood
    let isLeft: Bool

    private var rotation: Double {
        let base = mood.browPosition * 15
        // Для скептицизма — разные брови
        if mood == .skeptical {
            return isLeft ? -20 : 10
        }
        return isLeft ? -base : base
    }

    private var offsetY: Double {
        return -mood.browPosition * 1.5
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(mood.eyeColor.opacity(0.8))
            .frame(width: 5, height: 1)
            .rotationEffect(.degrees(rotation))
            .offset(y: offsetY)
    }
}

// MARK: - Рот робота

struct RobotMouth: View {
    let mood: RobotMood

    var body: some View {
        if mood.mouthOpen > 0.3 {
            // Открытый рот (удивление, зевок)
            Ellipse()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 4, height: 3 * mood.mouthOpen)
        } else if mood.mouthShape != 0 {
            // Улыбка или грусть
            MouthCurve(curvature: mood.mouthShape)
                .stroke(mood.eyeColor.opacity(0.7), lineWidth: 1)
                .frame(width: 6, height: 3)
        } else {
            // Нейтральный рот — просто линия
            Rectangle()
                .fill(mood.eyeColor.opacity(0.5))
                .frame(width: 4, height: 0.5)
        }
    }
}

// Форма рта — кривая
struct MouthCurve: Shape {
    let curvature: Double  // -1 = грусть, 1 = улыбка

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY

        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control: CGPoint(x: midX, y: midY + CGFloat(curvature) * rect.height)
        )

        return path
    }
}

// MARK: - Глаз робота (обновлённый)

struct RobotEye: View {
    let mood: RobotMood
    let mouseOffset: CGSize
    let isBlinking: Bool
    var squint: CGFloat = 1.0
    let isLeft: Bool

    private var eyeModifier: Double {
        isLeft ? mood.leftEyeModifier : mood.rightEyeModifier
    }

    private var eyeHeight: CGFloat {
        if isBlinking { return 1 }
        // squint: 0 = fully open, 1 = fully closed
        let openAmount = 1.0 - squint * 0.8  // At max squint, still 20% open
        return 6 * CGFloat(mood.eyeScale) * openAmount * CGFloat(eyeModifier)
    }

    private var eyeWidth: CGFloat {
        return 6 * CGFloat(eyeModifier)
    }

    var body: some View {
        ZStack {
            // Глаз
            Ellipse()
                .fill(mood.eyeColor)
                .frame(width: eyeWidth, height: eyeHeight)
                .shadow(color: mood.eyeColor.opacity(0.8), radius: 2)

            // Зрачок (показываем даже при прищуре, но не при моргании)
            if !isBlinking {
                Circle()
                    .fill(Color.black)
                    .frame(width: 5 * CGFloat(mood.pupilSize), height: 5 * CGFloat(mood.pupilSize))
                    .offset(
                        x: mouseOffset.width * 1.2,
                        y: mouseOffset.height * 1.2 + (mood == .sad ? 1 : 0)
                    )
                    .clipShape(Ellipse().size(width: eyeWidth + 2, height: eyeHeight + 2).offset(x: -1, y: -1))

                // Блик
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 1.5, height: 1.5)
                    .offset(x: -1, y: -1)
                    .opacity(eyeHeight > 2 ? 1 : 0)

                // Сердечки в глазах при love
                if mood == .love {
                    Text("♥")
                        .font(.system(size: 4))
                        .foregroundColor(.white)
                        .offset(x: 0.5, y: 0.5)
                }
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isBlinking)
        .animation(.easeInOut(duration: 0.2), value: mood)
    }
}

// MARK: - Эффекты частиц

struct HeartParticles: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Text("♥")
                    .font(.system(size: 4))
                    .foregroundColor(.pink)
                    .offset(
                        x: CGFloat.random(in: -10...10),
                        y: animate ? -15 : 0
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.5)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.3),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

struct CelebrationParticles: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill([Color.yellow, .green, .blue, .pink, .orange][i])
                    .frame(width: 2, height: 2)
                    .offset(
                        x: CGFloat.random(in: -15...15),
                        y: animate ? -20 : 5
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.0)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Старый глаз (для совместимости)

struct NotchEye: View {
    let mood: RobotMood
    let mouseOffset: CGSize
    let isBlinking: Bool
    var squint: CGFloat = 1.0
    let isLeft: Bool

    private var eyeHeight: CGFloat {
        if isBlinking { return 1.5 }
        return 7 * squint
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(mood.eyeColor)
                .frame(width: 7, height: eyeHeight)
                .shadow(color: mood.eyeColor.opacity(0.8), radius: 2)
                .animation(.easeInOut(duration: 0.08), value: isBlinking)
                .animation(.easeInOut(duration: 0.15), value: squint)

            if !isBlinking && squint > 0.3 {
                Circle()
                    .fill(Color.black)
                    .frame(width: 3, height: 3)
                    .offset(
                        x: mouseOffset.width * 1.5,
                        y: mouseOffset.height * 1.5 + (mood == .sad ? 1 : 0)
                    )
                    .animation(.easeOut(duration: 0.1), value: mouseOffset.width)

                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5, height: 1.5)
                    .offset(x: -1, y: -1)
            }
        }
    }
}

// MARK: - Старый мини-робот (не используется)

struct MenuBarRobotView: View {
    @ObservedObject var viewModel: FocusViewModel
    @StateObject private var mouseTracker = MouseTracker()
    @State private var bounce: CGFloat = 0
    @State private var isBlinking: Bool = false
    @State private var antennaGlow: Bool = false
    @State private var headTilt: Double = 0

    var body: some View {
        ZStack {
            // Антенна с пульсацией
            VStack(spacing: 0) {
                Circle()
                    .fill(viewModel.attentionState.mood.eyeColor)
                    .frame(width: 4, height: 4)
                    .shadow(color: viewModel.attentionState.mood.eyeColor.opacity(antennaGlow ? 0.8 : 0.3), radius: antennaGlow ? 4 : 2)

                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 1.5, height: 4)
            }
            .offset(y: -12)

            // Голова робота
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.25))
                .frame(width: 28, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
                )
                .rotationEffect(.degrees(headTilt))

            // Экран с глазами
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
                .frame(width: 24, height: 14)
                .overlay(
                    HStack(spacing: 6) {
                        LiveEye(
                            mood: viewModel.attentionState.mood,
                            mouseOffset: mouseTracker.offset,
                            isBlinking: isBlinking,
                            attentionLevel: viewModel.attentionState.level,
                            isLeft: true
                        )
                        LiveEye(
                            mood: viewModel.attentionState.mood,
                            mouseOffset: mouseTracker.offset,
                            isBlinking: isBlinking,
                            attentionLevel: viewModel.attentionState.level,
                            isLeft: false
                        )
                    }
                )
                .rotationEffect(.degrees(headTilt))
        }
        .offset(y: bounce)
        .onAppear {
            startIdleAnimations()
        }
        .onChange(of: viewModel.attentionState.mood) { _, newMood in
            reactToMood(newMood)
        }
        .frame(width: 40, height: 24)
    }

    private func startIdleAnimations() {
        // Моргание каждые 3-5 секунд
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if Double.random(in: 0...1) < 0.01 {  // ~раз в 3-4 секунды
                blink()
            }
        }

        // Пульсация антенны
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            antennaGlow = true
        }

        // Небольшие движения головы когда скучает
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if viewModel.attentionState.isBored {
                withAnimation(.easeInOut(duration: 0.5)) {
                    headTilt = Double.random(in: -3...3)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        headTilt = 0
                    }
                }
            }
        }
    }

    private func blink() {
        isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isBlinking = false
        }
    }

    private func reactToMood(_ mood: RobotMood) {
        switch mood {
        case .happy, .proud, .love, .celebrating:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                bounce = -3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring()) { bounce = 0 }
            }

        case .concerned, .skeptical:
            withAnimation(.easeInOut(duration: 0.2).repeatCount(2, autoreverses: true)) {
                headTilt = 5
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                headTilt = 0
            }

        case .worried, .angry:
            withAnimation(.easeInOut(duration: 0.1).repeatCount(4, autoreverses: true)) {
                bounce = -2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                bounce = 0
            }

        case .sad:
            withAnimation(.easeInOut(duration: 0.3)) {
                bounce = 2
                headTilt = -5
            }

        case .neutral, .sleepy, .surprised:
            withAnimation(.easeInOut(duration: 0.3)) {
                bounce = 0
                headTilt = 0
            }
        }
    }
}

// MARK: - Живой глаз с микро-анимациями

struct LiveEye: View {
    let mood: RobotMood
    let mouseOffset: CGSize
    let isBlinking: Bool
    let attentionLevel: Double
    let isLeft: Bool

    var body: some View {
        ZStack {
            // Глаз — размер зависит от настроения
            Ellipse()
                .fill(mood.eyeColor)
                .frame(width: 6 * mood.eyeScale, height: isBlinking ? 1 : 6 * mood.eyeScale)
                .shadow(color: mood.eyeColor.opacity(0.8), radius: 2)
                .animation(.easeInOut(duration: 0.1), value: isBlinking)

            // Зрачок — если не моргает
            if !isBlinking {
                Circle()
                    .fill(Color.black)
                    .frame(width: 6 * mood.pupilSize, height: 6 * mood.pupilSize)
                    .offset(
                        x: mouseOffset.width * 1.5,
                        y: mouseOffset.height * 1.5 + (mood == .sad ? 1 : 0)
                    )

                // Блик
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5, height: 1.5)
                    .offset(x: -1, y: -1)
            }
        }
    }
}

struct MiniEye: View {
    let state: RobotState
    let isLeft: Bool
    let mouseOffset: CGSize

    var body: some View {
        ZStack {
            // Глаз
            Circle()
                .fill(state.eyeColor)
                .frame(width: 6, height: 6)
                .shadow(color: state.eyeColor.opacity(0.8), radius: 2)

            // Зрачок - следит за курсором
            Circle()
                .fill(Color.black)
                .frame(width: 3, height: 3)
                .offset(x: mouseOffset.width * 1.5, y: mouseOffset.height * 1.5)
        }
    }
}

// MARK: - Отслеживание курсора с живым поведением

class MouseTracker: ObservableObject {
    @Published var offset: CGSize = .zero
    @Published var isFollowingMouse: Bool = true  // Следит ли за мышкой
    @Published var randomLookOffset: CGSize = .zero  // Случайное направление взгляда

    private var timer: Timer?
    private var behaviorTimer: Timer?
    private let robotPosition: CGPoint
    private var lastMousePosition: CGPoint = .zero
    private var mouseIdleTime: TimeInterval = 0

    init() {
        // Позиция робота — справа в расширенном notch
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            robotPosition = CGPoint(
                x: screenFrame.midX + 90 + 25,
                y: screenFrame.maxY - 16
            )
        } else {
            robotPosition = .zero
        }

        startTracking()
        startBehavior()
    }

    func startBehavior() {
        behaviorTimer?.invalidate()
        behaviorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateBehavior()
        }
    }

    private func updateBehavior() {
        let random = Double.random(in: 0...1)

        // Если мышка не двигалась — чаще отвлекается
        if mouseIdleTime > 2.0 {
            if random < 0.5 {
                // Смотрит в случайную сторону
                lookRandomDirection()
            } else if random < 0.7 {
                // Смотрит прямо (на пользователя)
                lookAtUser()
            }
        } else {
            // Мышка активна — иногда всё равно отвлекается
            if random < 0.15 {
                lookRandomDirection()
            } else if random < 0.25 {
                lookAtUser()
            }
        }
    }

    private func lookRandomDirection() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isFollowingMouse = false
                self.randomLookOffset = CGSize(
                    width: CGFloat.random(in: -1.5...1.5),
                    height: CGFloat.random(in: -1.0...1.0)
                )
            }
        }
        // Возвращается к мышке через некоторое время
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.8...2.0)) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.isFollowingMouse = true
                self?.randomLookOffset = .zero
            }
        }
    }

    func lookAtUser() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isFollowingMouse = false
                self.randomLookOffset = .zero  // Смотрит прямо
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.0...2.5)) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.isFollowingMouse = true
            }
        }
    }

    // Вызывается когда настроение меняется на warning/distracted
    func forceLokatUser() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isFollowingMouse = false
                self.randomLookOffset = .zero
            }
        }
    }

    func resumeFollowing() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isFollowingMouse = true
            }
        }
    }

    func startTracking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateMousePosition()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateMousePosition() {
        let mouseLocation = NSEvent.mouseLocation

        // Проверяем движение мышки
        let distance = hypot(mouseLocation.x - lastMousePosition.x, mouseLocation.y - lastMousePosition.y)
        if distance < 5 {
            mouseIdleTime += 0.1
        } else {
            mouseIdleTime = 0
        }
        lastMousePosition = mouseLocation

        // Вычисляем направление от робота к курсору
        let dx = mouseLocation.x - robotPosition.x
        let dy = mouseLocation.y - robotPosition.y

        // Нормализуем и ограничиваем смещение зрачка
        let maxOffset: CGFloat = 1.5
        let distToMouse = sqrt(dx * dx + dy * dy)

        if distToMouse > 0 {
            let normalizedX = (dx / distToMouse) * maxOffset
            let normalizedY = (dy / distToMouse) * maxOffset

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.1)) {
                    self.offset = CGSize(width: normalizedX, height: -normalizedY)  // Инвертируем Y
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
        behaviorTimer?.invalidate()
    }
}
