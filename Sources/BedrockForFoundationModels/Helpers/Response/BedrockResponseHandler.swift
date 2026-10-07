//
//  BedrockResponseHandler.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//

import AWSBedrockRuntime
import Foundation
import FoundationModels

nonisolated enum BedrockResponseHandler {

    static func sendTokenUsage(
        _ usage: BedrockRuntimeClientTypes.TokenUsage?,
        reasoningTokenUsed: Int,
        into channel: LanguageModelExecutorGenerationChannel
    ) async {
        guard let usage else { return }

        let cached = usage.cacheReadInputTokens ?? 0
        let prompt = (usage.inputTokens ?? 0) + cached
        let output = usage.outputTokens ?? 0

        // NOTE: if cacheReadInputTokens > inputToken, the App will simply crash with BadExec
        await channel.send(
            .response(
                action: .updateUsage(
                    input: .init(
                        totalTokenCount: prompt,  // NOTE: this value is not the inputToken but the sum of input + cache
                        cachedTokenCount: cached
                    ),
                    output: .init(
                        totalTokenCount: output,
                        reasoningTokenCount: reasoningTokenUsed > output
                            ? 0 : reasoningTokenUsed
                    )
                )
            )
        )

    }

    static func checkStopReason(
        _ stopReason: BedrockRuntimeClientTypes.StopReason?,
        guardrailTrace: BedrockRuntimeClientTypes.GuardrailTraceAssessment?,
        totalTokenUsed: Int?
    ) throws {
        switch stopReason {
        case .guardrailIntervened:
            throw FoundationModels.LanguageModelError.guardrailViolation(
                .init(
                    debugDescription: guardrailTrace?.actionReason
                        ?? ""
                )
            )

        case .malformedModelOutput, .contentFiltered, .malformedToolUse,
            .maxTokens:
            let explanation =
                "Model stopped due to \(stopReason?.rawValue, default: "unknown reason")."
            throw FoundationModels.LanguageModelError.refusal(
                .init(
                    explanation: explanation,
                    debugDescription: explanation
                )
            )

        case .modelContextWindowExceeded:
            throw FoundationModels.LanguageModelError.contextSizeExceeded(
                .init(
                    contextSize: 0,
                    tokenCount: totalTokenUsed ?? 0,
                    debugDescription:
                        "Model Context Window Exceeded. Context size is based on the model using. "
                )
            )

        case .toolUse, .endTurn, .stopSequence, .none, .sdkUnknown(_):
            break
        }
    }

    static func sendMetadata(
        _ metadata: [String: SegmentMetadata],
        into channel: LanguageModelExecutorGenerationChannel
    ) async {
        await channel.send(
            .response(
                action: .updateMetadata(removeEmptyMetadata(metadata))
            )
        )
    }

    private static func removeEmptyMetadata(_ metadata: [String: SegmentMetadata])
        -> [String: SegmentMetadata]
    {
        return metadata.filter({
            !$0.value.isEmpty
        })
    }

}
