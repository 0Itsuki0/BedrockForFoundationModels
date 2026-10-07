# (WIP) BedrockForFoundationModels



## (Partially) Confirmed
- multi-turn converse
- tool use (with argument, string output)
- structured output
- override SigV4 with the provided access key / session token
- basic caching (tool, system, message)
- guardrails
- basic streaming (with tool use)
- text document citation


## Pending Task
- bytes document citation
- prompt metadata
- confirming API key override
- message caching with documents added



## Future

- Extended Thinking: https://docs.aws.amazon.com/nova/latest/userguide/extended-thinking.html
- file/image size check


---

Use [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html) as a server-side language model through Apple's [Foundation Models](https://developer.apple.com/documentation/foundationmodels) framework. The package conforms Bedrock to the framework's `LanguageModel` protocol, so you drive it with the same `LanguageModelSession` API you use for Apple's on-device model — `respond(to:)`, streaming, guided generation, and tool calling all work the same way.

Requests are sent through the Bedrock [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) or [ConverseStream](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html) API.

> **Beta.** This package targets the Foundation Models server-side language model API introduced in the OS 27 betas. APIs may change before general availability.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Examples](#examples)
- [Choosing a model](#choosing-a-model)
- [Authentication](#authentication)
- [Converse vs ConverseStream](#converse-vs-conversestream)
- [Streaming](#streaming)
- [Structured output](#structured-output)
- [Tool use](#tool-use)
- [Generation options](#generation-options)
- [Prompt caching](#prompt-caching)
- [Guardrails](#guardrails)
- [Attachments](#attachments)
- [Document citations](#document-citations)
- [Response metadata](#response-metadata)
- [What this package provides](#what-this-package-provides)

## Requirements

- iOS 27.2, macOS 27.2, visionOS 27.2, or watchOS 27.2 (beta) — the OS releases whose Foundation Models framework supports server-side language models.
- Xcode 27 (beta).
- AWS credentials (or an Amazon Bedrock API key) with access to the model you want to use. See [Authentication](#authentication).

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/0Itsuki0/BedrockForFoundationModels.git", branch: "main")
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and enter the repository URL.

Then add `BedrockForFoundationModels` to your target's dependencies and import it alongside `FoundationModels`:

```swift
import FoundationModels
import BedrockForFoundationModels
```

## Quick start

```swift
import FoundationModels
import BedrockForFoundationModels

let model = BedrockLanguageModel(
  modelId: "anthropic.claude-sonnet-5"
)

let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "Plan a 4-day trip to Buenos Aires.")
print(response.content)
```

`BedrockLanguageModel` is the entry point. Pass it to `LanguageModelSession` and use the session exactly as you would with any Foundation Models provider.

## Examples

[`Examples`](Examples) contains one example function per feature. Each takes a `stream` parameter to switch between the Converse and ConverseStream API.

| File | Function | |
|---|---|---|
| [`BasicExample.swift`](Examples/BasicExample.swift) | `basicExample(stream:)` | Multi-turn text generation with `session.respond` |
| [`MultiTurnExample.swift`](Examples/MultiTurnExample.swift) | `multiTurnExample(stream:)` | Multiple calls on one session, and a session created from an existing `Transcript` |
| [`StreamExample.swift`](Examples/StreamExample.swift) | `streamExample(stream:)` | `session.streamResponse` |
| [`StructuredOutputExample.swift`](Examples/StructuredOutputExample.swift) | `structuredOutputExample(stream:)` | `@Generable` structured output |
| [`ToolUseExample.swift`](Examples/ToolUseExample.swift) | `toolUseExample(stream:)` | Client-side tool calling |
| [`DocumentCitationExample.swift`](Examples/DocumentCitationExample.swift) | `documentCitationExample(stream:)` | Document attachments with citations |
| [`ResponseMetadataExample.swift`](Examples/ResponseMetadataExample.swift) | `responseMetadataExample(stream:)` | Extracting `ResponseMetadata` (citations, metrics, additional fields) |
| [`AdvancedConfigurationExample.swift`](Examples/AdvancedConfigurationExample.swift) | `advancedConfigurationExample(stream:)` | Advanced configuration: STS AssumeRole credentials, inference profile, guardrail, caching, performance |

The placeholder model ID is in [`ExampleConstants.swift`](Examples/ExampleConstants.swift).

## Choosing a model

`modelId` accepts anything the Converse API accepts as `modelId`:

- A base model ID or ARN. See [Supported foundation models](https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html).
- An inference profile ID or ARN, including application inference profiles. See [Inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html).
- A Provisioned Throughput ARN.

```swift
BedrockLanguageModel(
  modelId: "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/your-profile-id"
)
```

Feature support (tool use, structured output, citations, document/video/audio input, ...) depends on the model. See [Supported models and model features](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference-supported-models-features.html).

## Authentication

By default, `region` and credentials are resolved by the AWS SDK default chain (environment variables, shared config / SSO profile, etc.).

```swift
// Default chain.
BedrockLanguageModel(modelId: modelId)

// Static credentials, for example temporary credentials from STS AssumeRole.
// Overrides the default chain for SigV4 signing.
BedrockLanguageModel(
  modelId: modelId,
  credential: .init(
    accessKeyId: "...",
    secretAccessKey: "...",
    sessionToken: "..."
  )
)

// Amazon Bedrock API key (bearer token) instead of SigV4 signing.
BedrockLanguageModel(modelId: modelId, apiKey: "...")
```

See [Amazon Bedrock API keys](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html) and [`AdvancedConfigurationExample.swift`](Examples/AdvancedConfigurationExample.swift) for assuming a role with STS.

## Converse vs ConverseStream

`stream:` chooses the Bedrock API:

```swift
BedrockLanguageModel(modelId: modelId, stream: true) // ConverseStream
BedrockLanguageModel(modelId: modelId, stream: false) // Converse (default)
```

This is independent of `session.respond` / `session.streamResponse`. Both session APIs work with either setting; with `stream: false`, `streamResponse` delivers the complete output at once.

## Streaming

`streamResponse(to:)` returns the response incrementally. Each element is a cumulative snapshot:

```swift
let model = BedrockLanguageModel(modelId: modelId, stream: true)
let session = LanguageModelSession(model: model)

var printed = ""
for try await snapshot in session.streamResponse(to: "Summarize today's top science stories.") {
  // snapshots are cumulative: print only the newly generated part
  print(snapshot.content.dropFirst(printed.count), terminator: "")
  printed = snapshot.content
}
```

## Structured output

Annotate a type with `@Generable` and request it with `generating:`. The schema is sent as a strict JSON schema with Bedrock [structured output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html):

```swift
@Generable
struct Trip {
  @Guide(description: "Destination city") var destination: String
  @Guide(description: "Places to visit") var places: [String]
}

let response = try await session.respond(to: "Plan a trip to Tokyo.", generating: Trip.self)
print(response.content.destination)
```

Bedrock does not support:

- Recursive schemas
- Numerical constraints (`.minimum`, `.maximum`, `.range`)
- String constraints (minLength, maxLength)
- `.maximumCount` on arrays. `.minimumCount` only supports `0` or `1`.

## Tool use

Pass client-side tools with `tools:`. The session calls the tool and sends the result back to the model:

```swift
struct WeatherTool: Tool {
  let name = "getWeather"
  let description = "Get the current weather for a city."

  @Generable
  struct Arguments {
    @Guide(description: "The city to get the weather for.")
    var city: String
  }

  func call(arguments: Arguments) async throws -> String {
    "It is sunny and 22°C in \(arguments.city)."
  }
}

let session = LanguageModelSession(model: model, tools: [WeatherTool()])
let response = try await session.respond(to: "What's the weather like in Tokyo?")
```

`GenerationOptions.toolCallingMode` maps to the Bedrock [tool choice](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ToolChoice.html): `.allowed` → `auto`, `.required` → `any`, `.disallowed` → no tool choice.

Tool names must match `[a-zA-Z0-9_-]+` on Bedrock; other names are sanitized and mapped back automatically.

## Generation options

`GenerationOptions` and `ContextOptions` map to the Converse request:

| Foundation Models | Bedrock |
|---|---|
| `maximumResponseTokens` | `inferenceConfig.maxTokens` |
| `temperature` | `inferenceConfig.temperature` |
| `samplingMode: .greedy` | `inferenceConfig.temperature = 0` (if no temperature is set) |
| `samplingMode: .random(top:)` | `additionalModelRequestFields.inferenceConfig.topK` |
| `samplingMode: .random(probabilityThreshold:)` | `inferenceConfig.topP` |
| `reasoningLevel` | `outputConfig.effort` |

Reasoning levels map to effort: `.light` → `low`, `.moderate` → `medium`, `.deep` → `high`, and `.custom` accepts an effort name directly (`"xhigh"`, `"max"`).

Stop sequences, latency-optimized inference, and additional response fields are configured on the model:

```swift
BedrockLanguageModel(
  modelId: modelId,
  performance: .optimized,
  stopSequences: ["END"],
  additionalResponseFieldPaths: ["/stop_sequence"]
)
```

See [Latency optimized inference](https://docs.aws.amazon.com/bedrock/latest/userguide/latency-optimized-inference.html).

## Prompt caching

Each section is cached by injecting a cache point with the given TTL. A `nil` TTL (the default) disables caching for that section:

```swift
BedrockLanguageModel(
  modelId: modelId,
  cacheConfig: .init(
    toolsTTL: .fiveMinutes,       // after the last tool definition
    systemPromptTTL: .fiveMinutes, // at the end of the system prompt
    messagesTTL: .fiveMinutes      // on the last user message
  )
)
```

See [Prompt caching](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html).

## Guardrails

```swift
BedrockLanguageModel(
  modelId: modelId,
  guardrailConfig: .init(
    guardrailIdentifier: "your-guardrail-id",
    guardrailVersion: "1",
    trace: .enabled,
    streamProcessingMode: .async // only used with ConverseStream
  )
)
```

See [Amazon Bedrock Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html) and [Configure streaming response behavior](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-streaming.html).

## Attachments

Images and data attachments are sent as Bedrock image, document, video, and audio content blocks. Use `supportsDataAttachmentType(_:)` to check whether a type is supported:

| Kind | Formats |
|---|---|
| Document | csv, doc, docx, html, md, pdf, xls, xlsx, txt |
| Video | flv, mkv, mov, mpeg, mpg, 3gp, webm, wmv |
| Audio | aac, flac, m4a, mka, mkv, mp3, mp4, mpeg, ogg, opus, pcm, wav, webm, x-aac |

`UTType` constants for formats not declared by `UniformTypeIdentifiers` (`.docx`, `.xlsx`, `.flac`, ...) are provided by the package.

Document attachment metadata:

- `String.enableDocumentCitationKey` (`Bool`): enable citations for the document. Defaults to `false`.
- `String.documentNameKey` (`String`): the document name. The attachment's label takes precedence.

## Document citations

Enable citations with `String.enableDocumentCitationKey` in the attachment metadata:

```swift
struct TextDocument: DataAttachmentRepresentable {
  let text: String

  var transcriptRepresentation: Transcript.DataAttachment {
    .init(
      contentType: .plainText,
      content: Data(text.utf8),
      metadata: GeneratedContent(properties: [
        String.enableDocumentCitationKey: true
      ])
    )
  }
  // ...
}

let response = try await session.respond {
  Attachment(TextDocument(text: "Project Atlas is ..."))
    .label("Atlas-1")
  "What is Project Atlas? Answer based on the documents."
}
```

Citations are returned in the [response metadata](#response-metadata). See [`DocumentCitationExample.swift`](Examples/DocumentCitationExample.swift) and [CitationsConfig](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CitationsConfig.html).

## Response metadata

Each response entry carries a `ResponseMetadata` under `ResponseMetadata.metadataKey` (`"responseMetadata"`):

```json
{
  "responseMetadata": {
    "segmentMetadata": [
      {
        "segmentId": "3CEC8C02-6BCC-4792-89D9-9B4F7D62D7F1",
        "citations": [
          {
            "content": "",
            "citations": [
              {
                "title": "Atlas-1",
                "sourceContent": ["Project Atlas is an internal initiative to automate invoice processing."],
                "location": { "type": "documentchar", "documentIndex": 0, "start": 0, "end": 71 }
              }
            ]
          }
        ]
      }
    ],
    "metrics": { "latencyMs": 2420 }
  }
}
```

- `segmentMetadata`: per-segment citations. `segmentId` matches the id of a segment in the response entry.
- `metrics`: Converse / ConverseStream metrics.
- `additionalModelResponseFields`: the fields requested with `additionalResponseFieldPaths`.

Extract it from the transcript:

```swift
if case .response(let entry) = session.transcript.last,
   let content = entry.metadata[ResponseMetadata.metadataKey] {
  let metadata = try ResponseMetadata(content)
  for segmentMetadata in metadata.segmentMetadata {
    for citationContent in segmentMetadata.citations {
      for citation in citationContent.citations {
        print(citation.title ?? "", citation.location as Any)
      }
    }
  }
}
```

See [`ResponseMetadataExample.swift`](Examples/ResponseMetadataExample.swift).

## What this package provides

The public surface is Apple's Foundation Models provider conformance plus the configuration types that reach it — `BedrockLanguageModel`, `BedrockExecutor`, `BedrockModelConfiguration`, and the response metadata types (`ResponseMetadata`, `SegmentMetadata`, `CitationContent`, `DocumentCitation`). It is not a general-purpose Bedrock Runtime client.
