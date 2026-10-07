//
//  OutputEffort.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import FoundationModels

/// The effort level for the model to use when generating a response.
/// Higher effort levels allow the model to spend more time reasoning before responding.
/// Supported values are low, medium, high, xhigh, and max.
/// When [extended thinking](https://docs.aws.amazon.com/nova/latest/userguide/extended-thinking.html) is disabled, the effort level is capped at high.
/// Use effort high or below, or enable thinking to use higher effort levels.
nonisolated enum OutputEffort: String {
    case low
    case medium
    case high
    case xhigh
    case max

    static func fromReasoningLevel(
        _ reasoningLevel: ContextOptions.ReasoningLevel?
    ) -> OutputEffort? {
        guard let reasoningLevel else {
            return nil
        }
        return switch reasoningLevel {
        case .light:
            .low
        case .moderate:
            .medium
        case .deep:
            .high
        case .custom(let string):
            OutputEffort(rawValue: string)
        @unknown default:
            nil
        }
    }
}
