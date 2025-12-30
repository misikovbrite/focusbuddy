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
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "FocusBuddy"
            settingsWindow?.titlebarAppearsTransparent = true
            settingsWindow?.titleVisibility = .hidden
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

// MARK: - Окно настроек (Redesigned)

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: FocusViewModel
    @State private var selectedTab: SettingsTab = .general
    @State private var newWhitelistSite = ""
    @State private var robotMood: RobotMood = .happy
    @State private var isHoveringRobot = false

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case pomodoro = "Pomodoro"
        case statistics = "Statistics"
        case whitelist = "Whitelist"
        case debug = "Debug"

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .pomodoro: return "timer"
            case .statistics: return "chart.bar"
            case .whitelist: return "checkmark.shield"
            case .debug: return "ant"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebarView
                .frame(width: 180)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)

            // Content
            ScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalContent
                    case .pomodoro:
                        pomodoroContent
                    case .statistics:
                        statisticsContent
                    case .whitelist:
                        whitelistContent
                    case .debug:
                        debugContent
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    // Настроение робота в зависимости от strictness mode
    private var strictnessMood: RobotMood {
        switch settings.strictnessMode {
        case .chill: return .sleepy      // Расслабленный, полузакрытые глаза
        case .normal: return .happy      // Обычный, довольный
        case .strict: return .proud      // Собранный, серьёзный но не злой
        }
    }

    // Цвет glow в зависимости от strictness
    private var strictnessGlowColor: Color {
        switch settings.strictnessMode {
        case .chill: return .green
        case .normal: return .blue
        case .strict: return .orange
        }
    }

    // Наклон головы робота
    private var strictnessHeadTilt: Double {
        switch settings.strictnessMode {
        case .chill: return -3       // Слегка наклонена, расслаблен
        case .normal: return 0       // Прямо
        case .strict: return 2       // Слегка приподнята, внимателен
        }
    }

    var sidebarView: some View {
        VStack(spacing: 0) {
            // Robot header
            VStack(spacing: 8) {
                ZStack {
                    // Glow effect — меняется от strictness mode
                    Circle()
                        .fill(isHoveringRobot ? robotMood.eyeColor.opacity(0.2) : strictnessGlowColor.opacity(0.15))
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                        .animation(.easeInOut(duration: 0.4), value: settings.strictnessMode)

                    // Второй слой glow для strict mode — более интенсивный
                    if settings.strictnessMode == .strict {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .blur(radius: 30)
                    }

                    RobotFace(
                        mood: isHoveringRobot ? robotMood : strictnessMood,
                        eyeOffset: .zero,
                        isBlinking: false,
                        eyeSquint: isHoveringRobot ? 0.3 : (settings.strictnessMode == .chill ? 0.4 : 0),
                        antennaGlow: true,
                        headTilt: isHoveringRobot ? 5 : strictnessHeadTilt,
                        bounce: 0
                    )
                    .scaleEffect(2.8)
                    .animation(.easeInOut(duration: 0.3), value: settings.strictnessMode)
                }
                .frame(height: 70)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHoveringRobot = hovering
                        if hovering {
                            robotMood = .love
                        } else {
                            robotMood = strictnessMood
                        }
                    }
                }

                Text("FocusBuddy")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                // Status pill — показывает и strictness mode
                HStack(spacing: 4) {
                    Circle()
                        .fill(strictnessGlowColor)
                        .frame(width: 6, height: 6)
                    Text(settings.strictnessMode.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(strictnessGlowColor.opacity(0.1))
                .cornerRadius(10)
                .animation(.easeInOut(duration: 0.2), value: settings.strictnessMode)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 16)

            // Navigation items
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SidebarItem(
                        icon: tab.icon,
                        title: tab.rawValue,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)

            Spacer()

            // Version info
            Text("v1.0.0")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 16)
        }
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - General Content

    var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            SectionHeader(title: "Settings", subtitle: "Customize your focus experience")

            // Strictness Mode Card
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Focus Mode", systemImage: "brain.head.profile")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        ForEach(StrictnessMode.allCases, id: \.self) { mode in
                            StrictnessPill(
                                mode: mode,
                                isSelected: settings.strictnessMode == mode
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    settings.strictnessMode = mode
                                }
                            }
                        }
                    }

                    Text(settings.strictnessMode.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Timing Card
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Timing", systemImage: "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    // Warning slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Warning delay")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(String(format: "%.1f", settings.warningDelay))s")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                        CustomSlider(value: $settings.warningDelay, range: 1...5, color: .yellow)
                    }

                    // Distracted slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Distraction threshold")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(String(format: "%.1f", settings.distractedDelay))s")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        CustomSlider(value: $settings.distractedDelay, range: 2...10, color: .orange)
                    }
                }
            }
            .onChange(of: settings.warningDelay) { _, new in
                viewModel.warningThreshold = new
            }
            .onChange(of: settings.distractedDelay) { _, new in
                viewModel.distractedThreshold = new
            }

            // Sound & Sensitivity
            HStack(spacing: 16) {
                // Sound toggle
                SettingsCard {
                    HStack {
                        Label("Sound", systemImage: settings.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Toggle("", isOn: $settings.soundEnabled)
                            .toggleStyle(.switch)
                            .scaleEffect(0.8)
                    }
                }

                // Sensitivity
                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Sensitivity", systemImage: "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        CustomSlider(value: $settings.sensitivity, range: 0.3...0.7, color: .blue)
                    }
                }
            }

            // Session Stats Card
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Today's Session", systemImage: "chart.bar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            viewModel.resetStats()
                        } label: {
                            Text("Reset")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 16) {
                        StatBadge(
                            value: viewModel.focusStats.formattedFocusedTime,
                            label: "Focused",
                            color: .green
                        )
                        StatBadge(
                            value: "\(viewModel.focusStats.distractionCount)",
                            label: "Distractions",
                            color: .orange
                        )
                        StatBadge(
                            value: String(format: "%.0f%%", viewModel.focusStats.focusPercentage),
                            label: "Efficiency",
                            color: .blue
                        )
                    }
                }
            }
        }
    }

    // MARK: - Pomodoro Content

    var pomodoroContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Pomodoro Timer", subtitle: "Stay focused with timed work sessions")

            // Timer display
            SettingsCard {
                VStack(spacing: 16) {
                    // Big timer with ring
                    ZStack {
                        // Background ring
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 8)
                            .frame(width: 140, height: 140)

                        // Progress ring
                        if settings.pomodoroState != .idle {
                            Circle()
                                .trim(from: 0, to: pomodoroProgress)
                                .stroke(
                                    settings.pomodoroState.color,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: pomodoroProgress)
                        }

                        VStack(spacing: 4) {
                            Text(settings.pomodoroTimeFormatted)
                                .font(.system(size: 36, weight: .light, design: .monospaced))
                                .foregroundColor(settings.pomodoroState == .idle ? .secondary : settings.pomodoroState.color)

                            Text(settings.pomodoroState.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Control buttons
                    HStack(spacing: 12) {
                        if settings.pomodoroState == .idle {
                            PomodoroButton(title: "Start Focus", color: .green) {
                                settings.startPomodoro()
                                SoundManager.shared.playPomodoroStart()
                            }
                        } else {
                            PomodoroButton(title: "Stop", color: .red, isSecondary: true) {
                                settings.stopPomodoro()
                            }

                            if settings.pomodoroState == .working {
                                PomodoroButton(title: "Take Break", color: .blue) {
                                    settings.startBreak()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Duration settings
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Duration", systemImage: "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 24) {
                        DurationPicker(
                            title: "Work",
                            value: $settings.pomodoroWorkMinutes,
                            range: 5...60,
                            step: 5,
                            color: .green
                        )

                        DurationPicker(
                            title: "Break",
                            value: $settings.pomodoroBreakMinutes,
                            range: 1...30,
                            step: 1,
                            color: .blue
                        )
                    }
                }
            }

            // Tips
            SettingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tips", systemImage: "lightbulb")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 6) {
                        TipRow(icon: "hand.wave", text: "Wave to start/stop timer")
                        TipRow(icon: "hand.raised", text: "Peace sign ✌️ to toggle break")
                        TipRow(icon: "bell", text: "Robot alerts you when distracted")
                    }
                }
            }
        }
    }

    private var pomodoroProgress: Double {
        guard settings.pomodoroState != .idle else { return 0 }
        let totalTime: Double
        if settings.pomodoroState == .working {
            totalTime = Double(settings.pomodoroWorkMinutes * 60)
        } else {
            totalTime = Double(settings.pomodoroBreakMinutes * 60)
        }
        guard totalTime > 0 else { return 0 }
        return 1.0 - (settings.pomodoroTimeRemaining / totalTime)
    }

    // MARK: - Whitelist Content

    var whitelistContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Whitelist", subtitle: "Sites that won't trigger robot warnings")

            // Add site
            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 18))

                    TextField("Add site (e.g. notion, figma)", text: $newWhitelistSite)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if !newWhitelistSite.isEmpty {
                        Button {
                            settings.addToWhitelist(newWhitelistSite)
                            newWhitelistSite = ""
                        } label: {
                            Text("Add")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Allowed sites
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Allowed Sites", systemImage: "checkmark.shield")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    if settings.whitelistedSites.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No sites added yet")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(settings.whitelistedSites, id: \.self) { site in
                                WhitelistChip(site: site) {
                                    settings.removeFromWhitelist(site)
                                }
                            }
                        }
                    }
                }
            }

            // Blocked by default
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Blocked by Default", systemImage: "nosign")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    FlowLayout(spacing: 8) {
                        ForEach(["Instagram", "TikTok", "Twitter", "Facebook", "Reddit", "YouTube", "Netflix", "Twitch"], id: \.self) { site in
                            Text(site)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }

                    Text("Add a site to whitelist above to allow it")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Statistics Content

    var statisticsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Statistics", subtitle: "Track your focus progress")

            // Overview Cards
            HStack(spacing: 12) {
                StatOverviewCard(
                    title: "Total Pomodoros",
                    value: "\(settings.pomodoroStats.totalPomodorosCompleted)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                StatOverviewCard(
                    title: "Focus Hours",
                    value: String(format: "%.1f", settings.pomodoroStats.totalFocusHours),
                    icon: "clock.fill",
                    color: .blue
                )

                StatOverviewCard(
                    title: "Current Streak",
                    value: "\(settings.pomodoroStats.currentStreak)",
                    subtitle: "days",
                    icon: "flame.fill",
                    color: .orange
                )
            }

            // Weekly Progress
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("This Week", systemImage: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(settings.pomodoroStats.weeklyPomodorosCompleted) pomodoros")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    // Week chart
                    WeeklyChart(stats: settings.getWeekStats())
                }
            }

            // Records & Achievements
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Records", systemImage: "trophy.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 16) {
                        RecordItem(
                            title: "Longest Streak",
                            value: "\(settings.pomodoroStats.longestStreak) days",
                            icon: "flame",
                            color: .orange
                        )

                        RecordItem(
                            title: "Best Day",
                            value: "\(settings.pomodoroStats.bestDayPomodorosCount) pomodoros",
                            icon: "star",
                            color: .yellow
                        )

                        RecordItem(
                            title: "Avg. Daily",
                            value: String(format: "%.1f", settings.pomodoroStats.averageDailyPomodoros),
                            icon: "chart.line.uptrend.xyaxis",
                            color: .green
                        )
                    }
                }
            }

            // Today's Details
            if let todayStats = settings.getTodayStats() {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Today", systemImage: "sun.max.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        HStack(spacing: 16) {
                            TodayStat(label: "Pomodoros", value: "\(todayStats.pomodorosCompleted)", color: .green)
                            TodayStat(label: "Focus Time", value: "\(todayStats.focusMinutes) min", color: .blue)
                            TodayStat(label: "Distractions", value: "\(todayStats.distractionCount)", color: .orange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Debug Content

    var debugContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Debug", subtitle: "Test robot emotions and states")

            // Emotion grid
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Test Emotions", systemImage: "face.smiling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(RobotMood.allCases, id: \.self) { mood in
                            EmotionChip(
                                mood: mood,
                                isSelected: viewModel.attentionState.mood == mood
                            ) {
                                viewModel.attentionState.setMood(mood)
                                robotMood = mood
                            }
                        }
                    }
                }
            }

            // Robot preview
            SettingsCard {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(viewModel.attentionState.mood.eyeColor.opacity(0.15))
                            .frame(width: 100, height: 100)
                            .blur(radius: 20)

                        RobotFace(
                            mood: viewModel.attentionState.mood,
                            eyeOffset: .zero,
                            isBlinking: false,
                            eyeSquint: 0,
                            antennaGlow: true,
                            headTilt: 0,
                            bounce: 0
                        )
                        .scaleEffect(3.5)
                    }
                    .frame(height: 100)
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
            }

            // State info
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Current State", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 16) {
                        DebugStat(label: "Mood", value: viewModel.attentionState.mood.displayName, color: viewModel.attentionState.mood.eyeColor)
                        DebugStat(label: "Attention", value: String(format: "%.0f%%", viewModel.attentionState.level * 100), color: .blue)
                        DebugStat(label: "Bored", value: viewModel.attentionState.isBored ? "Yes" : "No", color: viewModel.attentionState.isBored ? .orange : .green)
                    }
                }
            }

            // Camera debug
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Camera State", systemImage: "camera")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 16) {
                        DebugStat(
                            label: "Face",
                            value: viewModel.cameraManager.isFaceDetected ? "Yes" : "No",
                            color: viewModel.cameraManager.isFaceDetected ? .green : .red
                        )
                        DebugStat(
                            label: "Angle",
                            value: String(format: "%.2f", viewModel.cameraManager.headAngle),
                            color: viewModel.cameraManager.headAngle < 0.4 ? .green : .orange
                        )
                        DebugStat(
                            label: "FaceX",
                            value: String(format: "%.2f", viewModel.cameraManager.facePositionX),
                            color: .blue
                        )
                    }
                }
            }

            // Reset actions
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Button("Reset Wake-up Animation") {
                        settings.hasSeenWakeUpAnimation = false
                        UserDefaults.standard.set(false, forKey: "hasSeenWakeUpAnimation")
                    }
                    .buttonStyle(.bordered)

                    Text("Restart app to see wake-up animation again")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 4)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(12)
    }
}

