import Foundation

enum AssistantProfile: String, Codable, CaseIterable, Sendable {
    case generalist
    case code
    case techInterview

    var displayName: String {
        switch self {
        case .generalist: "Generalista"
        case .code: "Código"
        case .techInterview: "Entrevista Tech"
        }
    }

    var description: String {
        switch self {
        case .generalist: "Assistente para conversas e reuniões profissionais"
        case .code: "Assistente para code review e pair programming"
        case .techInterview: "Coach para entrevistas técnicas"
        }
    }
}
