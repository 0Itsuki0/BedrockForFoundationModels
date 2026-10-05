//
//  BedrockResponseHandler.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//


import AWSBedrockRuntime
//import CoreImage
import FoundationModels
import Foundation
//extension Document: ExpressibleByDictionaryLiteral {
//
//    public init(dictionaryLiteral elements: (String, Document)...) {
//        let value = elements.reduce([String: Document]()) { acc, curr in
//            var newValue = acc
//            newValue[curr.0] = curr.1
//            return newValue
//        }
//        self.init(StringMapDocument(value: value))
//    }
//}
//import Smithy
//@_spi(SmithyDocumentImpl) import Smithy
//import SmithyIdentity
//import SmithyJSON
//import UniformTypeIdentifiers


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
        of documentContentBlocks: [BedrockRuntimeClientTypes
            .DocumentContentBlock],
        separator: String = "\n"
    ) -> String {
        documentContentBlocks.compactMap {
            switch $0 {
            case .text(let t): t
            case .sdkUnknown(let s): s
            @unknown default: nil
            }
        }
        .joined(separator: separator)
    }
    
    private static func text(
        of citationContent: [BedrockRuntimeClientTypes
            .CitationGeneratedContent],
        separator: String = "\n"
    ) -> String {
        citationContent.compactMap {
            switch $0 {
            case .text(let t): t
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
        print(#function, output)
        //        response.usage?.outputTokens
        //        response.serviceTier?.type
        
        // NOTE: explicit Segment ID so that each contentBlock is its own segment (with its own metadata)
        switch output {
        case .message(let message):
            for contentBlock in message.content ?? [] {
                let segmentId = UUID().uuidString
                var metadata = SegmentMetadata()
                
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
                    metadata.citations = citation.citations?.compactMap {
                        DocumentCitation($0)
                    }
                default:
                    continue
                }
                
                await channel.send(
                    .response(
                        action: .updateMetadata([
                            segmentId: metadata
                        ])
                    )
                )
            }
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
        case .malformedModelOutput:
            throw FoundationModels.LanguageModelError.refusal(
                .init(
                    explanation: "malformedModelOutput",
                    debugDescription: "malformedModelOutput"
                )
            )
        case .contentFiltered:
            throw FoundationModels.LanguageModelError.refusal(
                .init(
                    explanation: "malformedModelOutput",
                    debugDescription: "malformedModelOutput"
                )
            )
        case .malformedToolUse:
            throw FoundationModels.LanguageModelError.refusal(
                .init(
                    explanation: "malformedModelOutput",
                    debugDescription: "malformedModelOutput"
                )
            )
        case .maxTokens:
            throw FoundationModels.LanguageModelError.refusal(
                .init(
                    explanation: "malformedModelOutput",
                    debugDescription: "malformedModelOutput"
                )
            )
            
        case .modelContextWindowExceeded:
            //            throw FoundationModels.LanguageModelError.contextSizeExceeded(.init(contextSize: <#T##Int#>, tokenCount: <#T##Int#>, debugDescription: <#T##String#>))
            break
        case .sdkUnknown(let unknown):
            //            throw FoundationModels.LanguageModelError.refusal(<#T##LanguageModelError.Refusal#>)
            break
        case .toolUse, .endTurn, .stopSequence, .none:
            break
        }
        
    }
}
