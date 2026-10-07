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
        stream: stream
    )
    let session = LanguageModelSession(
        model: model,
        instructions: "You are a helpful assistant."
    )

    let responseStream = session.streamResponse(
        to: "Write a short poem about the ocean."
    )

    // snapshots are cumulative: print only the newly generated part
    var printed = ""
    for try await snapshot in responseStream {
        print(snapshot.content.dropFirst(printed.count), terminator: "")
        printed = snapshot.content
    }
    print()
}
