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

public struct BedrockLanguageModel: LanguageModel {
    public let executorConfiguration: BedrockExecutor.Configuration

    public init(
        modelId: String,
        region: String? = nil,
        apiKey: String? = nil,
        credential: BedrockModelConfiguration.AWSCredentialIdentity? = nil,
        guardrailConfig: BedrockModelConfiguration.GuardrailConfiguration? =
            nil,
        cacheConfig: BedrockModelConfiguration.CacheConfiguration? = nil,
        performance: BedrockRuntimeClientTypes.PerformanceConfigLatency? = nil

    ) {
        self.init(
            executorConfiguration: .init(
                modelId: modelId,
                region: region,
                apiKey: apiKey,
                credential: credential,
                guardrailConfig: guardrailConfig,
                cacheConfig: cacheConfig,
                performance: performance
            )
        )
    }

    public init(executorConfiguration: BedrockExecutor.Configuration) {
        self.executorConfiguration = executorConfiguration
    }

    public typealias Executor = BedrockExecutor

    public var capabilities: LanguageModelCapabilities {
        return LanguageModelCapabilities([
            .toolCalling, .guidedGeneration, .reasoning, .vision,
        ])
    }

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

public nonisolated struct BedrockModelConfiguration: Hashable, Sendable {
    public let modelId: String
    public let region: String?
    /**
     * Amazon Bedrock API key for bearer token authentication.
     * When provided, requests use the API key instead of SigV4 signing.
     * @see https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys.html
     */
    public let apiKey: String?

    public let credential: AWSCredentialIdentity?

    public let guardrailConfig: GuardrailConfiguration?

    public let cacheConfig: CacheConfiguration?

    public let performance: BedrockRuntimeClientTypes.PerformanceConfigLatency?

    /// Configuration information for a guardrail that you use with the [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) operation.
    public struct GuardrailConfiguration: Hashable, Sendable {
        /// The identifier for the guardrail.
        public var guardrailIdentifier: Swift.String?
        /// The version of the guardrail.
        public var guardrailVersion: Swift.String?
        /// The trace behavior for the guardrail.
        public var trace: BedrockRuntimeClientTypes.GuardrailTrace?

        /// The processing mode. For more information, see Configure streaming response behavior in the Amazon Bedrock User Guide.
        public var streamProcessingMode:
            BedrockRuntimeClientTypes.GuardrailStreamProcessingMode?

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

    /// Creates AWS credentials with the specified keys and optionally an expiration and session token.
    ///
    /// - Parameters:
    ///   - accessKey: The access key
    ///   - secret: The secret for the provided access key
    ///   - accountID: The account ID for the credentials, if known.  Defaults to `nil`.
    ///   - expiration: The date when the credentials will expire and no longer be valid. If value is `nil` then the credentials never expire. Defaults to `nil`
    ///   - sessionToken: A session token for this session. Defaults to `nil`
    public struct AWSCredentialIdentity: Hashable, Sendable {
        public let accessKeyId: String
        public let secretAccessKey: String
        public let sessionToken: String?
        public let accountID: String?
        public let expiration: Date?

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

    /// https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html#prompt-caching-simplified
    public struct CacheConfiguration: Hashable, Sendable {
        /**
         * Cache the tool definitions. A TTL sets this section's duration; `false` disables it.
         *
         * @defaultValue true
         */
        public let toolsTTL: BedrockRuntimeClientTypes.CacheTTL?
        /**
         * Cache the system prompt, auto-injecting a cache point at its end so repeated calls with the same
         * static system prefix hit the cache. A TTL sets this section's duration; `true` (the default) reads
         * the value from `ttl`; `false` disables systemPrompt cache injection.
         *
         * @defaultValue true
         */
        public let systemPromptTTL: BedrockRuntimeClientTypes.CacheTTL?
        /**
         * Cache the conversation prefix, on the last user message. A TTL sets this section's duration;
         * `false` disables it.
         *
         * @defaultValue true
         */
        public let messagesTTL: BedrockRuntimeClientTypes.CacheTTL?

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

    public init(
        modelId: String,
        region: String?,
        apiKey: String?,
        credential: AWSCredentialIdentity? = nil,
        guardrailConfig: GuardrailConfiguration? = nil,
        cacheConfig: CacheConfiguration? = nil,
        performance: BedrockRuntimeClientTypes.PerformanceConfigLatency? = nil
    ) {
        self.modelId = modelId
        self.region = region
        self.apiKey = apiKey
        self.credential = credential
        self.guardrailConfig = guardrailConfig
        self.cacheConfig = cacheConfig
        self.performance = performance
    }
}

public struct BedrockExecutor: LanguageModelExecutor {
    public typealias Configuration = BedrockModelConfiguration

    public typealias Model = BedrockLanguageModel

    public init(configuration: Configuration) throws {}

    public func prewarm(model: BedrockLanguageModel, transcript: Transcript) {}

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        print(request.metadata)
        if let stream = request.metadata[RequestMetadataKey.stream.rawValue],
            (try? stream.value(Bool.self)) == true
        {
            try await self.stream(
                to: request,
                model: model,
                streamingInto: channel
            )
            return
        }

        let (converseInput, toolNameMap) =
            try BedrockRequestBuilder.buildConverseInput(
                from: request,
                model: model
            )

        for (index, message) in (converseInput.messages ?? []).enumerated() {
            print("--index \(index)--")
            print(message.role as Any)
            print(message.content as Any)
        }

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

    private func stream(
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

        for (index, message) in (converseInput.messages ?? []).enumerated() {
            print("--index \(index)--")
            print(message.role as Any)
            print(message.content as Any)
        }

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

}
