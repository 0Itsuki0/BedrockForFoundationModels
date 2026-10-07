//
//  BedrockLanguageModel.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//

//
//  BedrockLanguageModel.swift
//  CustomLanguageModel
//
//  Created by Itsuki on 2026/10/03.
//

import AWSBedrockRuntime
import Foundation
import FoundationModels
import UniformTypeIdentifiers

/// Amazon Bedrock as a Foundation Models server-side language model.
///
/// Requests are sent through the Bedrock
/// [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) or
/// [ConverseStream](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html) API.
///
/// ```swift
/// let model = BedrockLanguageModel(modelId: "anthropic.claude-sonnet-5")
/// let session = LanguageModelSession(model: model)
/// let response = try await session.respond(to: "...") // or session.streamResponse(to: "...")
/// ```
///
/// For more examples, refer to Examples.
///
/// - SeeAlso: [Carry out a conversation with the Converse API operations](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html)
public struct BedrockLanguageModel: LanguageModel {
    public typealias Executor = BedrockExecutor

    /// The configuration used by ``BedrockExecutor`` to build and send requests.
    public let executorConfiguration: BedrockExecutor.Configuration

    /// Creates a BedrockLanguageModel from individual parameters.
    ///
    /// - Parameters:
    ///   - modelId: The model ID, inference profile ID, or ARN to run inference with.
    ///     See [Supported foundation models in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html).
    ///   - region: The AWS region of the Bedrock service. If `nil`, the region is resolved by the AWS SDK default chain.
    ///   - apiKey: An Amazon Bedrock API key for bearer token authentication. When provided, requests use the API key instead of SigV4 signing.
    ///     See [Amazon Bedrock API keys](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html).
    ///   - credential: Static AWS credentials. If `nil`, credentials are resolved by the AWS SDK default chain.
    ///   - guardrailConfig: Guardrail configuration for content filtering and safety controls.
    ///     See [Amazon Bedrock Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html).
    ///   - cacheConfig: Prompt caching configuration.
    ///     See [Prompt caching](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html).
    ///   - performance: Latency setting. Set to `.optimized` to use a latency-optimized version of the model.
    ///     See [Latency optimized inference](https://docs.aws.amazon.com/bedrock/latest/userguide/latency-optimized-inference.html).
    ///   - stopSequences: Sequences that will stop generation when encountered.
    ///   - stream: Whether to use the ConverseStream API instead of the Converse API. Defaults to `false`.
    ///   - additionalResponseFieldPaths: Additional model response field paths (JSON Pointers) to return in the response.
    ///
    /// - Note:
    ///    - `stream` controls whether to use Converse API or Converse Stream API. It is independent of the session.respond or session.streamResponse usage.
    public init(
        modelId: String,
        region: String? = nil,
        apiKey: String? = nil,
        credential: BedrockModelConfiguration.AWSCredentialIdentity? = nil,
        guardrailConfig: BedrockModelConfiguration.GuardrailConfiguration? =
            nil,
        cacheConfig: BedrockModelConfiguration.CacheConfiguration? = nil,
        performance: BedrockRuntimeClientTypes.PerformanceConfigLatency? = nil,
        stopSequences: [String]? = nil,
        stream: Bool = false,
        additionalResponseFieldPaths: [String]? = nil

    ) {
        self.init(
            executorConfiguration: .init(
                modelId: modelId,
                region: region,
                apiKey: apiKey,
                credential: credential,
                guardrailConfig: guardrailConfig,
                cacheConfig: cacheConfig,
                performance: performance,
                stopSequences: stopSequences,
                stream: stream,
                additionalResponseFieldPaths: additionalResponseFieldPaths
            )
        )
    }

    /// Creates a BedrockLanguageModel from executor configuration.
    ///
    /// - Parameters:
    ///   - executorConfiguration: The configuration used to build and send requests to Bedrock.
    public init(executorConfiguration: BedrockExecutor.Configuration) {
        self.executorConfiguration = executorConfiguration
    }

    /// The capabilities supported by this model: tool calling, guided generation, reasoning, and vision.
    ///
    /// Actual support depends on the underlying model.
    /// See [Supported models and model features](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference-supported-models-features.html).
    public var capabilities: LanguageModelCapabilities {
        return LanguageModelCapabilities([
            .toolCalling, .guidedGeneration, .reasoning, .vision,
        ])
    }

