//
//  DocumentCitationExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import Foundation
import FoundationModels

/// A plain text document attachment with citations enabled or disabled.
struct CitableTextDocument: DataAttachmentRepresentable {
    let text: String
    let enableCitation: Bool

    var transcriptRepresentation: Transcript.DataAttachment {
        return .init(
            contentType: .plainText,
            content: Data(text.utf8),
            metadata: GeneratedContent(properties: [
                String.enableDocumentCitationKey: enableCitation
            ])
        )
    }

    init(text: String, enableCitation: Bool) {
        self.text = text
        self.enableCitation = enableCitation
    }

    init(_ attachment: Transcript.DataAttachment) throws {
        self.text = String(data: attachment.content, encoding: .utf8) ?? ""
        self.enableCitation =
            (try? attachment.metadata.value(
                forProperty: String.enableDocumentCitationKey
            )) ?? false
    }
}

/// Document citations. Citations are returned in the response metadata as `[SegmentId: SegmentMetadata]`.
///
/// See [CitationsConfig](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CitationsConfig.html).
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func documentCitationExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        region: ExampleConstants.region,
        stream: stream
    )
    let session = LanguageModelSession(model: model)

    let overview = CitableTextDocument(
        text:
            "Project Atlas is an internal initiative to automate invoice processing.",
        enableCitation: true
    )
    let phase1 = CitableTextDocument(
        text:
            "In phase 1 of Atlas, paper invoices are scanned with OCR and registered in the accounting system automatically.",
        enableCitation: true
    )

    let prompt = Prompt {
        // the label is used as the document name
        Attachment(overview)
            .label("Atlas-Overview")
        Attachment(phase1)
            .label("Atlas-Phase1")
        "What is Project Atlas? Answer based on the documents."
    }

    if stream {
        let responseStream = session.streamResponse(to: prompt)
        for try await snapshot in responseStream {
            print(snapshot.content)
        }
    } else {
        let response = try await session.respond(to: prompt)
        print(response.content)
    }

    switch session.transcript.last {
    case .response(let response):
        /// citation locations contained within the metadata ``ResponseMetadata/SegmentMetadata``
        print(response.metadata)
    default:
        break
    }
}
