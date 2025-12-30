import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = FocusViewModel()
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Прозрачный фон
            Color.clear

            VStack(spacing: 8) {
                // Робот (компактный)
                RobotView(state: viewModel.robotState)
                    .scaleEffect(0.5)
                    .frame(height: 180)

                // Сообщение (показывается при наведении или когда не focused)
                if isHovering || viewModel.robotState != .focused {
                    RobotMessageView(state: viewModel.robotState)
                        .transition(.opacity.combined(with: .scale))
                }

                // Мини-статистика при наведении
                if isHovering {
                    MiniStatsView(stats: viewModel.focusStats)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(10)
        }
        .frame(width: 200, height: 280)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(isHovering ? 0.7 : 0.4))
                .shadow(color: viewModel.robotState.eyeColor.opacity(0.3), radius: 10)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
}

// MARK: - Сообщение робота

struct RobotMessageView: View {
    let state: RobotState

    var message: String {
        switch state {
        case .focused:
            return "Работаем!"
        case .warning:
            return "Эй!"
        case .distracted:
            return "Вернись!"
        case .welcomeBack:
            return "Ура!"
        }
    }

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(state.eyeColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(state.eyeColor.opacity(0.5), lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: state)
    }
}

// MARK: - Мини-статистика

struct MiniStatsView: View {
    let stats: FocusStats

    var body: some View {
        HStack(spacing: 15) {
            MiniStatItem(
                icon: "clock.fill",
                value: stats.formattedFocusedTime,
                color: .green
            )

            MiniStatItem(
                icon: "exclamationmark.triangle.fill",
                value: "\(stats.distractionCount)",
                color: .orange
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
        )
    }
}

struct MiniStatItem: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 200, height: 280)
        .background(Color.gray)
}