struct StrictnessPill: View {
    let mode: StrictnessMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                Text(mode.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? modeColor : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var modeColor: Color {
        switch mode {
        case .chill: return .green
        case .normal: return .blue
        case .strict: return .orange
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 6)

                // Filled track
                Capsule()
                    .fill(color.opacity(0.8))
                    .frame(width: max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound) * geometry.size.width), height: 6)

                // Thumb
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
                    .offset(x: (value - range.lowerBound) / (range.upperBound - range.lowerBound) * (geometry.size.width - 16))
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = range.lowerBound + (gesture.location.x / geometry.size.width) * (range.upperBound - range.lowerBound)
                                value = min(max(newValue, range.lowerBound), range.upperBound)
                            }
                    )
            }
        }
        .frame(height: 16)
    }
}

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct PomodoroButton: View {
    let title: String
    let color: Color
    var isSecondary: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSecondary ? color : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSecondary ? color.opacity(isHovered ? 0.15 : 0.1) : color.opacity(isHovered ? 0.9 : 1))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct DurationPicker: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    if value > range.lowerBound {
                        value -= step
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(value <= range.lowerBound ? .secondary.opacity(0.3) : color)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 50)

                Button {
                    if value < range.upperBound {
                        value += step
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(value >= range.upperBound ? .secondary.opacity(0.3) : color)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
            }

            Text("min")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

struct WhitelistChip: View {
    let site: String
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(site)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .cornerRadius(14)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

struct EmotionChip: View {
    let mood: RobotMood
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(mood.eyeColor)
                    .frame(width: 20, height: 20)
                    .shadow(color: isSelected ? mood.eyeColor.opacity(0.5) : .clear, radius: 4)
                Text(mood.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? mood.eyeColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? mood.eyeColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct DebugStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Statistics Components

struct StatOverviewCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct WeeklyChart: View {
    let stats: [DailyFocusStats]

    private let daysOfWeek = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let dayStats = getDayStats(for: index)
                VStack(spacing: 4) {
                    // Bar
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 28, height: 60)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(for: dayStats.pomodorosCompleted))
                            .frame(width: 28, height: barHeight(for: dayStats.pomodorosCompleted))
                    }

                    // Day label
                    Text(daysOfWeek[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isToday(index) ? .primary : .secondary)

                    // Count
                    Text("\(dayStats.pomodorosCompleted)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func getDayStats(for weekdayIndex: Int) -> DailyFocusStats {
        let calendar = Calendar.current
        let today = Date()

        // Find the Monday of this week
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7  // Convert to Monday = 0
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return DailyFocusStats(dateString: "")
        }

        guard let targetDate = calendar.date(byAdding: .day, value: weekdayIndex, to: monday) else {
            return DailyFocusStats(dateString: "")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let targetKey = formatter.string(from: targetDate)

        return stats.first(where: { $0.dateString == targetKey }) ?? DailyFocusStats(dateString: targetKey)
    }

    private func isToday(_ weekdayIndex: Int) -> Bool {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let todayIndex = (weekday + 5) % 7
        return weekdayIndex == todayIndex
    }

    private func barHeight(for count: Int) -> CGFloat {
        let maxHeight: CGFloat = 60
        let maxCount = max(stats.map { $0.pomodorosCompleted }.max() ?? 1, 4)
        return max(4, CGFloat(count) / CGFloat(maxCount) * maxHeight)
    }

    private func barColor(for count: Int) -> Color {
        if count == 0 { return Color.gray.opacity(0.3) }
        if count >= 4 { return .green }
        if count >= 2 { return .blue }
        return .orange
    }
}

struct RecordItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

struct TodayStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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
    @StateObject private var microphoneMonitor = MicrophoneMonitor()
    @State private var isBlinking: Bool = false
    @State private var isSurprised: Bool = false  // Surprised by loud sound
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
    @State private var isYawning: Bool = false  // Зевота
    @State private var isStretching: Bool = false  // Потягивание
    @State private var microBounce: CGFloat = 0  // Микро-подпрыгивания
    @State private var lastIdleAction: Date = Date()  // Время последнего idle действия
    @State private var gestureRecognizedScale: CGFloat = 1.0  // Визуальный feedback жеста
    @State private var showOnboardingTip: Bool = false  // Показывать подсказку
    @State private var onboardingStep: Int = 0  // Шаг онбординга
    @State private var greetingMessage: String? = nil  // Персональное приветствие
    @State private var showGreeting: Bool = false  // Показывать приветствие

    // WOW Effects
    @State private var isWakingUp: Bool = false  // Анимация пробуждения
    @State private var wakeUpPhase: Int = 0  // Фаза пробуждения (0-5)
    @State private var peekOffset: CGFloat = -30  // Offset для "выглядывания" из notch
    @State private var isPeeking: Bool = false  // Выглядывает из норки
    @State private var stareTime: Date? = nil  // Время начала пристального взгляда
    @State private var isEmbarrassed: Bool = false  // Смущён от взгляда
    @State private var clickCount: Int = 0  // Счётчик быстрых кликов
    @State private var lastClickTime: Date = Date()  // Время последнего клика
    @State private var isGiggling: Bool = false  // Хихикает от кликов
    @State private var faceTrackingOffset: CGSize = .zero  // Offset от отслеживания лица
    @State private var wowEffectsTimer: Timer?  // Таймер для WOW эффектов

    private let notchBlack = Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))

    // Onboarding messages
    private let onboardingMessages = [
        "👋 Hi! I'm your Focus Buddy. Click me to expand!",
        "👆 Wave your hand to start/stop Pomodoro timer",
        "✌️ Show peace sign to toggle break mode",
        "🔴 I watch for distracting sites and alert you",
        "⚙️ Right-click me for quick settings"
    ]

    // Размеры при наведении и расширении
    private var currentWidth: CGFloat {
        if isExpanded { return 380 }
        return isHovered ? baseWidth * 1.02 : baseWidth  // Subtle hover effect
    }
    private var currentHeight: CGFloat {
        if isExpanded { return 160 }
        return isHovered ? baseHeight * 1.02 : baseHeight  // Subtle hover effect
    }

    // Squint для wake-up анимации
    private var wakeUpSquint: CGFloat {
        switch wakeUpPhase {
        case 0: return 1.0      // Закрыты
        case 1: return 0.8      // Чуть приоткрыты
        case 2: return 0.5      // Полуоткрыты
        case 3: return 0.2      // Почти открыты
        case 4: return 0.0      // Открыты
        case 5: return 0.3      // Прищур (осматривается)
        default: return 0.0
        }
    }

    // Прогресс Pomodoro (0.0 - 1.0)
    private var pomodoroProgress: Double {
        guard settings.pomodoroState != .idle else { return 0 }
        let totalTime: Double
        if settings.pomodoroState == .working {
            totalTime = Double(settings.pomodoroWorkMinutes * 60)
        } else {
            totalTime = Double(settings.pomodoroBreakMinutes * 60)
        }
        guard totalTime > 0 else { return 0 }
        return 1.0 - (settings.pomodoroTimeRemaining / totalTime)
    }

    // Куда смотрят глаза — зависит от настроения и поведения
    private var effectiveEyeOffset: CGSize {
        let mood = viewModel.attentionState.mood

        // При пробуждении — глаза медленно двигаются
        if isWakingUp {
            switch wakeUpPhase {
            case 0...2: return .zero  // Только открываются
            case 3: return CGSize(width: -0.5, height: 0)  // Смотрит влево
            case 4: return CGSize(width: 0.5, height: 0)   // Смотрит вправо
            case 5: return .zero  // Смотрит на пользователя
            default: return .zero
            }
        }

        // Смущён — отводит глаза
        if isEmbarrassed {
            return CGSize(width: 0.6, height: 0.3)  // Смотрит в сторону и вниз
        }

        // При warning/distracted/angry — смотрит прямо на пользователя
        if mood == .concerned || mood == .worried || mood == .sad || mood == .angry || mood == .skeptical {
            return .zero
        }

        // При сонливости — глаза вниз
        if mood == .sleepy {
            return CGSize(width: 0, height: 0.5)
        }

        // Следует за мышкой когда она активна
        if mouseTracker.isFollowingMouse {
            return CGSize(
                width: mouseTracker.offset.width + lookAroundOffset,
                height: mouseTracker.offset.height
            )
        }

        // Когда мышка неактивна — смотрит на пользователя через камеру (face tracking)
        // или в случайную сторону если face tracking недоступен
        if faceTrackingOffset != .zero {
            return faceTrackingOffset
        } else {
            return mouseTracker.randomLookOffset
        }
    }

    // Эффективный squint с учётом всех состояний
    private var effectiveSquint: CGFloat {
        if isWakingUp { return wakeUpSquint }
        if isEmbarrassed { return 0.4 }  // Прищуривается от смущения
        if isGiggling { return 0.5 }  // Прищуривается от смеха
        return eyeSquint
    }

    // Эффективное настроение
    private var effectiveMood: RobotMood {
        if showLoveEasterEgg { return .love }
        if isEmbarrassed { return .love }  // Смущённый = румянец
        if isSurprised { return .surprised }  // Удивлён громким звуком
        if isGiggling { return .happy }
        if isWakingUp && wakeUpPhase < 4 { return .sleepy }
        return viewModel.attentionState.mood
    }

    // Эффективный наклон головы
    private var effectiveHeadTilt: Double {
        if isWakingUp {
            switch wakeUpPhase {
            case 3: return -8  // Наклон влево
            case 4: return 8   // Наклон вправо
            case 5: return 3   // Лёгкий наклон (любопытство)
            default: return 0
            }
        }
        if isPeeking { return 5 }  // Любопытно выглядывает
        if isGiggling { return Double.random(in: -5...5) }  // Трясётся от смеха
        return headTilt
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
                    ZStack {
                        // Progress ring (only when Pomodoro active)
                        if settings.pomodoroState != .idle {
                            PomodoroProgressRing(
                                progress: pomodoroProgress,
                                isWorking: settings.pomodoroState == .working
                            )
                            .frame(width: isExpanded ? 70 : 28, height: isExpanded ? 70 : 28)
                        }

                        RobotFace(
                            mood: effectiveMood,
                            eyeOffset: effectiveEyeOffset,
                            isBlinking: isBlinking && !isWakingUp,
                            isWinking: isWinking,
                            eyeSquint: effectiveSquint,
                            antennaGlow: antennaGlow && !isWakingUp,
                            headTilt: effectiveHeadTilt,
                            bounce: bounce + breathe + microBounce + (isGiggling ? 2 : 0)
                        )
                    }
                    .scaleEffect((isExpanded ? 2.5 : 1.0) * gestureRecognizedScale)
                    .opacity(isWakingUp && wakeUpPhase == 0 ? 0.7 : 1.0)
                    .offset(
                        x: isExpanded ? 0 : (currentWidth / 2 - 24),
                        y: isExpanded ? -10 : (-currentHeight / 2 + baseHeight / 2)
                    )
                }
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
            }

            // Onboarding tooltip
            if showOnboardingTip && onboardingStep < onboardingMessages.count {
                OnboardingTooltip(
                    message: onboardingMessages[onboardingStep],
                    step: onboardingStep,
                    totalSteps: onboardingMessages.count,
                    onNext: {
                        withAnimation {
                            if onboardingStep < onboardingMessages.count - 1 {
                                onboardingStep += 1
                            } else {
                                showOnboardingTip = false
                                settings.completeOnboarding()
                            }
                        }
                    },
                    onSkip: {
                        withAnimation {
                            showOnboardingTip = false
                            settings.completeOnboarding()
                        }
                    }
                )
                .offset(y: currentHeight + 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Greeting banner
            if showGreeting, let message = greetingMessage {
                GreetingBanner(message: message, isShowing: $showGreeting)
                    .offset(y: currentHeight + 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 400, height: 170, alignment: .top)
        .onTapGesture(count: 2) {
            // Двойной клик — пасхалка с сердечками
            triggerLoveEasterEgg()
        }
        .onTapGesture(count: 1) {
            // Track quick clicks for giggling easter egg
            handleQuickClicks()
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

            // Track stare time for embarrassment easter egg
            if hovering && !isWakingUp {
                stareTime = Date()
            } else {
                stareTime = nil
                isEmbarrassed = false
            }
        }
        .onAppear {
            // WOW Effect: Wake-up animation on first launch
            if !settings.hasSeenWakeUpAnimation {
                startWakeUpAnimation()
                settings.markWakeUpAnimationSeen()
            } else {
                // Normal startup
                startAnimations()
            }

            // Show onboarding for first-time users (after wake-up if applicable)
            let onboardingDelay = settings.hasSeenWakeUpAnimation ? 1.5 : 4.0
            if settings.showOnboarding && !settings.hasCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + onboardingDelay) {
                    withAnimation {
                        showOnboardingTip = true
                    }
                }
            } else {
                // Show greeting if available
                if let greeting = settings.getGreeting() {
                    greetingMessage = greeting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            showGreeting = true
                        }
                    }
                    // Auto-hide after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                        withAnimation {
                            showGreeting = false
                        }
                    }
                }
            }

            // Update last session date
            settings.lastSessionDate = Date()
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
        .onChange(of: microphoneMonitor.isLoudSound) { _, isLoud in
            if isLoud {
                reactToLoudSound()
            }
        }
        .onChange(of: viewModel.cameraManager.isShowingHeart) { _, isShowingHeart in
            if isShowingHeart {
                reactToHeartGesture()
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
        wowEffectsTimer?.invalidate()

        // Запускаем таймер редких пасхалок
        startEasterEggTimer()

        // WOW Effects timer — stare detection and face tracking
        wowEffectsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Check stare time for embarrassment
            checkStareTime()
            // Update face tracking offset from camera
            updateFaceTracking()
        }

        // Start microphone monitoring for loud sound reactions
        microphoneMonitor.startMonitoring()

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

        // Дыхание — более заметное, естественное
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            breathe = 1.0
        }

        // Микро-подпрыгивания — очень мягкие
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            microBounce = 0.5
        }

        // Периодические живые действия
        idleTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            let random = Double.random(in: 0...1)
            let timeSinceLastAction = Date().timeIntervalSince(lastIdleAction)
            let isBored = viewModel.attentionState.isBored || settings.pomodoroState == .idle

            if isBored && timeSinceLastAction > 15 {
                // Долго idle — зевота или потягивание
                if random < 0.3 {
                    yawn()
                } else if random < 0.5 {
                    stretch()
                } else if random < 0.8 {
                    lookAround()
                }
            } else if isBored {
                // Скучает — оглядывается, наклоняет голову
                if random < 0.35 {
                    lookAround()
                } else if random < 0.6 {
                    // Наклон головы от скуки
                    withAnimation(.easeInOut(duration: 0.5)) {
                        headTilt = Double.random(in: -5...5)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            headTilt = 0
                        }
                    }
                }
            } else if random < 0.15 {
                // Иногда оглядывается даже когда не скучает
                lookAround()
            } else if random < 0.08 {
                // Редко — счастливый прыжок при хорошем фокусе
                if viewModel.attentionState.mood == .happy {
                    happyBounce()
                }
            }
        }
    }

    private func lookAround() {
        lastIdleAction = Date()
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

    private func yawn() {
        lastIdleAction = Date()
        isYawning = true

        // Глаза закрываются, голова немного назад
        withAnimation(.easeInOut(duration: 0.4)) {
            eyeSquint = 0.7
            bounce = 1
        }

        // Держим зевоту
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                self.eyeSquint = 0
                self.bounce = 0
                self.isYawning = false
            }
        }
    }

    private func stretch() {
        lastIdleAction = Date()
        isStretching = true

        // Вытягивается вверх
        withAnimation(.easeOut(duration: 0.5)) {
            bounce = -4
            headTilt = Double.random(in: -8...8)
        }

        // Расслабляется
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                self.bounce = 1
            }
        }

        // Возврат
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.bounce = 0
                self.headTilt = 0
                self.isStretching = false
            }
        }
    }

    private func happyBounce() {
        lastIdleAction = Date()

        // Маленький прыжок от радости
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            bounce = -2
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                self.bounce = 0
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

    // MARK: - WOW Effects

    /// Анимация пробуждения — робот просыпается в notch
    private func startWakeUpAnimation() {
        isWakingUp = true
        wakeUpPhase = 0

        // Фаза 0 → 1: Чуть приоткрывает глаза
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.4)) {
                wakeUpPhase = 1
            }
        }

        // Фаза 1 → 2: Полуоткрывает глаза
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                wakeUpPhase = 2
            }
        }

        // Фаза 2 → 3: Открывает глаза, смотрит влево
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.4)) {
                wakeUpPhase = 3
            }
        }

        // Фаза 3 → 4: Смотрит вправо
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                wakeUpPhase = 4
            }
        }

        // Фаза 4 → 5: Смотрит на пользователя, прищуривается (узнал!)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeInOut(duration: 0.3)) {
                wakeUpPhase = 5
            }
        }

        // Завершение анимации — робот ожил!
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                isWakingUp = false
                wakeUpPhase = 0
                antennaGlow = true
            }
            // Маленький прыжок радости
            happyBounce()
            SoundManager.shared.playHappyChirp()

            // Start regular animations after wake-up
            startAnimations()
        }
    }

    /// Робот выглядывает из notch при hover
    private func peekOut() {
        guard !isExpanded && !isPeeking else { return }

        isPeeking = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            peekOffset = 0
        }

        // Любопытно оглядывается
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            lookAround()
        }
    }

    private func peekBack() {
        guard isPeeking else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            peekOffset = -30
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPeeking = false
        }
    }

    /// Проверка на долгий взгляд — робот смущается
    private func checkStareTime() {
        guard let startTime = stareTime else { return }

        let staredFor = Date().timeIntervalSince(startTime)

        // Если смотрят больше 3 секунд — смущается
        if staredFor > 3.0 && !isEmbarrassed {
            withAnimation(.easeInOut(duration: 0.3)) {
                isEmbarrassed = true
            }
            SoundManager.shared.playHappyChirp()

            // Через 2 секунды перестаёт смущаться
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isEmbarrassed = false
                }
            }
        }
    }

    /// Обработка быстрых кликов — робот смеётся
    private func handleQuickClicks() {
        let now = Date()
        let timeSinceLastClick = now.timeIntervalSince(lastClickTime)

        if timeSinceLastClick < 0.5 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now

        // 5+ быстрых кликов — робот хихикает
        if clickCount >= 5 && !isGiggling {
            startGiggling()
            clickCount = 0
        }
    }

    private func startGiggling() {
        isGiggling = true
        SoundManager.shared.playCelebration()

        // Трясётся от смеха 1.5 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isGiggling = false
            }
        }
    }

    /// Обновление face tracking offset из камеры
    private func updateFaceTracking() {
        // Только если лицо видно
        guard viewModel.cameraManager.isFaceDetected else {
            // Если лицо не видно — сбрасываем offset
            if faceTrackingOffset != .zero {
                withAnimation(.easeOut(duration: 0.3)) {
                    faceTrackingOffset = .zero
                }
            }
            return
        }

        // Используем позицию лица на экране (0 = слева, 1 = справа)
        let faceX = viewModel.cameraManager.facePositionX

        // Конвертируем в offset: 0.5 = центр = 0, края = ±1.5
        // Если человек слева (faceX < 0.5), робот смотрит влево (offset < 0)
        let xOffset = (faceX - 0.5) * 3.0

        // Ограничиваем максимальное смещение
        let clampedOffset = max(-1.5, min(1.5, xOffset))

        withAnimation(.easeOut(duration: 0.15)) {
            faceTrackingOffset = CGSize(width: clampedOffset, height: 0)
        }
    }

    /// Реакция на громкий звук — робот вздрагивает
    private func reactToLoudSound() {
        guard !isWakingUp && !isGiggling else { return }

        // Робот вздрагивает и удивляется
        withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
            isSurprised = true
            bounce = -4
            headTilt = Double.random(in: -10...10)
        }

        SoundManager.shared.playSurprisedSound()

        // Возвращается в норму
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                isSurprised = false
                bounce = 0
                headTilt = 0
            }
        }
    }

    /// Реакция на сердечко руками — робот влюбляется!
    private func reactToHeartGesture() {
        guard !isWakingUp else { return }

        // Расширенная love reaction
        SoundManager.shared.playLoveSound()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            showLoveEasterEgg = true
            bounce = -5
            eyeSquint = 0.4  // Счастливо прищуривается
        }

        // Visual feedback — pulse
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            gestureRecognizedScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                self.gestureRecognizedScale = 1.0
            }
        }

        // Longer love animation for heart gesture
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.4)) {
                showLoveEasterEgg = false
                bounce = 0
                eyeSquint = 0
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
        // Visual feedback — robot pulses when gesture recognized
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            gestureRecognizedScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                self.gestureRecognizedScale = 1.0
            }
        }

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
        // Visual feedback — robot pulses when gesture recognized
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            gestureRecognizedScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                self.gestureRecognizedScale = 1.0
            }
        }

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
            eyeSquint = 0.8  // Almost close eyes
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

