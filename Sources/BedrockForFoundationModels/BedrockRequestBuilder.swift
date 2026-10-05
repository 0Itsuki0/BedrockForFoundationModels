//
//  BedrockRequestBuilder.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//

import AWSBedrockRuntime
import CoreImage
import FoundationModels
//extension Document: ExpressibleByDictionaryLiteral {
//
//    public init(dictionaryLiteral elements: (String, Document)...) {
//        let value = elements.reduce([String: Document]()) { acc, curr in
//            var newValue = acc
//            newValue[curr.0] = curr.1
//            return newValue
//        }
//        self.init(StringMapDocument(value: value))
//    }
//}
//import Smithy
@_spi(SmithyDocumentImpl) import Smithy
import SmithyIdentity
import SmithyJSON
import UniformTypeIdentifiers

nonisolated enum BedrockRequestBuilder {

    enum Error: LocalizedError {
        case unsupportedDataAttachmentType
        // Error when converting smithy document to JSON
        case decodingDocument(String)
    }
    //    ConverseInput
    //    additionalModelRequestFields: Smithy.Document? = nil,
    //    additionalModelResponseFieldPaths: [Swift.String]? = nil,
    //    guardrailConfig: BedrockRuntimeClientTypes.GuardrailConfiguration? = nil,
    //    inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration? = nil,
    //    messages: [BedrockRuntimeClientTypes.Message]? = nil,
    //    modelId: Swift.String? = nil,
    //    outputConfig: BedrockRuntimeClientTypes.OutputConfig? = nil,
    //    performanceConfig: BedrockRuntimeClientTypes.PerformanceConfiguration? = nil,
    //    promptVariables: [Swift.String: BedrockRuntimeClientTypes.PromptVariableValues]? = nil,
    //    requestMetadata: [Swift.String: Swift.String]? = nil,
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

    static func sanitizedJsonSchema(from schema: GenerationSchema) throws
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

    static func buildOutputConfig(
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

    static func buildConverseInput(
        from request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel
    ) throws -> (ConverseInput, [ToolNameMap]) {
        /// Strict JSON Schema via constrained decoding (`output_config.format`) —
        /// the model cannot emit a token that violates the schema. Compatible with
        /// thinking; the response streams as plain text deltas containing valid
        /// JSON. Nothing is added to `system`. The API shows the model the schema
        /// itself whenever a format is set. And `system` has to stay the same
        /// across a session's requests: the API can reject a replayed thinking
        /// block once the conversation before it has changed, and the system prompt
        /// is part of that conversation. `includeSchemaInPrompt` is moot for the
        /// same reason: the schema always reaches the model.
        //        request.contextOptions.includeSchemaInPrompt
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
            callingMode: request.generationOptions.toolCallingMode
        ) {
            input.toolConfig = config.0
            toolNameMap = config.1
        }

        input.modelId = model.executorConfiguration.modelId

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
                //                closeTurn()
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
        callingMode: GenerationOptions.ToolCallingMode?
    ) throws -> (BedrockRuntimeClientTypes.ToolConfiguration, [ToolNameMap])? {
        guard !tools.isEmpty, callingMode != .disallowed else {
            return nil
        }
        let tools = try tools.map({
            try tool(from: $0)
        })
        let choice = toolChoice(for: callingMode)
        return (
            BedrockRuntimeClientTypes.ToolConfiguration(
                toolChoice: choice,
                tools: tools.map(\.0)
            ), tools.map(\.1)
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

    //        public enum SystemContentBlock: Swift.Sendable {
    //            /// A system prompt for the model.
    //            case text(Swift.String)
    //            /// A content block to assess with the guardrail. Use with the [Converse](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html) or [ConverseStream](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html) API operations. For more information, see Use a guardrail with the Converse API in the Amazon Bedrock User Guide.
    //            case guardcontent(BedrockRuntimeClientTypes.GuardrailConverseContentBlock)
    //            /// CachePoint to include in the system prompt.
    //            case cachepoint(BedrockRuntimeClientTypes.CachePointBlock)
    //            case sdkUnknown(Swift.String)
    //        }

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
//
//extension GeneratedContent {
//    enum Error: LocalizedError, Sendable {
//        /// The bytes weren't a decodable image.
//        //        case undecodable
//        /// `ImageIO` could not write the re-encoded image.
//        case encodingFailed
//        /// Still over ``maxByteCount`` after re-encoding at the lowest quality.
//        //        case tooLarge(byteCount: Int)
//
//        var errorDescription: String? {
//            switch self {
//            //            case .undecodable:
//            //                "The data could not be decoded as an image."
//            case .encodingFailed:
//                "The generated content cannot be converted to structure accept by bedrock API."
//            //            case .tooLarge(let byteCount):
//            //                "The image is \(byteCount) bytes after compression, over the "
//            //                + "\(ClaudeImage.maxByteCount)-byte limit."
//            }
//        }
//    }
//
//    var smithyDocument: Smithy.Document {
//        get throws {
//            switch self.kind {
//            case .null:
//                return .init(nilLiteral: ())
//            case .bool(let value):
//                return .init(booleanLiteral: value)
//            case .number(let value):
//                return .init(floatLiteral: Float(value))
//            case .string(let value):
//                return .init(stringLiteral: value)
//            case .array(let value):
//                return .init(
//                    ListDocument(
//                        value: try value.map({ try $0.smithyDocument })
//                    )
//                )
//            case .structure(let value, _):
//                return .init(
//                    StringMapDocument(
//                        value: try value.mapValues({ try $0.smithyDocument })
//                    )
//                )
//            @unknown default:
//                throw Error.encodingFailed
//            }
//        }
//    }
//}

nonisolated extension String {
    public static let enableDocumentCitationKey = "enableCitation"
    public static let documentNameKey = "name"
}

//extension Transcript.Segment {
//    private var contentBlock: BedrockRuntimeClientTypes.ContentBlock? {
//        switch self {
//        case .text(let text):
//            return .text(text.content)
//        case .structure(let structured):
//            return .text(structured.content.jsonString)
//        case .attachment(let attachment):
//            switch attachment.content {
//
//            case .image(let image):
//                return .image(.init())
//            case .data(_):
//                <#code#>
//            @unknown default:
//                <#fatalError()#>
//            }
//        @unknown default:
//            print("Unknown segment type: \(self)")
//            return nil
//        }
//    }
//}

extension Transcript.DataAttachment {
    private var contentBlock: BedrockRuntimeClientTypes.ContentBlock? {
        get throws {

            // DocumentBlock
            if let documentFormat = self.contentType.documentFormat,
                !documentFormat.isUnknown
            {
                return .document(.init(citations: .init(enabled: true)))
            }

            // VideoBlock

            // Audio Block
            /// A document to include in the message.
            //        case document(BedrockRuntimeClientTypes.DocumentBlock)
            //            /// Video to include in the message.
            //        case video(BedrockRuntimeClientTypes.VideoBlock)
            //            /// An audio content block containing audio data in the conversation.
            //        case audio(BedrockRuntimeClientTypes.AudioBlock)

            //            let oriented = self.ciImage.oriented(orientation)
            //            let source: BedrockRuntimeClientTypes.ImageSource = .bytes(
            //                try oriented.jpegData
            //            )
            //            return .image(.init(format: .jpeg, source: source))

            return nil
        }
    }
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

extension Transcript.ImageAttachment {
    private var contentBlock: BedrockRuntimeClientTypes.ContentBlock {
        get throws {
            let oriented = self.ciImage.oriented(orientation)
            let source: BedrockRuntimeClientTypes.ImageSource = .bytes(
                try oriented.jpegData
            )
            return .image(.init(format: .jpeg, source: source))
        }
    }
}

nonisolated
    extension CIImage
{
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
