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

// MARK: - Converse / Converse Stream Input Request Builder Shared
nonisolated enum BedrockRequestBuilder {

    enum Error: LocalizedError, Sendable {
        case unsupportedDataAttachmentType(UTType)
        
        var errorDescription: String? {
            switch self {
            case .unsupportedDataAttachmentType(let type):
                "\(type) is not supported. Please try a different format."
            }
        }
    }

    static func buildConverseInputCommon(
        from request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel
    ) throws -> (ConverseInputCommon, [ToolNameMap]) {
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

        var input = ConverseInputCommon()

        let inferenceConfig = buildInferenceConfig(
            from: request,
            stopSequences: executorConfiguration.stopSequences
        )
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

        input.additionalModelResponseFieldPaths =
            executorConfiguration.additionalResponseFieldPaths

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

        input.performanceConfig = .init(
            latency: executorConfiguration.performance
        )

        let (system, messages, isToolOutputTurn) = try buildMessages(
            from: request.transcript,
            cacheConfig: cacheConfig,
            toolNameMap: toolNameMap
        )

        input.messages = messages

        if !system.isEmpty {
            input.system = system
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

    private static func buildMessages(
        from transcript: Transcript,
        cacheConfig: BedrockModelConfiguration.CacheConfiguration?,
        toolNameMap: [ToolNameMap]
    ) throws -> (
        system: [BedrockRuntimeClientTypes.SystemContentBlock],
        messages: [BedrockRuntimeClientTypes.Message],
        isToolOutputTurn: Bool
    ) {
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

        for (index, entry) in transcript.enumerated() {
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
                if index == transcript.count - 1 {
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

        messages = groupMessagesByRole(messages: messages)
        messages = addMessageCache(
            messages: messages,
            cacheConfig: cacheConfig?.messagesTTL
        )

        if !system.isEmpty,
            let cachePoint = buildCachePoint(
                ttl: cacheConfig?.systemPromptTTL
            )
        {
            system.append(
                .cachepoint(cachePoint)
            )
        }

        return (system, messages, isToolOutputTurn)
    }

    // TODO: - check image/document size
    private static func checkAttachmentSize() {

    }

    private static func buildInferenceConfig(
        from request: LanguageModelExecutorGenerationRequest,
        stopSequences: [String]?
    ) -> (
        config: BedrockRuntimeClientTypes.InferenceConfiguration,
        // map to be add to ConverseInput.additionalModelRequestFields
        additionalInferenceConfig: [String: SmithyDocument]?
    ) {
        var configuration = BedrockRuntimeClientTypes.InferenceConfiguration()
        var additionalInferenceConfig: [String: SmithyDocument] = [:]

        configuration.stopSequences = stopSequences

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
        case .randomTopK(let k, _):
            /// Top k passed in with additionalModelRequestFields:
            /// https://docs.aws.amazon.com/nova/latest/userguide/using-converse-api.html
            /// additionalModelRequestFields = { "inferenceConfig": { "topK": 20 }}
            ///
            /// the API has no sampling-seed parameter
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
            OutputEffort.fromReasoningLevel(
                request.contextOptions.reasoningLevel
            )?.rawValue

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

        throw Error.unsupportedDataAttachmentType(dataAttachment.contentType)
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

        throw Error.unsupportedDataAttachmentType(dataAttachment.contentType)
    }

    private static func documentBlock(
        bytes: Data,
        contentType: UTType,
        metadata: GeneratedContent,
        label: String?
    ) -> BedrockRuntimeClientTypes.DocumentBlock? {
        guard
            let documentFormat = BedrockRuntimeClientTypes.DocumentFormat
                .fromUTType(contentType), !documentFormat.isUnknown
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
        let source: BedrockRuntimeClientTypes.DocumentSource =
            if documentFormat.isTextDocument {
                if let string = String(data: bytes, encoding: .utf8) {
                    .text(string)
                } else {
                    .bytes(bytes)
                }
            } else {
                .bytes(bytes)
            }
        return .init(
            citations: .init(enabled: enableCitation ?? false),
            context: metadata.jsonString,
            format: documentFormat,
            name: name,
            source: source
        )
    }

    private static func videoBlock(
        bytes: Data,
        contentType: UTType
    ) -> BedrockRuntimeClientTypes.VideoBlock? {

        guard
            let videoFormat = BedrockRuntimeClientTypes.VideoFormat
                .fromUTType(contentType), !videoFormat.isUnknown
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

        guard
            let audioFormat = BedrockRuntimeClientTypes.AudioFormat
                .fromUTType(contentType), !audioFormat.isUnknown
        else { return nil }

        return .init(
            format: audioFormat,
            source: .bytes(bytes)
        )
    }
}
