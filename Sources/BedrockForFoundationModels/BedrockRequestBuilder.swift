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

    enum Error: LocalizedError {
        case unsupportedDataAttachmentType
    }
    //    ConverseInput
    //    additionalModelRequestFields: Smithy.Document? = nil,
    //    additionalModelResponseFieldPaths: [String]? = nil,
    //    guardrailConfig: BedrockRuntimeClientTypes.GuardrailConfiguration? = nil,
    //    inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration? = nil,
    //    messages: [BedrockRuntimeClientTypes.Message]? = nil,
    //    modelId: String? = nil,
    //    outputConfig: BedrockRuntimeClientTypes.OutputConfig? = nil,
    //    performanceConfig: BedrockRuntimeClientTypes.PerformanceConfiguration? = nil,
    //    promptVariables: [String: BedrockRuntimeClientTypes.PromptVariableValues]? = nil,
    //    requestMetadata: [String: String]? = nil,
    //    serviceTier: BedrockRuntimeClientTypes.ServiceTier? = nil,
    //    system: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil,
    //    toolConfig: BedrockRuntimeClientTypes.ToolConfiguration? = nil

    //    public var additionalModelRequestFields: Smithy.Document?

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

    //    private enum ToolResultType: String {
    //        case textBlock
    //        case imageBlock
    //        case videoBlock
    //        case documentBlock
    //        case jsonBlock
    //    }

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

nonisolated extension BedrockRuntimeClientTypes.AudioFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }
}

nonisolated extension BedrockRuntimeClientTypes.VideoFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }
}

nonisolated extension BedrockRuntimeClientTypes.DocumentFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }
}

nonisolated extension UTType {
    public static let doc = UTType(
        identifier: "com.microsoft.word.doc",
        allowUndeclared: true
    )
    public static let docx = UTType(
        identifier: "org.openxmlformats.wordprocessingml.document",
        allowUndeclared: true
    )
    public static let xls = UTType(
        identifier: "com.microsoft.excel.xls",
        allowUndeclared: true
    )
    public static let xlsx = UTType(
        identifier: "org.openxmlformats.spreadsheetml.sheet",
        allowUndeclared: true
    )

    var documentFormat: BedrockRuntimeClientTypes.DocumentFormat? {
        return switch self as UTType? {
        case .commaSeparatedText: .csv
        case .doc: .doc
        case .docx: .docx
        case .html: .html
        case .markdown: .md
        case .pdf: .pdf
        case .plainText: .txt
        case .xls: .xls
        case .xlsx: .xlsx
        default: nil
        }
    }

    public static let flv = UTType(
        identifier: "com.macromedia.flash-video",
        allowUndeclared: true
    )
    public static let mkv = UTType(
        identifier: "org.matroska.mkv",
        allowUndeclared: true
    )
    public static let threeGp = UTType(
        identifier: "public.3gpp",
        allowUndeclared: true
    )
    public static let webm = UTType(
        identifier: "org.webmproject.webm",
        allowUndeclared: true
    )
    public static let wmv = UTType(
        identifier: "com.microsoft.windows-media-wmv",
        allowUndeclared: true
    )
    public static let mpg = UTType(
        filenameExtension: "mpg",
        conformingTo: .mpeg
    )

    var videoFormat: BedrockRuntimeClientTypes.VideoFormat? {
        return switch self as UTType? {
        case .flv: .flv
        case .mkv: .mkv
        case .quickTimeMovie: .mov
        case .mpeg: .mpeg
        case .mpg: .mpg
        case .threeGp: .threeGp
        case .webm: .webm
        case .wmv: .wmv
        default: nil
        }
    }

    public static let aac = UTType(
        identifier: "public.aac-audio",
        allowUndeclared: true
    )
    public static let flac = UTType(
        identifier: "org.xiph.flac",
        allowUndeclared: true
    )
    public static let mka = UTType(
        identifier: "org.matroska.mka",
        allowUndeclared: true
    )
    public static let ogg = UTType(
        identifier: "org.xiph.ogg-audio",
        allowUndeclared: true
    )
    public static let opus = UTType(
        identifier: "org.xiph.opus",
        allowUndeclared: true
    )
    public static let pcm = UTType(
        filenameExtension: "pcm",
        conformingTo: .data
    )
    public static let xAac = UTType(
        filenameExtension: "xaac",
        conformingTo: aac ?? .audio
    )

    var audioFormat: BedrockRuntimeClientTypes.AudioFormat? {
        return switch self as UTType? {
        case .aac: .aac
        case .flac: .flac
        case .mpeg4Audio: .m4a
        case .mka: .mka
        case .mkv: .mkv
        case .mp3: .mp3
        case .mpeg4Movie: .mp4
        case .mpeg: .mpeg
        case .mp3: .mpga
        case .ogg: .ogg
        case .opus: .opus
        case .pcm: .pcm
        case .wav: .wav
        case .webm: .webm
        case .xAac: .xAac
        default: nil
        }
    }
}

nonisolated extension CIImage {
    enum Error: LocalizedError, Sendable {
        /// The bytes weren't a decodable image.
        //        case undecodable
        /// `ImageIO` could not write the re-encoded image.
        case encodingFailed
        /// Still over ``maxByteCount`` after re-encoding at the lowest quality.
        //        case tooLarge(byteCount: Int)

        var errorDescription: String? {
            switch self {
            //            case .undecodable:
            //                "The data could not be decoded as an image."
            case .encodingFailed:
                "The image could not be re-encoded for upload."
            //            case .tooLarge(let byteCount):
            //                "The image is \(byteCount) bytes after compression, over the "
            //                + "\(ClaudeImage.maxByteCount)-byte limit."
            }
        }
    }

    var jpegData: Data {
        get throws {
            let context = CIContext()
            let colorSpace =
                self.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let jpegData = context.jpegRepresentation(
                of: self,
                colorSpace: colorSpace,
                options: [
                    .init(
                        rawValue: kCGImageDestinationLossyCompressionQuality
                            as String
                    ): 1.0
                ]
            )
            guard let jpegData else {
                throw Error.encodingFailed
            }

            return jpegData
        }
    }
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

nonisolated extension CGImage {
    enum Error: LocalizedError {
        case encodingFailed
    }
    static func fromData(_ data: Data) throws -> CGImage {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            throw Error.encodingFailed
        }
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw Error.encodingFailed
        }
        return image
    }
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
