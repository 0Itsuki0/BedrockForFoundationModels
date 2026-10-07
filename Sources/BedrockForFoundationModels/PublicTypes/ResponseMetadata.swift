//
//  ResponseMetadata.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import FoundationModels
import Smithy

@Generable()
public struct ResponseMetadata {
    public static let metadataKey = "responseMetadata"

    public package(set) var segmentMetadata: [SegmentMetadata]

    /// Additional fields in the response that are unique to the model.
    public package(set) var additionalModelResponseFields: GeneratedContent? =
        nil

    /// If non-streaming: Metrics for a call to Converse
    /// If streaming:  Metrics for a call to ConverseStream
    public package(set) var metrics: ResponseMetrics? = nil
}

@Generable()
public struct ResponseMetrics {
    /// The latency of the call to Converse/ConverseStream, in milliseconds.
    public package(set) var latencyMs: Int

    init(latencyMs: Int) {
        self.latencyMs = latencyMs
    }

    /// From  metrics for a call to [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html).
    static func fromConverseMetrics(
        _ metrics: BedrockRuntimeClientTypes.ConverseMetrics?
    ) -> ResponseMetrics? {
        guard let metrics, let latencyMs = metrics.latencyMs else { return nil }
        return ResponseMetrics(latencyMs: latencyMs)
    }

    // From metrics for a call to converseStream
    static func fromConverseStreamMetrics(
        _ metrics: BedrockRuntimeClientTypes.ConverseStreamMetrics?
    ) -> ResponseMetrics? {
        guard let metrics, let latencyMs = metrics.latencyMs else { return nil }
        return ResponseMetrics(latencyMs: latencyMs)
    }
}

/// Metadata attached to a response segment.
///
/// Metadata will be added to the response as `[SegmentId: SegmentMetadata]`.
@Generable()
public struct SegmentMetadata {
    public package(set) var segmentId: String

    /// The citations for the segment.
    public package(set) var citations: [CitationContent] = []
}

extension SegmentMetadata {
    var isEmpty: Bool {
        return citations.isEmpty
    }
}