// MARK: - Pomodoro Progress Ring

struct PomodoroProgressRing: View {
    let progress: Double  // 0.0 - 1.0
    let isWorking: Bool

    private var ringColor: Color {
        isWorking ? .green : .blue
    }

    var body: some View {
        ZStack {
            // Soft outer glow — очень размытый
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor.opacity(0.2),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)

            // Medium glow
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor.opacity(0.3),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 4)

            // Core line — тонкая яркая линия в центре
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Onboarding Tooltip

struct OnboardingTooltip: View {
    let message: String
    let step: Int
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                // Progress dots
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 4, height: 4)
                    }
                }

                Spacer()

                Button("Skip") {
                    onSkip()
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .buttonStyle(.plain)

                Button(step == totalSteps - 1 ? "Done" : "Next") {
                    onNext()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .cornerRadius(4)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.85))
        )
        .frame(width: 220)
    }
}

// MARK: - Greeting Banner

struct GreetingBanner: View {
    let message: String
    @Binding var isShowing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("🤖")
                .font(.system(size: 12))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Button {
                withAnimation {
                    isShowing = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.85))
        )
        .frame(width: 280)
        .transition(.move(edge: .top).combined(with: .opacity))
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
        // Смотрит в случайную сторону (когда face tracking недоступен)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.randomLookOffset = CGSize(
                    width: CGFloat.random(in: -1.5...1.5),
                    height: CGFloat.random(in: -1.0...1.0)
                )
            }
        }
        // Через время сбрасываем случайный offset (чтобы face tracking мог взять верх)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.5...3.0)) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.randomLookOffset = .zero
            }
        }
    }

    func lookAtUser() {
        // Сбрасываем случайный offset — теперь face tracking возьмёт верх
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.randomLookOffset = .zero
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
            // Если мышка не двигалась больше 1.5 секунд — перестаём следить за ней
            if mouseIdleTime > 1.5 && isFollowingMouse {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.isFollowingMouse = false
                    }
                }
            }
        } else {
            // Мышка начала двигаться — снова следим за ней
            if mouseIdleTime > 1.5 && !isFollowingMouse {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isFollowingMouse = true
                    }
                }
            }
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
