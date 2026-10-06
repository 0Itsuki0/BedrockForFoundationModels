//
//  BedrockRequestBuilder.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//

import AWSBedrockRuntime
import CoreImage
import FoundationModels
@_spi(SmithyDocumentImpl) import Smithy
import SmithyJSON
import UniformTypeIdentifiers

nonisolated enum BedrockRequestBuilder {

    enum Error: LocalizedError, Sendable {
        case unsupportedDataAttachmentType
    }

    /// Additional inference parameters that the model supports, beyond the base set of inference parameters that Converse and ConverseStream support in the inferenceConfig field. For more information, see [Model parameters](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters.html).
    //    public var additionalModelRequestFields: Smithy.Document?
    //    /// Additional model parameters field paths to return in the response. Converse and ConverseStream return the requested fields as a JSON Pointer object in the additionalModelResponseFields field. The following is example JSON for additionalModelResponseFieldPaths. [ "/stop_sequence" ] For information about the JSON Pointer syntax, see the [Internet Engineering Task Force (IETF)](https://datatracker.ietf.org/doc/html/rfc6901) documentation. Converse and ConverseStream reject an empty JSON Pointer or incorrectly structured JSON Pointer with a 400 error code. if the JSON Pointer is valid, but the requested field is not in the model response, it is ignored by Converse.
    //    public var additionalModelResponseFieldPaths: [Swift.String]?
    //    /// Configuration information for a guardrail that you want to use in the request. If you include guardContent blocks in the content field in the messages field, the guardrail operates only on those messages. If you include no guardContent blocks, the guardrail operates on all messages in the request body and in any included prompt resource.
    //    public var guardrailConfig: BedrockRuntimeClientTypes.GuardrailStreamConfiguration?
    //    /// Inference parameters to pass to the model. Converse and ConverseStream support a base set of inference parameters. If you need to pass additional parameters that the model supports, use the additionalModelRequestFields request field.
    //    public var inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration?
    //    /// The messages that you want to send to the model.
    //    public var messages: [BedrockRuntimeClientTypes.Message]?
    //    /// Specifies the model or throughput with which to run inference, or the prompt resource to use in inference. The value depends on the resource that you use:
    //    ///
    //    /// * If you use a base model, specify the model ID or its ARN. For a list of model IDs for base models, see [Amazon Bedrock base model IDs (on-demand throughput)](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html#model-ids-arns) in the Amazon Bedrock User Guide.
    //    ///
    //    /// * If you use an inference profile, specify the inference profile ID or its ARN. For a list of inference profile IDs, see [Supported Regions and models for cross-region inference](https://docs.aws.amazon.com/bedrock/latest/userguide/cross-region-inference-support.html) in the Amazon Bedrock User Guide.
    //    ///
    //    /// * If you use a provisioned model, specify the ARN of the Provisioned Throughput. For more information, see [Run inference using a Provisioned Throughput](https://docs.aws.amazon.com/bedrock/latest/userguide/prov-thru-use.html) in the Amazon Bedrock User Guide.
    //    ///
    //    /// * If you use a custom model, first purchase Provisioned Throughput for it. Then specify the ARN of the resulting provisioned model. For more information, see [Use a custom model in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-use.html) in the Amazon Bedrock User Guide.
    //    ///
    //    /// * To include a prompt that was defined in [Prompt management](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-management.html), specify the ARN of the prompt version to use.
    //    ///
    //    ///
    //    /// The Converse API doesn't support [imported models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-import-model.html).
    //    /// This member is required.
    //    public var modelId: Swift.String?
    //    /// Output configuration for a model response.
    //    public var outputConfig: BedrockRuntimeClientTypes.OutputConfig?
    //    /// Model performance settings for the request.
    //    public var performanceConfig: BedrockRuntimeClientTypes.PerformanceConfiguration?
    //    /// Contains a map of variables in a prompt from Prompt management to objects containing the values to fill in for them when running model invocation. This field is ignored if you don't specify a prompt resource in the modelId field.
    //    public var promptVariables: [Swift.String: BedrockRuntimeClientTypes.PromptVariableValues]?
    //    /// Key-value pairs that you can use to filter invocation logs.
    //    public var requestMetadata: [Swift.String: Swift.String]?
    //    /// Specifies the processing tier configuration used for serving the request.
    //    public var serviceTier: BedrockRuntimeClientTypes.ServiceTier?
    //    /// A prompt that provides instructions or context to the model about the task it should perform, or the persona it should adopt during the conversation.
    //    public var system: [BedrockRuntimeClientTypes.SystemContentBlock]?
    //    /// Configuration information for the tools that the model can use when generating a response. For information about models that support streaming tool use, see [Supported models and model features](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html#conversation-inference-supported-models-features).
    //    public var toolConfig: BedrockRuntimeClientTypes.ToolConfiguration?

    // TODO: - converse stream
    static func buildConverseStreamInput(
        from request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel
    ) throws -> (ConverseStreamInput, [ToolNameMap]) {
        throw NSError(domain: "to be implemented", code: 0)
    }
    
    // TODO: - check image/document size
    static func checkAttachmentSize() {
        
    }

    private static func buildInferenceConfig(
        from request: LanguageModelExecutorGenerationRequest
    ) -> (
        config: BedrockRuntimeClientTypes.InferenceConfiguration,
        // map to be add to ConverseInput.additionalModelRequestFields
        additionalInferenceConfig: [String: SmithyDocument]?
    ) {
        var configuration = BedrockRuntimeClientTypes.InferenceConfiguration()
        var additionalInferenceConfig: [String: SmithyDocument] = [:]

        let generationOptions = request.generationOptions
        configuration.maxTokens = generationOptions.maximumResponseTokens
        configuration.temperature = generationOptions.temperature.map(
            Float.init
        )

        switch generationOptions.samplingMode?.kind {
        case .greedy:
            if generationOptions.temperature == nil {
                configuration.temperature = 0
            }
        case .randomTopK(let k, _):  // the API has no sampling-seed parameter
            /// Top k passed in with additionalModelRequestFields:
            /// https://docs.aws.amazon.com/nova/latest/userguide/using-converse-api.html
            /// additionalModelRequestFields = { "inferenceConfig": { "topK": 20 }}
            additionalInferenceConfig["topK"] = Smithy.Document(
                integerLiteral: k
            )
        case .randomProbabilityThreshold(let threshold, _):
            configuration.topp = Float(threshold)
        case nil:
            break
        @unknown default:
            break
        }

        return (
            configuration,
            additionalInferenceConfig.isEmpty
                ? nil
                : additionalInferenceConfig
        )
    }

    private static func buildGuardrailConfig(
        from executorConfiguration: BedrockExecutor.Configuration
    ) -> BedrockRuntimeClientTypes.GuardrailConfiguration? {
        guard let guardrailConfig = executorConfiguration.guardrailConfig else {
            return nil
        }

        return .init(
            guardrailIdentifier: guardrailConfig.guardrailIdentifier,
            guardrailVersion: guardrailConfig.guardrailVersion,
            trace: guardrailConfig.trace
        )
    }

    private static func sanitizedJsonSchema(from schema: GenerationSchema)
        throws
        -> String?
    {
        let document = try SmithyDocumentSupport.document(from: schema)
        let sanitized = try sanitizeForStructuredOutput(document)
        let jsonString = try SmithyDocumentSupport.jsonString(for: sanitized)
        return jsonString
    }

    /// https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html
    ///
    /// The following features are not supported by Bedrock:
    /// - Recursive schemas
    /// - External $ref references
    /// - Numerical constraints (minimum, maximum, multipleOf)
    /// - String constraints (minLength, maxLength)
    /// - additionalProperties set to anything other than false
    ///
    /// Additional Constrain:
    /// - Array types: FoundationModels' maximumCount (Bedrock maxItems): not supported. minimumCount (minItems): only support 0 or 1
    private static func sanitizeForStructuredOutput(_ value: SmithyDocument)
        throws
        -> SmithyDocument
    {
        let unsupportedProperties = [
            "x-order", "maxItems", "minimum", "maximum", "multipleOf",
            "minLength", "maxLength",
        ]
        switch value.type {
        case .map:
            var out = try value.asStringMap()
            for (key, value) in out {
                if unsupportedProperties.contains(key) {
                    out.removeValue(forKey: key)
                } else {
                    out[key] = try sanitizeForStructuredOutput(value)
                }
            }
            return StringMapDocument(value: out)
        case .list:
            var out = try value.asList()
            out = try out.map({ try sanitizeForStructuredOutput($0) })
            return ListDocument(value: out)
        default:
            return value
        }
    }

    private static func buildOutputConfig(
        from request: LanguageModelExecutorGenerationRequest,
    ) throws -> BedrockRuntimeClientTypes.OutputConfig {
        var config = BedrockRuntimeClientTypes.OutputConfig()
        config.effort =
            request.contextOptions.reasoningLevel?.outputEffort?.rawValue

        // LanguageModelExecutorGenerationRequest.schema contains
        // the generation schema of the last respond/streamResponse call
        if let schema = request.schema {
            config.textFormat = .init(
                structure: .jsonschema(
                    .init(
                        description: nil,
                        name: schema.name,
                        schema: try sanitizedJsonSchema(from: schema)
                    )
                ),
                type: .jsonSchema
            )
        }
        return config
    }

    // TODO: Add cache points based on the cache config
    static func buildConverseInput(
        from request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel
    ) throws -> (ConverseInput, [ToolNameMap]) {
        let executorConfiguration = model.executorConfiguration
        // https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html#prompt-caching-simplified
        let cacheConfig = executorConfiguration.cacheConfig

        /// Strict JSON Schema via constrained decoding (`output_config.format`) —
        /// the model cannot emit a token that violates the schema. Compatible with
        /// thinking; the response streams as plain text deltas containing valid
        /// JSON. Nothing is added to `system`. The API shows the model the schema
        /// itself whenever a format is set. And `system` has to stay the same
        /// across a session's requests: the API can reject a replayed thinking
        /// block once the conversation before it has changed, and the system prompt
        /// is part of that conversation. `includeSchemaInPrompt` is moot for the
        /// same reason: the schema always reaches the model.

        var input = ConverseInput()
        let inferenceConfig = buildInferenceConfig(from: request)
        input.inferenceConfig = inferenceConfig.config
        var additionalModelRequestFields: [String: SmithyDocument] = [:]

        // https://docs.aws.amazon.com/nova/latest/userguide/using-converse-api.html
        if let additionalInferenceConfig = inferenceConfig
            .additionalInferenceConfig
        {
            additionalModelRequestFields["inferenceConfig"] = StringMapDocument(
                value: additionalInferenceConfig
            )
        }

        input.outputConfig = try buildOutputConfig(from: request)

        var toolNameMap: [ToolNameMap] = []
        if let config = try buildToolConfig(
            tools: request.enabledToolDefinitions,
            callingMode: request.generationOptions.toolCallingMode,
            cacheConfig: cacheConfig?.toolsTTL
        ) {
            input.toolConfig = config.0
            toolNameMap = config.1
        }

        input.modelId = executorConfiguration.modelId
        input.guardrailConfig = buildGuardrailConfig(
            from: executorConfiguration
        )

        input.performanceConfig = .init(
            latency: executorConfiguration.performance
        )

        var system: [BedrockRuntimeClientTypes.SystemContentBlock] = []
        var messages: [BedrockRuntimeClientTypes.Message] = []
        var isToolOutputTurn: Bool = false

        func addMessage(
            _ blocks: [BedrockRuntimeClientTypes.ContentBlock],
            _ role: BedrockRuntimeClientTypes.ConversationRole
        ) {
            if !blocks.isEmpty {
                messages.append(.init(content: blocks, role: role))
            }
        }

        for (index, entry) in request.transcript.enumerated() {
            switch entry {
            case .instructions(let instruction):
                if let block = systemContentBlock(from: instruction) {
                    system.append(block)
                }

            case .prompt(let prompt):
                addMessage(try contentBlocks(from: prompt.segments), .user)
            case .toolOutput(let toolOutput):
                addMessage(
                    [try toolResultContentBlocks(from: toolOutput)],
                    .user
                )
                if index == request.transcript.count - 1 {
                    isToolOutputTurn = true
                }
            case .data(let dataEntry):
                print(
                    "Received data entry, still trying to figure out where to put it."
                )
                print(dataEntry.description)
                continue

            case .toolCalls(let toolCalls):

                addMessage(
                    toolCallContentBlocks(
                        from: toolCalls,
                        toolNameMap: toolNameMap
                    ),
                    .assistant
                )
                continue
            case .response(let response):
                addMessage(
                    try contentBlocks(from: response.segments),
                    .assistant
                )
            case .reasoning(let reasoning):
                addMessage(
                    [reasoningContentBlock(from: reasoning)],
                    .assistant
                )

            @unknown default:
                print("Received unknown entry type", entry.description)
                continue
            }
        }
        // print("messages: ", messages)
        messages = groupMessagesByRole(messages: messages)
        messages = addMessageCache(
            messages: messages,
            cacheConfig: cacheConfig?.messagesTTL
        )

        input.messages = messages

        if !system.isEmpty {
            input.system = system

            if let cachePoint = buildCachePoint(
                ttl: cacheConfig?.systemPromptTTL
            ) {
                input.system?.append(
                    .cachepoint(cachePoint)
                )
            }
        }

        if !additionalModelRequestFields.isEmpty {
            input.additionalModelRequestFields = .init(
                StringMapDocument(value: additionalModelRequestFields)
            )
        }

        // if it is tool output turn
        // forcing tool use will result in infinite tool calling loop
        if isToolOutputTurn {
            input.toolConfig?.toolChoice = .auto(.init())
        }

        return (input, toolNameMap)
    }

    /**
     * Ensure the last user message carries exactly one cache point.
     *
     * A cache point already present in the last user message is honored where it sits rather than
     * replaced: a caller places one to mark where its reusable prefix ends, ahead of content that is
     * rebuilt every call. Moving it to the end of the message would put that per-call content inside
     * the cached prefix, so every request would write a new entry and none would ever read one.
     *
     * Cache points in earlier messages are still removed, so they cannot accumulate one per turn
     * against the provider's cache-point budget.
     *
     * @param messages - List of messages to inject cache point into (modified in place)
     * @param ttl - TTL for the injected cache point. Falsy leaves the Bedrock default.
     */
    private static func addMessageCache(
        messages: [BedrockRuntimeClientTypes.Message],
        cacheConfig: BedrockRuntimeClientTypes.CacheTTL?
    ) -> [BedrockRuntimeClientTypes.Message] {
        guard let cachePoint = buildCachePoint(ttl: cacheConfig) else {
            return messages
        }

        guard
            let lastUserIndex = messages.lastIndex(where: { $0.role == .user })
        else {
            return messages
        }

        var messages = messages
        for (index, message) in messages.enumerated() {
            var message = message
            if index == lastUserIndex {
                if message.content?.contains(where: { $0.isCachePoint })
                    == false
                {
                    // NOTE:
                    // the problem mentioned in strands-ts of *placing cache point after PDF document causes ValidationException from Bedrock* might still exist.
                    // If so, the cache point needs to be placed before the last PDF.
                    // Ref: strands-ts/src/models/bedrock.ts line 1135 within `_injectCachePoint`
                    message.content?.append(.cachepoint(cachePoint))
                    messages[index] = message
                }

                continue
            }

            // remove cache points in earlier messages,
            // so they cannot accumulate one per turn against the provider's cache-point budget.
            message.content = message.content?.filter({ !$0.isCachePoint })
            messages[index] = message
        }

        return messages
    }

    //ValidationException(properties: AWSBedrockRuntime.ValidationException.Properties(message: Optional("2 validation errors detected: Value \'Count Tool\' at \'toolConfig.tools.1.member.toolSpec.name\' failed to satisfy constraint: Member must satisfy regular expression pattern: [a-zA-Z0-9_-]+; Value at \'system.1.member.text\' failed to satisfy constraint: Member must have length greater than or equal to 1")), httpResponse:
    /// Tool name has to be satisfy regular expression pattern [a-zA-Z0-9_-]+
    private static func bedrockToolName(_ name: String) -> String {
        name.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_"
                || $0 == "-"
                ? String($0)
                : "_\(String($0.value, radix: 16))"
        }.joined()
    }

    private static func tool(from tool: Transcript.ToolDefinition) throws
        -> (BedrockRuntimeClientTypes.Tool, ToolNameMap)
    {
        let schema = tool.parameters
        // The json Schema for tools doesn't seem to be needs sanitization
        let document = try SmithyDocumentSupport.document(from: schema)
        let originalName = tool.name
        let bedrockName = bedrockToolName(originalName)
        let specification = BedrockRuntimeClientTypes.ToolSpecification(
            description: tool.description,
            inputSchema: .json(document),
            name: bedrockName
        )
        let tool = BedrockRuntimeClientTypes.Tool.toolspec(specification)
        return (tool, .init(original: originalName, bedrock: bedrockName))
    }

    private static func buildToolConfig(
        tools: [Transcript.ToolDefinition],
        callingMode: GenerationOptions.ToolCallingMode?,
        cacheConfig: BedrockRuntimeClientTypes.CacheTTL?
    ) throws -> (BedrockRuntimeClientTypes.ToolConfiguration, [ToolNameMap])? {
        guard !tools.isEmpty, callingMode != .disallowed else {
            return nil
        }
        let toolsConfigs = try tools.map({
            try tool(from: $0)
        })

        var tools = toolsConfigs.map(\.0)

        if let cachePoint = buildCachePoint(ttl: cacheConfig) {
            tools.append(
                BedrockRuntimeClientTypes.Tool.cachepoint(cachePoint)
            )
        }

        let choice = toolChoice(for: callingMode)
        return (
            BedrockRuntimeClientTypes.ToolConfiguration(
                toolChoice: choice,
                tools: tools
            ), toolsConfigs.map(\.1)
        )
    }

    private static func buildCachePoint(
        ttl: BedrockRuntimeClientTypes.CacheTTL?
    ) -> BedrockRuntimeClientTypes.CachePointBlock? {
        guard let ttl else {
            return nil
        }
        return BedrockRuntimeClientTypes.CachePointBlock(
            ttl: ttl,
            type: .default
        )
    }

    private static func toolChoice(
        for mode: GenerationOptions.ToolCallingMode?
    ) -> BedrockRuntimeClientTypes.ToolChoice? {
        let auto = BedrockRuntimeClientTypes.ToolChoice.auto(.init())
        guard let mode else { return auto }
        switch mode.kind {
        case .required: return .any(.init())
        case .disallowed: return nil
        case .allowed: return auto
        @unknown default: return auto
        }
    }

    static private func groupMessagesByRole(
        messages: [BedrockRuntimeClientTypes.Message]
    ) -> [BedrockRuntimeClientTypes.Message] {
        var processed: [BedrockRuntimeClientTypes.Message] = []

        var turnBlocks: [BedrockRuntimeClientTypes.ContentBlock] = []
        var previousRole: BedrockRuntimeClientTypes.ConversationRole? = nil

        func closeTurn() {
            defer {
                turnBlocks = []
                previousRole = nil
            }
            guard let previousRole, !turnBlocks.isEmpty else {
                return
            }
            processed.append(.init(content: turnBlocks, role: previousRole))
        }

        for message in messages {
            if message.role != previousRole {
                closeTurn()
            }
            previousRole = message.role
            turnBlocks.append(contentsOf: message.content ?? [])
        }
        closeTurn()
        return processed
    }

    private static func text(
        of segments: [Transcript.Segment],
        separator: String = "\n"
    ) -> String {
        segments.compactMap {
            switch $0 {
            case .text(let t): t.content.isEmpty ? nil : t.content
            case .structure(let s): s.content.jsonString
            case .attachment: nil
            @unknown default: nil
            }
        }
        .joined(separator: separator)
    }

    private static func systemContentBlock(
        from instructions: Transcript.Instructions
    ) -> BedrockRuntimeClientTypes.SystemContentBlock? {
        let text = text(of: instructions.segments)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return .text(text)
    }

    private static func reasoningContentBlock(
        from reasoning: Transcript.Reasoning
    ) -> BedrockRuntimeClientTypes.ContentBlock {
        let signature: String? =
            if let signature = reasoning.signature {
                String(data: signature, encoding: .utf8)
            } else {
                nil
            }

        return .reasoningcontent(
            .reasoningtext(
                .init(
                    signature: signature,
                    text: text(of: reasoning.segments)
                )
            )
        )
    }

    private static func toolCallContentBlocks(
        from toolCalls: Transcript.ToolCalls,
        toolNameMap: [ToolNameMap]
    ) -> [BedrockRuntimeClientTypes.ContentBlock] {
        let blocks: [BedrockRuntimeClientTypes.ToolUseBlock] = toolCalls.map {
            toolCall in
            let name =
                toolNameMap.first(where: {
                    $0.original == toolCall.toolName
                })?.bedrock ?? toolCall.toolName
            return .init(
                input: SmithyDocumentSupport.document(from: toolCall.arguments),
                name: name,
                toolUseId: toolCall.id,
                type: nil
            )
        }
        return blocks.map({ .tooluse($0) })
    }

    private static func toolResultContentBlocks(
        from toolOutput: Transcript.ToolOutput
    ) throws -> BedrockRuntimeClientTypes.ContentBlock {
        let contentBlocks: [BedrockRuntimeClientTypes.ToolResultContentBlock] =
            try toolOutput.segments.map {
                segment -> BedrockRuntimeClientTypes.ToolResultContentBlock? in
                switch segment {
                case .text(let text):
                    if text.content.isEmpty {
                        nil
                    } else {
                        .text(text.content)
                    }
                case .structure(let structure):
                    if let document = SmithyDocumentSupport.document(
                        from: structure.content
                    ) {
                        .json(document)
                    } else {
                        nil
                    }
                case .attachment(let attachment):
                    switch attachment.content {
                    case .data(let dataAttachment):
                        try tooResultContentBlock(
                            from: dataAttachment,
                            label: attachment.label
                        )
                    case .image(let image):
                        .image(
                            .init(
                                format: .jpeg,
                                source: .bytes(try image.ciImage.jpegData)
                            )
                        )

                    @unknown default: nil
                    }
                @unknown default: nil
                }
            }.compactMap({ $0 })

        return .toolresult(
            .init(
                content: contentBlocks,
                status: .success,
                toolUseId: toolOutput.id,
                type: nil
            )
        )
    }

    private static func contentBlocks(from segments: [Transcript.Segment])
        throws -> [BedrockRuntimeClientTypes.ContentBlock]
    {
        try segments.map { segment -> BedrockRuntimeClientTypes.ContentBlock? in
            switch segment {
            case .text(let text):
                if text.content.isEmpty {
                    nil
                } else {
                    .text(text.content)
                }
            case .structure(let structure):
                .text(structure.content.jsonString)
            case .attachment(let attachment):
                switch attachment.content {
                case .data(let dataAttachment):
                    try contentBlock(
                        from: dataAttachment,
                        label: attachment.label
                    )
                case .image(let image):
                    .image(
                        .init(
                            format: .jpeg,
                            source: .bytes(try image.ciImage.jpegData)
                        )
                    )
                @unknown default: nil
                }
            @unknown default: nil
            }
        }.compactMap({ $0 })
    }

    private static func tooResultContentBlock(
        from dataAttachment: Transcript.DataAttachment,
        label: String?
    ) throws -> BedrockRuntimeClientTypes.ToolResultContentBlock {
        let bytes = dataAttachment.content
        let contentType = dataAttachment.contentType

        if let block = documentBlock(
            bytes: bytes,
            contentType: contentType,
            metadata: dataAttachment.metadata,
            label: label
        ) {
            return .document(block)
        }

        if let block = videoBlock(bytes: bytes, contentType: contentType) {
            return .video(block)
        }

        throw Error.unsupportedDataAttachmentType
    }

    private static func contentBlock(
        from dataAttachment: Transcript.DataAttachment,
        label: String?
    ) throws -> BedrockRuntimeClientTypes.ContentBlock {
        let bytes = dataAttachment.content
        let contentType = dataAttachment.contentType

        if let block = documentBlock(
            bytes: bytes,
            contentType: contentType,
            metadata: dataAttachment.metadata,
            label: label
        ) {
            return .document(block)
        }

        if let block = videoBlock(bytes: bytes, contentType: contentType) {
            return .video(block)
        }

        if let block = audioBlock(bytes: bytes, contentType: contentType) {
            return .audio(block)
        }

        throw Error.unsupportedDataAttachmentType
    }

    private static func documentBlock(
        bytes: Data,
        contentType: UTType,
        metadata: GeneratedContent,
        label: String?
    ) -> BedrockRuntimeClientTypes.DocumentBlock? {
        guard let documentFormat = contentType.documentFormat,
            !documentFormat.isUnknown
        else { return nil }

        let enableCitation =
            try? metadata.value(
                Bool.self,
                forProperty: .enableDocumentCitationKey
            )
        let name =
            label
            ?? (try? metadata.value(
                String.self,
                forProperty: .documentNameKey
            ))
        return .init(
            citations: .init(enabled: enableCitation ?? false),
            context: metadata.jsonString,
            format: documentFormat,
            name: name,
            source: .bytes(bytes)
        )
    }

    private static func videoBlock(
        bytes: Data,
        contentType: UTType
    ) -> BedrockRuntimeClientTypes.VideoBlock? {

        guard let videoFormat = contentType.videoFormat,
            !videoFormat.isUnknown
        else { return nil }

        return .init(
            format: videoFormat,
            source: .bytes(bytes)
        )
    }

    private static func audioBlock(
        bytes: Data,
        contentType: UTType
    ) -> BedrockRuntimeClientTypes.AudioBlock? {

        guard let audioFormat = contentType.audioFormat,
            !audioFormat.isUnknown
        else { return nil }

        return .init(
            format: audioFormat,
            source: .bytes(bytes)
        )
    }

}

