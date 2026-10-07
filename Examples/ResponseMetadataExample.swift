//
//  ResponseMetadataExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import FoundationModels

/// Extracts ``ResponseMetadata`` from a transcript response.
///
/// The metadata is stored in `response.metadata` under ``ResponseMetadata/metadataKey``, for example:
///
/// ```json
/// [
///   "responseMetadata": {
///     "segmentMetadata": [
///       {
///         "segmentId": "3CEC8C02-6BCC-4792-89D9-9B4F7D62D7F1",
///         "citations": [
///           {
///             "content": "",
///             "citations": [
///               {
///                 "title": "Atlas-1",
///                 "sourceContent": ["Project Atlas is an internal initiative to automate invoice processing."],
///                 "location": { "type": "documentchar", "documentIndex": 0, "start": 0, "end": 71 }
///               }
///             ]
///           }
///         ]
///       }
///     ],
///     "metrics": { "latencyMs": 2420 }
///   }
/// ]
/// ```
func extractResponseMetadata(from response: Transcript.Response) throws
    -> ResponseMetadata?
{
    guard let content = response.metadata[ResponseMetadata.metadataKey] else {
        return nil
    }
    return try ResponseMetadata(content)
}

/// Prints every field of the ``ResponseMetadata`` of the last response in the session.
func printResponseMetadata(of session: LanguageModelSession) throws {
    guard case .response(let response) = session.transcript.last,
        let metadata = try extractResponseMetadata(from: response)
    else {
        print("no response metadata")
        return
    }

    if let metrics = metadata.metrics {
        print("latency:", metrics.latencyMs, "ms")
    }

    if let additionalFields = metadata.additionalModelResponseFields {
        print("additional model response fields:", additionalFields.jsonString)
    }

    for segmentMetadata in metadata.segmentMetadata {
        // `segmentId` matches the id of a segment in the response
        let segment = response.segments.first(where: {
            $0.id == segmentMetadata.segmentId
        })
        if case .text(let textSegment) = segment {
            print("segment:", textSegment.content)
        }

        for citationContent in segmentMetadata.citations {
            // empty for citations deltas that ground already-streamed text
            if !citationContent.content.isEmpty {
                print("  cited content:", citationContent.content)
            }

            for citation in citationContent.citations {
                print("  title:", citation.title ?? "-")
                print("  source content:", citation.sourceContent ?? [])

                switch citation.location {
                case .documentchar(let documentIndex, let end, let start):
                    print(
                        "  document \(documentIndex ?? -1), characters \(start ?? -1)..<\(end ?? -1)"
                    )
                case .documentpage(let documentIndex, let end, let start):
                    print(
                        "  document \(documentIndex ?? -1), pages \(start ?? -1)...\(end ?? -1)"
                    )
                case .documentchunk(let documentIndex, let end, let start):
                    print(
                        "  document \(documentIndex ?? -1), chunks \(start ?? -1)...\(end ?? -1)"
                    )
                case .searchresultlocation(let end, let searchResultIndex, let start):
                    print(
                        "  search result \(searchResultIndex ?? -1), blocks \(start ?? -1)...\(end ?? -1)"
                    )
                case .web(let domain, let url):
                    print("  web:", domain ?? "-", url ?? "-")
                case .sdkUnknown(let value):
                    print("  unknown location:", value)
                case nil:
                    break
                }
            }
        }
    }
}

/// Extracting response metadata: metrics and additional model response fields.
///
/// For citations in the metadata, see ``documentCitationExample(stream:)``.
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func responseMetadataExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        stopSequences: ["END"],
        stream: stream,
        // returned in `ResponseMetadata.additionalModelResponseFields`
        additionalResponseFieldPaths: ["/stop_sequence"]
    )
    let session = LanguageModelSession(model: model)
    let prompt = "Count from 1 to 5, then write END."

    if stream {
        // snapshots are cumulative: print only the newly generated part
        var printed = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            print(snapshot.content.dropFirst(printed.count), terminator: "")
            printed = snapshot.content
        }
        print()
    } else {
        let response = try await session.respond(to: prompt)
        print(response.content)
    }

    try printResponseMetadata(of: session)
}
