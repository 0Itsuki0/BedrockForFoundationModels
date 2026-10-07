//
//  StructuredOutputExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import BedrockForFoundationModels
import FoundationModels

/// Generated with Bedrock structured output (strict JSON schema).
///
/// Bedrock does not support numerical constraints (minimum, maximum), string length constraints,
/// or `maximumCount` on arrays, so avoid those guides.
/// See [Structured output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).
@Generable
struct Recipe {
    @Guide(description: "The name of the dish.")
    var name: String

    @Guide(description: "The difficulty of the recipe.")
    var difficulty: Difficulty

    @Guide(description: "Ingredients required for the dish.")
    var ingredients: [Ingredient]

    @Guide(description: "Ordered preparation steps.")
    var steps: [String]

    @Generable
    enum Difficulty {
        case easy
        case medium
        case hard
    }

    @Generable
    struct Ingredient {
        @Guide(description: "The ingredient name.")
        var name: String
        @Guide(description: "The amount, for example `200g` or `2 cups`.")
        var amount: String
    }
}

/// Structured output with `@Generable` types.
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func structuredOutputExample(stream: Bool) async throws {
    let model = BedrockLanguageModel(
        modelId: ExampleConstants.modelId,
        stream: stream
    )
    let session = LanguageModelSession(model: model)
    let prompt = "Give me a simple recipe for pancakes."

    let recipe: Recipe
    if stream {
        let responseStream = session.streamResponse(
            to: prompt,
            generating: Recipe.self
        )
        for try await snapshot in responseStream {
            // `snapshot.content` is a `Recipe.PartiallyGenerated` with the properties generated so far,
            // for example, to update the UI progressively.
            _ = snapshot.content
        }
        recipe = try await responseStream.collect().content
    } else {
        recipe = try await session.respond(
            to: prompt,
            generating: Recipe.self
        ).content
    }

    print(recipe.name, recipe.difficulty)
    for ingredient in recipe.ingredients {
        print("-", ingredient.name, ingredient.amount)
    }
    for (index, step) in recipe.steps.enumerated() {
        print("\(index + 1).", step)
    }
}
