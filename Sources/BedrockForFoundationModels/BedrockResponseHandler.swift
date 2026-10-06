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
        try self.checkStopReason(response)

        guard let output = response.output else {
            return
        }
        var reasoningTokenUsed: Int = 0
        try await self.streamResult(
            output,
            into: channel,
            reasoningTokenUsed: &reasoningTokenUsed,
            toolNameMap: toolNameMap
        )

        if let usage = response.usage {
            await channel.send(
                .response(
                    action: .updateUsage(
                        input: .init(
                            totalTokenCount: usage.inputTokens ?? 0,
                            cachedTokenCount: usage.cacheReadInputTokens ?? 0
                        ),
                        output: .init(
                            totalTokenCount: usage.totalTokens ?? 0,
                            reasoningTokenCount: reasoningTokenUsed
                        )
                    )
                )
            )
        }

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

    /// event mapping reference:
    /// strands-ts/src/models/bedrock.ts: function _mapBedrockEventToSDKEvent
    private static func streamResult(
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
                    metadataMap[segmentId] = SegmentMetadata(
                        citations: citation.citations?.compactMap {
                            DocumentCitation($0)
                        }
                    )
                default:
                    continue
                }
            }

            await channel.send(
                .response(
                    action: .updateMetadata(metadataMap)
                )
            )
        case .sdkUnknown(_):
            break
        }
    }

    private static func checkStopReason(_ output: ConverseOutput) throws {
        switch output.stopReason {
        case .guardrailIntervened:
            throw FoundationModels.LanguageModelError.guardrailViolation(
                .init(
                    debugDescription: output.trace?.guardrail?.actionReason
                        ?? ""
                )
            )

        case .malformedModelOutput, .contentFiltered, .malformedToolUse,
            .maxTokens:
            let explanation =
                "Model stopped due to \(output.stopReason?.rawValue, default: "unknown reason")."
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
                    tokenCount: output.usage?.totalTokens ?? 0,
                    debugDescription:
                        "Model Context Window Exceeded. Context size is based on the model using. "
                )
            )

        case .toolUse, .endTurn, .stopSequence, .none, .sdkUnknown(_):
            break
        }

    }
}
