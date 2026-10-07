//
//  StreamExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import FoundationModels

/// Streaming text generation with `session.streamResponse`.
///
/// - Parameters:
///   - stream: Whether the model uses the ConverseStream API instead of the Converse API.
///     Independent of `session.respond` / `session.streamResponse`.
///     With `false`, the complete Converse output is delivered as a single snapshot.
func streamExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        region: ExampleConstants.region,
        stream: stream
    )
    let session = LanguageModelSession(
        model: model,
        instructions: "You are a helpful assistant."
    )

    let responseStream = session.streamResponse(
        to: "Write a short poem about the ocean."
    )

    for try await snapshot in responseStream {
        // each snapshot contains the content generated so far
        print(snapshot.content)
    }

    let response = try await responseStream.collect()
    print("final:", response.content)
}
