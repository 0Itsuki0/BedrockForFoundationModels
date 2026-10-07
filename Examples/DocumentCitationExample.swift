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

/// Document citations. Citations are returned in the response metadata as `segmentMetadata.citations`
///
/// See [CitationsConfig](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CitationsConfig.html).
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func documentCitationExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
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

    // citation locations are contained within the response metadata.
    // `response.metadata` looks like:
    //
    // ["responseMetadata": {"segmentMetadata":[{"citations":[{"citations":[{"title":"Atlas-1","sourceContent":["Project Atlas is an internal initiative to automate invoice processing."],"location":{"documentIndex":0,"start":0,"type":"documentchar","end":71}}],"content":""}],"segmentId":"3CEC8C02-6BCC-4792-89D9-9B4F7D62D7F1"},{"segmentId":"DED48F8D-6AFC-4855-A1AB-5BF568B54972","citations":[{"content":"","citations":[{"title":"Atlas-2","location":{"start":0,"end":111,"documentIndex":1,"type":"documentchar"},"sourceContent":["In phase 1 of Atlas, paper invoices are scanned with OCR and registered in the accounting system automatically."]}]}]}],"metrics":{"latencyMs":2420}}]
    //
    // To extract it as `ResponseMetadata` and read each citation, see `ResponseMetadataExample.swift`.
    try printResponseMetadata(of: session)
}
