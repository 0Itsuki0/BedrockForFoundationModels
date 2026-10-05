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

//struct Person: ConvertibleToGeneratedContent {
//    var name: String
//    var age: Int
//
//
//    var generatedContent: GeneratedContent {
//        GeneratedContent(properties: [
//            "firstName": name,
//            "ageInYears": age
//        ])
//    }
//}
/// The precise location within the source document where the cited content can be found, including character positions, page numbers, or chunk identifiers.
//public var location: BedrockRuntimeClientTypes.CitationLocation?
///// The source from the original search result that provided the cited content.
//public var source: Swift.String?
///// The specific content from the source document that was referenced or cited in the generated response.
//public var sourceContent: [BedrockRuntimeClientTypes.CitationSourceContent]?
///// The title or identifier of the source document being cited.
//public var title: Swift.String?

nonisolated struct ToolNameMap {
    let original: String
    let bedrock: String
}

@Generable()
struct DocumentCitation {
    
    @Generable()
    public enum CitationLocation: Swift.Sendable {
        /// The web URL that was cited for this reference.
        case web(domain: String?, url: String?)
        /// The character-level location within the document where the cited content is found.
        case documentchar(
            /// The index of the document within the array of documents provided in the request.
            documentIndex: Swift.Int?,
            /// The ending character position of the cited content within the document.
            end: Swift.Int?,
            /// The starting character position of the cited content within the document.
            start: Swift.Int?
        )
        /// The page-level location within the document where the cited content is found.
        case documentpage(
            /// The index of the document within the array of documents provided in the request.
            documentIndex: Swift.Int?,
            /// The ending page number of the cited content within the document.
            end: Swift.Int?,
            /// The starting page number of the cited content within the document.
            start: Swift.Int?
        )
        /// The chunk-level location within the document where the cited content is found, typically used for documents that have been segmented into logical chunks.
        case documentchunk(
            /// The index of the document within the array of documents provided in the request.
            documentIndex: Swift.Int?,
            /// The ending chunk identifier or index of the cited content within the document.
            end: Swift.Int?,
            /// The starting chunk identifier or index of the cited content within the document.
            start: Swift.Int?
            
        )
        /// The search result location where the cited content is found, including the search result index and block positions within the content array.
        case searchresultlocation(
            /// The ending position in the content array where the cited content ends.
            end: Swift.Int?,
            /// The index of the search result content block where the cited content is found.
            searchResultIndex: Swift.Int?,
            /// The starting position in the content array where the cited content begins.
            start: Swift.Int?
            
        )
        case sdkUnknown(Swift.String)
        
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
    public var source: Swift.String?
    /// The specific content from the source document that was referenced or cited in the generated response.
    public var sourceContent: [String]?
    /// The title or identifier of the source document being cited.
    public var title: Swift.String?
    
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
struct SegmentMetadata {
    var citations: [DocumentCitation]?
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

nonisolated extension BedrockRuntimeClientTypes.S3Location {
    private var url: URL? {
        guard let uri else { return nil }
        return URL(string: uri)
    }
    private var urlComponents: URLComponents? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)
    }
    
    var bucket: String? {
        guard let urlComponents else { return nil }
        return urlComponents.host
    }
    var key: String? {
        guard let urlComponents else { return nil }
        return String(urlComponents.path.dropFirst())
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


public struct BedrockLanguageModel: LanguageModel {
    public let executorConfiguration: BedrockExecutor.Configuration
    
    public init(
        modelId: String,
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String?
    ) {
        self.executorConfiguration = .init(
            modelId: modelId,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken
        )
    }
    
    public typealias Executor = BedrockExecutor
    
    public var capabilities: LanguageModelCapabilities {
        let modelId = executorConfiguration.modelId
        let baseCapabilities: [LanguageModelCapabilities.Capability] = [
            .toolCalling, .guidedGeneration, .reasoning,
        ]
        if modelId == "multi-modal" {
            return LanguageModelCapabilities(baseCapabilities + [.vision])
        } else {
            return LanguageModelCapabilities(baseCapabilities)
        }
    }
    
}

public nonisolated struct BedrockModelConfiguration: Hashable, Sendable {
    public let modelId: String
    
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    
    public init(
        modelId: String,
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String?
    ) {
        self.modelId = modelId
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
    
}

public struct BedrockExecutor: LanguageModelExecutor {
    public typealias Configuration = BedrockModelConfiguration
    
    public init(configuration: Configuration) throws {
        
    }
    
    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let config = model.executorConfiguration
        
        let (converseInput, toolNameMap) = try BedrockRequestBuilder.buildConverseInput(
            from: request,
            model: model
        )
        for (index, message) in (converseInput.messages ?? []).enumerated() {
            print("--index \(index)--")
            print(message.role as Any)
            print(message.content as Any)
        }
        
        let credentialResolver = StaticAWSCredentialIdentityResolver(
            AWSCredentialIdentity(
                accessKey: config.accessKeyId,
                secret: config.secretAccessKey,
                sessionToken: config.sessionToken,
            )
        )
        
        // Create a Bedrock Runtime client in the AWS Region you want to use.
        let runtimeConfig =
        try await BedrockRuntimeClient.BedrockRuntimeClientConfig(
            awsCredentialIdentityResolver: credentialResolver
        )
        let client = BedrockRuntimeClient(config: runtimeConfig)
        let response = try await client.converse(input: converseInput)
        //        if let guardrail = response.trace.
        //        response.trace?.guardrail
        //    case contentFiltered
        //    case endTurn
        //    case guardrailIntervened
        //    case malformedModelOutput
        //    case malformedToolUse
        //    case maxTokens
        //    case modelContextWindowExceeded
        //    case stopSequence
        //    case toolUse
        //        channel.send(.toolCalls(entryID: /**/, action: ))
        try await BedrockResponseHandler.handleConverseOutput(
            response: response,
            streamingInto: channel,
            toolNameMap: toolNameMap
        )
    }
    
    public typealias Model = BedrockLanguageModel
}

