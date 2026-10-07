//
//  ToolUseExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import FoundationModels

/// A tool the model can call to look up the weather.
///
/// See [Use a tool to complete an Amazon Bedrock model response](https://docs.aws.amazon.com/bedrock/latest/userguide/tool-use.html).
struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Get the current weather for a city."

    @Generable
    struct Arguments {
        @Guide(description: "The city to get the weather for.")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        // replace with a real weather lookup
        return "It is sunny and 22°C in \(arguments.city)."
    }
}

/// Tool use. The session calls the tool and sends the result back to the model automatically.
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func toolUseExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        stream: stream
    )
    let session = LanguageModelSession(
        model: model,
        tools: [WeatherTool()],
        instructions: "Use the tools available to answer the user."
    )
    let prompt = "What's the weather like in Tokyo?"

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

    // the tool call and its output are recorded in the transcript
    for entry in session.transcript {
        switch entry {
        case .toolCalls(let toolCalls):
            print("tool calls:", toolCalls)
        case .toolOutput(let toolOutput):
            print("tool output:", toolOutput)
        default:
            break
        }
    }
}
