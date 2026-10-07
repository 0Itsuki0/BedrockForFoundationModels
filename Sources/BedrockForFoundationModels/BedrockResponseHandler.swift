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

    static func handleConverseOutput(
        response: ConverseOutput,
        streamingInto channel: LanguageModelExecutorGenerationChannel,
        toolNameMap: [ToolNameMap]
    ) async throws {
        try self.checkStopReason(
            response.stopReason,
            guardrailTrace: response.trace?.guardrail,
            totalTokenUsed: response.usage?.totalTokens
        )

        guard let output = response.output else {
            let explanation = "Converse API failed to provide an output."
            throw FoundationModels.LanguageModelError.refusal(
                .init(explanation: explanation, debugDescription: explanation)
            )
        }

        var reasoningTokenUsed: Int = 0

        try await self.sendOutput(
            output,
            into: channel,
            reasoningTokenUsed: &reasoningTokenUsed,
            toolNameMap: toolNameMap
        )

        await self.sendTokenUsage(
            response.usage,
            reasoningTokenUsed: reasoningTokenUsed,
            into: channel
        )
    }

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

    private static func text(
        of citationContent: [BedrockRuntimeClientTypes
            .CitationGeneratedContent],
        separator: String = "\n"
    ) -> String {
        citationContent.compactMap {
            switch $0 {
            case .text(let t): t.isEmpty ? nil : t
            case .sdkUnknown(let s): s
            @unknown default: nil
            }
        }
        .joined(separator: separator)
    }

    /// stream converse output into channel
    /// event mapping reference:
    /// strands-ts/src/models/bedrock.ts: function _mapBedrockEventToSDKEvent
    private static func sendOutput(
        _ output: BedrockRuntimeClientTypes.ConverseOutput,
        into channel: LanguageModelExecutorGenerationChannel,
        reasoningTokenUsed: inout Int,
        toolNameMap: [ToolNameMap]
    ) async throws {

        switch output {
        case .message(let message):
            var metadataMap: [String: SegmentMetadata] = [:]

            for contentBlock in message.content ?? [] {
                // explicit Segment ID so that each contentBlock is its own segment (with its own metadata)
                let segmentId = UUID().uuidString
                metadataMap[segmentId] = SegmentMetadata()

                switch contentBlock {
                case .text(let text):
                    await channel.send(
                        .response(
                            action: .appendText(
                                text,
                                segmentID: segmentId,
                                tokenCount: text.count
                            )
                        )
                    )
                case .tooluse(let toolUse):
                    guard
                        let toolName = toolNameMap.first(where: {
                            $0.bedrock == toolUse.name
                        })
                    else {
                        continue
                    }
                    var inputString: String = ""
                    if let input = toolUse.input {
                        inputString =
                            try SmithyDocumentSupport.jsonString(for: input)
                            ?? ""
                    }

                    await channel.send(
                        .toolCalls(
                            action: .toolCall(
                                id: toolUse.toolUseId ?? segmentId,
                                name: toolName.original,
                                action: .appendArguments(
                                    inputString,
                                    tokenCount: inputString.count
                                )
                            )
                        )
                    )
                case .reasoningcontent(let reasoning):
                    switch reasoning {
                    case .reasoningtext(let text):
                        if let text = text.text {
                            await channel.send(
                                .reasoning(
                                    action: .appendText(
                                        text,
                                        segmentID: segmentId,
                                        tokenCount: text.count
                                    )
                                )
                            )
                            reasoningTokenUsed += text.count
                        }
                        if let signature = text.signature {
                            await channel.send(
                                .reasoning(
                                    action: .updateSignature(
                                        Data(signature.utf8),
                                        tokenCount: signature.count
                                    )
                                )
                            )
                            reasoningTokenUsed += signature.count
                        }
                    case .redactedcontent(_):
                        continue
                    case .sdkUnknown(_):
                        continue
                    }
                case .citationscontent(let citation):
                    let text = text(of: citation.content ?? [])
                    await channel.send(
                        .response(
                            action: .appendText(
                                text,
                                segmentID: segmentId,
                                tokenCount: text.count
                            )
                        )
                    )
                    if let citations = citation.citations, !citations.isEmpty {
                        metadataMap[segmentId]?.citations.append(
                            .init(
                                citations: citations.map({
                                    DocumentCitation($0)
                                }),
                                content: text
                            )
                        )
                    }
                default:
                    continue
                }
            }

            await channel.send(
                .response(
                    action: .updateMetadata(removeEmptyMetadata(metadataMap))
                )
            )
        case .sdkUnknown(let string):
            let explanation = "Received unknown result: \(string)"
            throw FoundationModels.LanguageModelError.refusal(
                .init(explanation: explanation, debugDescription: explanation)
            )
        }
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

    static func removeEmptyMetadata(_ metadata: [String: SegmentMetadata])
        -> [String: SegmentMetadata]
    {
        return metadata.filter({
            !$0.value.isEmpty
        })
    }
}