nonisolated extension BedrockRuntimeClientTypes.ContentBlock {
    var isCachePoint: Bool {
        if case .cachepoint(_) = self {
            return true
        }
        return false
    }
}

nonisolated extension String {
    public static let enableDocumentCitationKey = "enableCitation"
    public static let documentNameKey = "name"
}


nonisolated package struct ToolNameMap {
    let original: String
    let bedrock: String
}

@Generable()
public struct DocumentCitation {

    @Generable()
    public enum CitationLocation: Sendable {
        /// The web URL that was cited for this reference.
        case web(domain: String?, url: String?)
        /// The character-level location within the document where the cited content is found.
        case documentchar(
            /// The index of the document within the array of documents provided in the request.
            documentIndex: Int?,
            /// The ending character position of the cited content within the document.
            end: Int?,
            /// The starting character position of the cited content within the document.
            start: Int?
        )
        /// The page-level location within the document where the cited content is found.
        case documentpage(
            /// The index of the document within the array of documents provided in the request.
            documentIndex: Int?,
            /// The ending page number of the cited content within the document.
            end: Int?,
            /// The starting page number of the cited content within the document.
            start: Int?
        )
        /// The chunk-level location within the document where the cited content is found, typically used for documents that have been segmented into logical chunks.
        case documentchunk(
            /// The index of the document within the array of documents provided in the request.
            documentIndex: Int?,
            /// The ending chunk identifier or index of the cited content within the document.
            end: Int?,
            /// The starting chunk identifier or index of the cited content within the document.
            start: Int?

        )
        /// The search result location where the cited content is found, including the search result index and block positions within the content array.
        case searchresultlocation(
            /// The ending position in the content array where the cited content ends.
            end: Int?,
            /// The index of the search result content block where the cited content is found.
            searchResultIndex: Int?,
            /// The starting position in the content array where the cited content begins.
            start: Int?

        )
        case sdkUnknown(String)

