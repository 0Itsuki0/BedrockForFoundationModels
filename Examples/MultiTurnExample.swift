//
//  MultiTurnExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import FoundationModels

/// Multi-turn conversation.
///
/// 1. Calls the session multiple times. The session keeps the transcript, and every request sends the
///    whole conversation to Bedrock as `messages`.
/// 2. Creates a session from an existing transcript (for example, a conversation restored from storage)
///    and continues it.
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func multiTurnExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        stream: stream
    )

    // 1. multiple calls on the same session
    let session = LanguageModelSession(
        model: model,
        instructions: "You are a travel assistant. Answer concisely."
    )
    try await send("I'm planning a 3-day trip to Kyoto.", to: session, stream: stream)
    try await send("What should I see on the first day?", to: session, stream: stream)
    // refers to the earlier turns
    try await send("And how about the last day?", to: session, stream: stream)

    // 2. a session created from an existing transcript
    let transcript = Transcript(entries: [
        .instructions(
            Transcript.Instructions(
                segments: [
                    .text(.init(content: "You are a travel assistant. Answer concisely."))
                ],
                toolDefinitions: []
            )
        ),
        .prompt(
            Transcript.Prompt(
                segments: [.text(.init(content: "My name is Alex. I'm planning a trip to Osaka."))]
            )
        ),
        .response(
            Transcript.Response(
                segments: [.text(.init(content: "Nice to meet you, Alex! How many days will you stay in Osaka?"))]
            )
        ),
        .prompt(
            Transcript.Prompt(
                segments: [.text(.init(content: "Two days."))]
            )
        ),
        .response(
            Transcript.Response(
                segments: [.text(.init(content: "Great. Two days is enough for Dotonbori, Osaka Castle, and Universal Studios Japan."))]
            )
        ),
    ])

    let restoredSession = LanguageModelSession(
        model: model,
        transcript: transcript
    )
    // answered from the restored conversation
    try await send(
        "What's my name, and how long is my trip?",
        to: restoredSession,
        stream: stream
    )
}

/// Sends a prompt to the session and prints the response.
private func send(
    _ prompt: String,
    to session: LanguageModelSession,
    stream: Bool
) async throws {
    print("user:", prompt)
    print("assistant: ", terminator: "")

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
}