    /// Returns whether the given type can be sent as a document, video, or audio content block.
    ///
    /// - Parameters:
    ///   - type: The uniform type of the data attachment.
    /// - Returns: `true` if the type maps to a Bedrock `DocumentFormat`, `VideoFormat`, or `AudioFormat`.
    ///
    /// - SeeAlso: [DocumentBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_DocumentBlock.html),
    ///   [VideoBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_VideoBlock.html),
    ///   [AudioBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_AudioBlock.html)
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool
    {
        if BedrockRuntimeClientTypes.DocumentFormat.fromUTType(type) != nil {
            return true
        }

        if BedrockRuntimeClientTypes.VideoFormat.fromUTType(type) != nil {
            return true
        }
        if BedrockRuntimeClientTypes.AudioFormat.fromUTType(type) != nil {
            return true
        }
        return false
    }
}

/// Configuration for ``BedrockLanguageModel``, used by ``BedrockExecutor`` to build and send requests.
public nonisolated struct BedrockModelConfiguration: Hashable, Sendable {
    /// The model ID, inference profile ID, or ARN to run inference with.
    ///
    /// - SeeAlso: [Supported foundation models in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html),
    ///   [Inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html)
    public let modelId: String

    /// The AWS region of the Bedrock service.
    ///
    /// If `nil`, the region is resolved by the AWS SDK default chain.
    public let region: String?

    /// Amazon Bedrock API key for bearer token authentication.
    ///
    /// When provided, requests use the API key instead of SigV4 signing.
    ///
    /// - SeeAlso: [Amazon Bedrock API keys](https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html)
    public let apiKey: String?

    /// Static AWS credentials used for SigV4 signing.
    ///
    /// If `nil`, credentials are resolved by the AWS SDK default chain.
    public let credential: AWSCredentialIdentity?

    /// Guardrail configuration for content filtering and safety controls.
    ///
    /// - SeeAlso: [Amazon Bedrock Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html)
    public let guardrailConfig: GuardrailConfiguration?

    /// Prompt caching configuration.
    ///
    /// - SeeAlso: [Prompt caching](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html)
    public let cacheConfig: CacheConfiguration?

    /// Latency setting. Set to `.optimized` to use a latency-optimized version of the model.
    ///
    /// - SeeAlso: [Latency optimized inference](https://docs.aws.amazon.com/bedrock/latest/userguide/latency-optimized-inference.html)
    public let performance: BedrockRuntimeClientTypes.PerformanceConfigLatency?

    /// Sequences that will stop generation when encountered.
    ///
    /// - SeeAlso: [InferenceConfiguration](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_InferenceConfiguration.html)
    public let stopSequences: [String]?

    /// Whether or not to stream responses from the model.
    ///
    /// This will use the ConverseStream API instead of the Converse API.
    ///
    /// - SeeAlso: [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html),
    ///   [ConverseStream](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html)
    let stream: Bool

    /// Additional model response field paths (JSON Pointers) to extract from the Bedrock response.
    ///
    /// - SeeAlso: [Converse request syntax](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html#API_runtime_Converse_RequestSyntax)
    let additionalResponseFieldPaths: [String]?

    /// Configuration information for a guardrail that you use with the [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html)
    /// and [ConverseStream](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html) operations.
    ///
    /// - SeeAlso: [Use a guardrail with the Converse API](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-use-converse-api.html)
    public struct GuardrailConfiguration: Hashable, Sendable {
        /// The identifier for the guardrail.
        public var guardrailIdentifier: Swift.String?
        /// The version of the guardrail.
        public var guardrailVersion: Swift.String?
        /// The trace behavior for the guardrail.
        public var trace: BedrockRuntimeClientTypes.GuardrailTrace?

        /// The processing mode. Only used with the ConverseStream API.
        ///
        /// - SeeAlso: [Configure streaming response behavior to filter content](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-streaming.html)
        public var streamProcessingMode:
            BedrockRuntimeClientTypes.GuardrailStreamProcessingMode?

        /// Creates a guardrail configuration.
        ///
        /// - Parameters:
        ///   - guardrailIdentifier: The identifier for the guardrail.
        ///   - guardrailVersion: The version of the guardrail.
        ///   - trace: The trace behavior for the guardrail.
        ///   - streamProcessingMode: The processing mode. Only used with the ConverseStream API.
        public init(
            guardrailIdentifier: String?,
            guardrailVersion: String?,
            trace: BedrockRuntimeClientTypes.GuardrailTrace?,
            streamProcessingMode: BedrockRuntimeClientTypes
                .GuardrailStreamProcessingMode?
        ) {
            self.guardrailIdentifier = guardrailIdentifier
            self.guardrailVersion = guardrailVersion
            self.trace = trace
            self.streamProcessingMode = streamProcessingMode
        }
    }

    /// Static AWS credentials used for SigV4 signing.
    ///
    /// - SeeAlso: [AWS security credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/security-creds.html)
    public struct AWSCredentialIdentity: Hashable, Sendable {
        /// The access key ID.
        public let accessKeyId: String
        /// The secret for the provided access key.
        public let secretAccessKey: String
        /// A session token for temporary credentials.
        public let sessionToken: String?
        /// The account ID for the credentials, if known.
        public let accountID: String?
        /// The date when the credentials will expire and no longer be valid. If `nil`, the credentials never expire.
        public let expiration: Date?

        /// Creates AWS credentials with the specified keys and optionally an expiration and session token.
        ///
        /// - Parameters:
        ///   - accessKeyId: The access key ID.
        ///   - secretAccessKey: The secret for the provided access key.
        ///   - sessionToken: A session token for this session. Defaults to `nil`.
        ///   - accountID: The account ID for the credentials, if known. Defaults to `nil`.
        ///   - expiration: The date when the credentials will expire and no longer be valid. If value is `nil` then the credentials never expire. Defaults to `nil`.
        public init(
            accessKeyId: String,
            secretAccessKey: String,
            sessionToken: String? = nil,
            accountID: String? = nil,
            expiration: Date? = nil
        ) {
            self.accessKeyId = accessKeyId
            self.secretAccessKey = secretAccessKey
            self.sessionToken = sessionToken
            self.accountID = accountID
            self.expiration = expiration
        }
    }

    /// Prompt caching configuration.
    ///
    /// Each section is cached by injecting a cache point with the given TTL. A `nil` TTL disables caching for that section.
    ///
    /// - SeeAlso: [Prompt caching](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html#prompt-caching-simplified),
    ///   [CachePointBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CachePointBlock.html)
    public struct CacheConfiguration: Hashable, Sendable {
        /// Cache the tool definitions, injecting a cache point after the last tool.
        ///
        /// The TTL sets this section's duration; `nil` disables it.
        public let toolsTTL: BedrockRuntimeClientTypes.CacheTTL?

        /// Cache the system prompt, injecting a cache point at its end so repeated calls with the same
        /// static system prefix hit the cache.
        ///
        /// The TTL sets this section's duration; `nil` disables it.
        public let systemPromptTTL: BedrockRuntimeClientTypes.CacheTTL?

        /// Cache the conversation prefix, on the last user message.
        ///
        /// The TTL sets this section's duration; `nil` disables it.
        public let messagesTTL: BedrockRuntimeClientTypes.CacheTTL?

        /// Creates a prompt caching configuration.
        ///
        /// - Parameters:
        ///   - toolsTTL: The TTL for the tool definitions cache. `nil` disables it. Defaults to `nil`.
        ///   - systemPromptTTL: The TTL for the system prompt cache. `nil` disables it. Defaults to `nil`.
        ///   - messagesTTL: The TTL for the conversation prefix cache. `nil` disables it. Defaults to `nil`.
        public init(
            toolsTTL: BedrockRuntimeClientTypes.CacheTTL? = nil,
            systemPromptTTL: BedrockRuntimeClientTypes.CacheTTL? = nil,
            messagesTTL: BedrockRuntimeClientTypes.CacheTTL? = nil
        ) {
            self.toolsTTL = toolsTTL
            self.systemPromptTTL = systemPromptTTL
            self.messagesTTL = messagesTTL
        }
    }

    /// Creates a Configuration for use with `BedrockLanguageModel`.
    ///
    /// - Parameters:
    ///   - modelId: The model ID, inference profile ID, or ARN to run inference with.
    ///   - region: The AWS region of the Bedrock service. If `nil`, the region is resolved by the AWS SDK default chain.
    ///   - apiKey: An Amazon Bedrock API key for bearer token authentication. When provided, requests use the API key instead of SigV4 signing.
    ///   - credential: Static AWS credentials. If `nil`, credentials are resolved by the AWS SDK default chain.
    ///   - guardrailConfig: Guardrail configuration for content filtering and safety controls.
    ///   - cacheConfig: Prompt caching configuration.
    ///   - performance: Latency setting. Set to `.optimized` to use a latency-optimized version of the model.
    ///   - stopSequences: Sequences that will stop generation when encountered.
    ///   - stream: Whether to use the ConverseStream API instead of the Converse API. Defaults to `false`.
    ///   - additionalResponseFieldPaths: Additional model response field paths (JSON Pointers) to return in the response.
    ///
    /// - Note:
    ///    - `stream` controls whether to use Converse API or Converse Stream API. It is independent of the session.respond or session.streamResponse usage.
    public init(
        modelId: String,
        region: String? = nil,
        apiKey: String? = nil,
        credential: AWSCredentialIdentity? = nil,
        guardrailConfig: GuardrailConfiguration? = nil,
        cacheConfig: CacheConfiguration? = nil,
        performance: BedrockRuntimeClientTypes.PerformanceConfigLatency? = nil,
        stopSequences: [String]? = nil,
        stream: Bool = false,
        additionalResponseFieldPaths: [String]? = nil

    ) {
        self.modelId = modelId
        self.region = region
        self.apiKey = apiKey
        self.credential = credential
        self.guardrailConfig = guardrailConfig
        self.cacheConfig = cacheConfig
        self.performance = performance
        self.stopSequences = stopSequences
        self.stream = stream
        self.additionalResponseFieldPaths = additionalResponseFieldPaths
    }
}

