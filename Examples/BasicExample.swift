//
//  BasicExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import FoundationModels

/// Basic text generation with `session.respond`.
///
/// Credentials are resolved by the AWS SDK default chain (environment variables, shared config, SSO, etc.).
///
/// - Parameters:
///   - stream: Whether the model uses the ConverseStream API instead of the Converse API.
///     Independent of `session.respond` / `session.streamResponse`.
func basicExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        stream: stream
    )
    let session = LanguageModelSession(
        model: model,
        instructions: "You are a helpful assistant. Answer concisely."
    )

    let response = try await session.respond(to: "What is Amazon Bedrock?")
    print(response.content)

    // multi-turn: the session keeps the transcript
    let followUp = try await session.respond(to: "Summarize that in one sentence.")
    print(followUp.content)
}
