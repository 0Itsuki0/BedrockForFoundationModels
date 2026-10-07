//
//  Response+Converse.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import AWSBedrockRuntime
import Foundation
import FoundationModels

nonisolated extension BedrockResponseHandler {
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

        let (reasoningTokenUsed, segmentMetadata) = try await self.sendOutput(
            output,
            into: channel,
            toolNameMap: toolNameMap
        )

        await self.sendMetadata(
            segmentMetadata: segmentMetadata,
            additionalModelResponseFields: response
                .additionalModelResponseFields,
            metrics: ResponseMetrics.fromConverseMetrics(
                response.metrics
            ),
            into: channel
        )

        await self.sendTokenUsage(
            response.usage,
            reasoningTokenUsed: reasoningTokenUsed,
            into: channel
        )
    }

    /// stream converse output into channel
    /// event mapping reference:
    /// strands-ts/src/models/bedrock.ts: function _mapBedrockEventToSDKEvent
    private static func sendOutput(
        _ output: BedrockRuntimeClientTypes.ConverseOutput,
        into channel: LanguageModelExecutorGenerationChannel,
        toolNameMap: [ToolNameMap]
    ) async throws -> (
        reasoningTokenUsed: Int, segmentMetadata: [SegmentMetadata]
    ) {
        var reasoningTokenUsed: Int = 0
        var metadataMap: [String: SegmentMetadata] = [:]

        switch output {
        case .message(let message):

            for contentBlock in message.content ?? [] {
                // explicit Segment ID so that each contentBlock is its own segment (with its own metadata)
                let segmentId = UUID().uuidString
                metadataMap[segmentId] = SegmentMetadata(segmentId: segmentId)

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
                        if metadataMap[segmentId] == nil {
                            metadataMap[segmentId] = SegmentMetadata(
                                segmentId: segmentId
                            )
                        }
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

        case .sdkUnknown(let string):
            let explanation = "Received unknown result: \(string)"
            throw FoundationModels.LanguageModelError.refusal(
                .init(explanation: explanation, debugDescription: explanation)
            )
        }

        return (reasoningTokenUsed, metadataMap.map(\.value))
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
}