/// The executor that sends ``BedrockLanguageModel`` requests to Amazon Bedrock.
public struct BedrockExecutor: LanguageModelExecutor {
    public typealias Configuration = BedrockModelConfiguration

    public typealias Model = BedrockLanguageModel

    public init(configuration: Configuration) throws {}

    /// No-op. Bedrock is a server-side model and requires no prewarming.
    public func prewarm(model: BedrockLanguageModel, transcript: Transcript) {}

    /// Generates a response for the request and streams it into the channel.
    ///
    /// Uses the [ConverseStream](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html) API
    /// if ``BedrockModelConfiguration`` `stream` is `true`, otherwise the
    /// [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) API.
    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        if model.executorConfiguration.stream {
            try await self.respondWithConverseStream(
                to: request,
                model: model,
                streamingInto: channel
            )
        } else {
            try await self.respondWithConverse(
                to: request,
                model: model,
                streamingInto: channel
            )
        }
    }

    /// Generates a response with the [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) API
    /// and sends the complete output into the channel.
    public func respondWithConverse(
        to request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {

        let (converseInput, toolNameMap) =
            try BedrockRequestBuilder.buildConverseInput(
                from: request,
                model: model
            )

        printMessages(messages: converseInput.messages)

        let runtimeConfig =
            try await BedrockClientConfigBuilder.buildClientConfig(model: model)

        let client = BedrockRuntimeClient(config: runtimeConfig)

        let response = try await client.converse(input: converseInput)

        try await BedrockResponseHandler.handleConverseOutput(
            response: response,
            streamingInto: channel,
            toolNameMap: toolNameMap
        )
    }

    private func respondWithConverseStream(
        to request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        print(#function)

        let (converseInput, toolNameMap) =
            try BedrockRequestBuilder.buildConverseStreamInput(
                from: request,
                model: model
            )

        printMessages(messages: converseInput.messages)

        let runtimeConfig =
            try await BedrockClientConfigBuilder.buildClientConfig(model: model)

        let client = BedrockRuntimeClient(config: runtimeConfig)

        let response = try await client.converseStream(input: converseInput)

        try await BedrockResponseHandler.handleConverseStream(
            response: response,
            streamingInto: channel,
            toolNameMap: toolNameMap
        )
    }

    private func printMessages(messages: [BedrockRuntimeClientTypes.Message]?) {
        #if DEBUG
            print()
            print("----Messages----")
            for (index, message) in (messages ?? []).enumerated() {
                print("--index \(index)--")
                print(message.role as Any)
                print(message.content as Any)
            }
            print("----End----")
            print()
        #endif
    }
}
