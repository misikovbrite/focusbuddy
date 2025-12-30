import SwiftUI

enum RobotState {
    case focused      // Работаешь - зелёные глаза
    case warning      // Начал отвлекаться - жёлтые глаза
    case distracted   // Отвлёкся - красные глаза
    case welcomeBack  // Вернулся - радость

    var eyeColor: Color {
        switch self {
        case .focused, .welcomeBack:
            return .green
        case .warning:
            return .yellow
        case .distracted:
            return .red
        }
    }

    var glowColor: Color {
        eyeColor.opacity(0.6)
    }

    var antennaColor: Color {
        switch self {
        case .focused:
            return .green
        case .warning:
            return .yellow
        case .distracted:
            return .red
        case .welcomeBack:
            return .cyan
        }
    }
}
