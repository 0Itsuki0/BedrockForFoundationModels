//
//  Response+ConverseStream.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import Foundation
import FoundationModels
import Smithy

nonisolated extension BedrockResponseHandler {

    static func handleConverseStream(
        response: ConverseStreamOutput,
        streamingInto channel: LanguageModelExecutorGenerationChannel,
        toolNameMap: [ToolNameMap]
    ) async throws {

        guard let stream = response.stream else {
            let explanation =
                "Converse Stream API failed to provide an output stream."
            throw FoundationModels.LanguageModelError.refusal(
                .init(explanation: explanation, debugDescription: explanation)
            )
        }

        var metadataMap: [String: SegmentMetadata] = [:]

        var messageRole: BedrockRuntimeClientTypes.ConversationRole? = nil

        var toolName: ToolNameMap? = nil
        var toolUseId = ""
        var segmentId = UUID().uuidString
        var reasoningTokenUsed: Int = 0
        var citationDeltas: [BedrockRuntimeClientTypes.CitationsDelta] = []
        var reasoningSignature: String = ""

        var finalStopReason: BedrockRuntimeClientTypes.StopReason? = nil
        var additionalModelResponseFields: Smithy.Document? = nil
        var metadata: BedrockRuntimeClientTypes.ConverseStreamMetadataEvent? =
            nil

        func resetMessageState() {
            messageRole = nil
        }

        func resetBlockState() {
            segmentId = UUID().uuidString
            metadataMap[segmentId] = SegmentMetadata(segmentId: segmentId)
            resetToolState()
            resetReasoningState()
            resetCitationState()
        }

        func resetToolState() {
            toolName = nil
            toolUseId = ""
        }

        func resetReasoningState() {
            reasoningSignature = ""
            reasoningTokenUsed = 0
        }

        func resetCitationState() {
            citationDeltas = []
        }

        for try await event in stream {
            switch event {

            case .messagestart(let event):
                messageRole = event.role

            // NOTE: contentblockstart event not called if there isn't a tool use
            case .contentblockstart(let event):
                resetBlockState()

                switch event.start {
                case .tooluse(let toolUseStart):
                    toolName = toolNameMap.first(where: {
                        $0.bedrock == toolUseStart.name
                    })
                    toolUseId = toolUseStart.toolUseId ?? ""
                default:
                    break
                }

            case .contentblockdelta(let event):
                switch event.delta {
                case .text(let textDelta):
                    if messageRole == .assistant {
                        await channel.send(
                            .response(
                                action: .appendText(
                                    textDelta,
                                    segmentID: segmentId,
                                    tokenCount: textDelta.count
                                )
                            )
                        )
                    }
                case .tooluse(let toolUseDelta):
                    if !toolUseId.isEmpty, let toolName {
                        await channel.send(
                            .toolCalls(
                                action: .toolCall(
                                    id: toolUseId,
                                    name: toolName.original,
                                    action: .appendArguments(
                                        toolUseDelta.input ?? "",
                                        tokenCount: toolUseDelta.input?.count
                                            ?? 0
                                    )
                                )
                            )
                        )
                    }

                case .reasoningcontent(let reasoningDelta):
                    switch reasoningDelta {
                    case .text(let text):
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
                    case .redactedcontent(_):
                        break
                    case .signature(let signatureDelta):
                        reasoningSignature += signatureDelta
                        reasoningTokenUsed += signatureDelta.count
                    case .sdkUnknown(_):
                        break
                    }

                case .citation(let citation):
                    // Citations deltas that ground already-streamed text carry no content of their own.
                    citationDeltas.append(citation)
                default:
                    break
                }

            case .contentblockstop(_):
                if !reasoningSignature.isEmpty {
                    await channel.send(
                        .reasoning(
                            action: .updateSignature(
                                Data(reasoningSignature.utf8),
                                tokenCount: reasoningSignature.count
                            )
                        )
                    )
                }

                if !citationDeltas.isEmpty {
                    let citations = groupCitationDeltas(citationDeltas)
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
                            // Citations deltas that ground already-streamed text carry no content of their own.
                            content: ""
                        )
                    )
                }

                resetBlockState()

            case .messagestop(let event):
                additionalModelResponseFields =
                    event.additionalModelResponseFields
                finalStopReason = event.stopReason
                resetMessageState()

            case .metadata(let event):
                metadata = event

            case .sdkUnknown(let string):
                let explanation = "Received unknown result: \(string)"
                throw FoundationModels.LanguageModelError.refusal(
                    .init(
                        explanation: explanation,
                        debugDescription: explanation
                    )
                )
            }
        }

        try self.checkStopReason(
            finalStopReason,
            guardrailTrace: metadata?.trace?.guardrail,
            totalTokenUsed: metadata?.usage?.totalTokens
        )

        // Update metadata for all segments
        await sendMetadata(
            segmentMetadata: metadataMap.map(\.value),
            additionalModelResponseFields: additionalModelResponseFields,
            metrics: ResponseMetrics.fromConverseStreamMetrics(
                metadata?.metrics
            ),
            into: channel
        )

        await self.sendTokenUsage(
            metadata?.usage,
            reasoningTokenUsed: reasoningTokenUsed,
            into: channel
        )
    }

    private static func citation(
        from delta: BedrockRuntimeClientTypes.CitationsDelta
    ) -> BedrockRuntimeClientTypes.Citation {
        return BedrockRuntimeClientTypes.Citation(
            location: delta.location,
            source: delta.source,
            sourceContent: sourceContent(from: delta.sourceContent),
            title: delta.title
        )
    }

    private static func sourceContent(
        from deltaContents: [BedrockRuntimeClientTypes
            .CitationSourceContentDelta]?
    ) -> [BedrockRuntimeClientTypes.CitationSourceContent] {
        return deltaContents?.compactMap {
            delta -> BedrockRuntimeClientTypes.CitationSourceContent? in
            if let text = delta.text {
                return .text(text)
            } else {
                return nil
            }
        } ?? []
    }

    private static func groupCitationDeltas(
        _ deltas: [BedrockRuntimeClientTypes.CitationsDelta]
    ) -> [BedrockRuntimeClientTypes.Citation] {
        guard let firstDelta = deltas.first else {
            return []
        }
        var finalCitations: [BedrockRuntimeClientTypes.Citation] = []

        var currentDelta = firstDelta
        var currentCitation = citation(from: currentDelta)

        func isSameCitation(
            lhs: BedrockRuntimeClientTypes.CitationsDelta,
            rhs: BedrockRuntimeClientTypes.CitationsDelta
        ) -> Bool {
            if lhs.title != rhs.title || lhs.source != rhs.source {
                return false
            }

            switch (lhs.location, rhs.location) {
            case (.web(let a), .web(let b)):
                return a.domain == b.domain && a.url == b.url
            case (.documentchar(let a), .documentchar(let b)):
                return a.start == b.start && a.end == b.end
                    && a.documentIndex == b.documentIndex
            case (.documentpage(let a), .documentpage(let b)):
                return a.start == b.start && a.end == b.end
                    && a.documentIndex == b.documentIndex
            case (.documentchunk(let a), .documentchunk(let b)):
                return a.start == b.start && a.end == b.end
                    && a.documentIndex == b.documentIndex
            case (.searchresultlocation(let a), .searchresultlocation(let b)):
                return a.start == b.start && a.end == b.end
                    && a.searchResultIndex == b.searchResultIndex
            case (.sdkUnknown(let a), .sdkUnknown(let b)):
                return a == b
            default:
                return false
            }
        }

        for delta in deltas.dropFirst() {
            if isSameCitation(lhs: delta, rhs: currentDelta) {
                currentCitation.sourceContent?.append(
                    contentsOf: sourceContent(from: delta.sourceContent)
                )
            } else {
                finalCitations.append(currentCitation)
                currentDelta = delta
                currentCitation = citation(from: currentDelta)
            }
        }

        finalCitations.append(currentCitation)
        return finalCitations
    }
}
