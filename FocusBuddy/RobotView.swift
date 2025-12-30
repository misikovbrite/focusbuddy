import SwiftUI

struct RobotView: View {
    let state: RobotState
    @State private var isAnimating = false
    @State private var antennaGlow = false

    var body: some View {
        VStack(spacing: 0) {
            // Антенна
            AntennaView(state: state, isGlowing: antennaGlow)
                .frame(height: 40)

            // Голова
            HeadView(state: state, isAnimating: isAnimating)
                .frame(width: 200, height: 180)

            // Шея
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 40, height: 20)

            // Тело
            BodyView(state: state)
                .frame(width: 160, height: 100)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                antennaGlow = true
            }
        }
        .onChange(of: state) { _, newState in
            triggerAnimation(for: newState)
        }
    }

    private func triggerAnimation(for state: RobotState) {
        switch state {
        case .distracted:
            // Тряска
            withAnimation(.easeInOut(duration: 0.1).repeatCount(10, autoreverses: true)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isAnimating = false
            }
        case .warning:
            // Покачивание
            withAnimation(.easeInOut(duration: 0.3).repeatCount(4, autoreverses: true)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isAnimating = false
            }
        case .welcomeBack:
            // Радостный прыжок
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = false
            }
        case .focused:
            isAnimating = false
        }
    }
}

// MARK: - Антенна

struct AntennaView: View {
    let state: RobotState
    let isGlowing: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Шарик на антенне
            Circle()
                .fill(state.antennaColor)
                .frame(width: 16, height: 16)
                .shadow(color: state.antennaColor.opacity(isGlowing ? 0.8 : 0.3), radius: isGlowing ? 10 : 5)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .offset(x: -3, y: -3)
                )

            // Стержень антенны
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 24)
        }
    }
}

// MARK: - Голова

struct HeadView: View {
    let state: RobotState
    let isAnimating: Bool

    var body: some View {
        ZStack {
            // Основа головы
            RoundedRectangle(cornerRadius: 40)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(Color.gray.opacity(0.6), lineWidth: 3)
                )

            // Экран лица
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.black.opacity(0.8))
                .padding(15)
                .overlay(
                    // Глаза и рот
                    VStack(spacing: 15) {
                        // Глаза
                        HStack(spacing: 40) {
                            EyeView(state: state, isLeft: true)
                            EyeView(state: state, isLeft: false)
                        }

                        // Рот
                        MouthView(state: state)
                    }
                    .padding(.top, 10)
                )
        }
        .rotationEffect(.degrees(isAnimating && state == .warning ? 5 : 0))
        .offset(x: isAnimating && state == .distracted ? 5 : 0)
        .offset(y: isAnimating && state == .welcomeBack ? -10 : 0)
    }
}

// MARK: - Глаз

struct EyeView: View {
    let state: RobotState
    let isLeft: Bool

    var body: some View {
        ZStack {
            // Свечение
            Circle()
                .fill(state.glowColor)
                .frame(width: 40, height: 40)
                .blur(radius: 8)

            // Основа глаза
            Circle()
                .fill(state.eyeColor)
                .frame(width: 30, height: 30)

            // Зрачок
            Circle()
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .offset(y: state == .distracted ? 4 : 0)

            // Блик
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 8, height: 8)
                .offset(x: -5, y: -5)

            // Бровь при злости
            if state == .distracted {
                RoundedRectangle(cornerRadius: 2)
                    .fill(state.eyeColor)
                    .frame(width: 25, height: 4)
                    .rotationEffect(.degrees(isLeft ? 20 : -20))
                    .offset(y: -22)
            }
        }
    }
}

// MARK: - Рот

struct MouthView: View {
    let state: RobotState

    var body: some View {
        Group {
            switch state {
            case .focused:
                // Улыбка
                SmileMouthShape(smile: true)
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 50, height: 20)

            case .warning:
                // Прямая линия
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.yellow)
                    .frame(width: 40, height: 4)

            case .distracted:
                // Грустный рот
                SmileMouthShape(smile: false)
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: 50, height: 20)

            case .welcomeBack:
                // Большая улыбка
                SmileMouthShape(smile: true)
                    .stroke(Color.cyan, lineWidth: 4)
                    .frame(width: 60, height: 25)
            }
        }
    }
}

struct SmileMouthShape: Shape {
    let smile: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startY = smile ? rect.midY : rect.minY
        let endY = smile ? rect.midY : rect.minY
        let controlY = smile ? rect.maxY : rect.maxY

        path.move(to: CGPoint(x: rect.minX, y: startY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: endY),
            control: CGPoint(x: rect.midX, y: controlY)
        )

        return path
    }
}

// MARK: - Тело

struct BodyView: View {
    let state: RobotState

    var body: some View {
        ZStack {
            // Основа тела
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                )

            // Индикатор на груди
            VStack(spacing: 8) {
                Circle()
                    .fill(state.eyeColor)
                    .frame(width: 20, height: 20)
                    .shadow(color: state.glowColor, radius: 8)

                // Кнопки
                HStack(spacing: 10) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 50) {
        HStack(spacing: 30) {
            RobotView(state: .focused)
            RobotView(state: .warning)
        }
        HStack(spacing: 30) {
            RobotView(state: .distracted)
            RobotView(state: .welcomeBack)
        }
    }
    .padding(50)
    .background(Color.black.opacity(0.9))
}