        init?(_ location: BedrockRuntimeClientTypes.CitationLocation?) {
            guard let location else {
                return nil
            }
            switch location {
            case .web(let webLocation):
                self = .web(domain: webLocation.domain, url: webLocation.url)
            case .documentchar(let documentCharLocation):
                self = .documentchar(
                    documentIndex: documentCharLocation.start,
                    end: documentCharLocation.end,
                    start: documentCharLocation.start
                )
            case .documentpage(let documentPageLocation):
                self = .documentpage(
                    documentIndex: documentPageLocation.start,
                    end: documentPageLocation.end,
                    start: documentPageLocation.start
                )

            case .documentchunk(let documentChunkLocation):
                self = .documentchunk(
                    documentIndex: documentChunkLocation.start,
                    end: documentChunkLocation.end,
                    start: documentChunkLocation.start
                )
            case .searchresultlocation(let searchResultLocation):
                self = .searchresultlocation(
                    end: searchResultLocation.end,
                    searchResultIndex: searchResultLocation.searchResultIndex,
                    start: searchResultLocation.start
                )
            case .sdkUnknown(let string):
                self = .sdkUnknown(string)
            }
        }
    }

    /// The precise location within the source document where the cited content can be found,
    ///  including character positions, page numbers, or chunk identifiers.
    public var location: CitationLocation?
    /// The source from the original search result that provided the cited content.
    public var source: String?
    /// The specific content from the source document that was referenced or cited in the generated response.
    public var sourceContent: [String]?
    /// The title or identifier of the source document being cited.
    public var title: String?

    init(_ citation: BedrockRuntimeClientTypes.Citation) {
        self.location = .init(citation.location)
        self.source = citation.source
        self.sourceContent = (citation.sourceContent ?? []).compactMap {
            content in
            switch content {
            case .sdkUnknown(_): nil
            case .text(let text): text
            }
        }
        self.title = citation.title
    }
}

@Generable()
public struct SegmentMetadata {
    public var citations: [DocumentCitation]?
}

// LanguageModelExecutorGenerationRequest.metadata contains the newest prompt.metadata,
// aka: the metadata of the last respond/streamResponse call
public enum RequestMetadataKey: String {
    /// true: ConverseStream. false: Converse
    /// ex: metadata: [RequestMetadataKey.stream.rawValue: false]
    case stream
    /// A list of stop sequences String. A stop sequence is a sequence of characters that causes the model to stop generating the response.
    /// ex: metadata: [RequestMetadataKey.stopSequences.rawValue: ["END"]]
    case stopSequences

    /// https://docs.aws.amazon.com/nova/latest/userguide/extended-thinking.html
    // case extendedThinking
}

/// The effort level for the model to use when generating a response.
/// Higher effort levels allow the model to spend more time reasoning before responding.
/// Supported values are low, medium, high, xhigh, and max.
/// When [extended thinking](https://docs.aws.amazon.com/nova/latest/userguide/extended-thinking.html) is disabled, the effort level is capped at high.
/// Use effort high or below, or enable thinking to use higher effort levels.
nonisolated enum OutputEffort: String {
    case low
    case medium
    case high
    case xhigh
    case max
}

nonisolated extension ContextOptions.ReasoningLevel {
    var outputEffort: OutputEffort? {
        switch self {
        case .light:
            .low
        case .moderate:
            .medium
        case .deep:
            .high
        case .custom(let string):
            OutputEffort(rawValue: string)
        @unknown default:
            nil
        }
    }
}
