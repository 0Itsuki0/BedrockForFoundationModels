//
//  DocumentCitation.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import FoundationModels

// MARK: - Data attachment metadata keys for documents
nonisolated extension String {
    /// Metadata key (`Bool`) to enable citations for a document attachment. Defaults to `false`.
    ///
    /// - SeeAlso: [CitationsConfig](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CitationsConfig.html)
    public static let enableDocumentCitationKey = "enableCitation"
    /// Metadata key (`String`) for the name of a document attachment. Ignored if the attachment has a label.
    ///
    /// - SeeAlso: [DocumentBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_DocumentBlock.html)
    public static let documentNameKey = "name"
}

/// A citation that references source documents used to generate the response.
///
/// - SeeAlso: [Citation](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Citation.html)
@Generable()
public struct DocumentCitation {

    /// The location of the cited content within a source.
    ///
    /// - SeeAlso: [CitationLocation](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CitationLocation.html)
    @Generable()
    public enum CitationLocation: Sendable {
        /// The web URL that was cited for this reference.
        case web(
            /// The domain that was cited.
            domain: String?,
            /// The URL that was cited.
            url: String?
        )
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
        /// A location type not known to this SDK version.
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
                    documentIndex: documentCharLocation.documentIndex,
                    end: documentCharLocation.end,
                    start: documentCharLocation.start
                )
            case .documentpage(let documentPageLocation):
                self = .documentpage(
                    documentIndex: documentPageLocation.documentIndex,
                    end: documentPageLocation.end,
                    start: documentPageLocation.start
                )

            case .documentchunk(let documentChunkLocation):
                self = .documentchunk(
                    documentIndex: documentChunkLocation.documentIndex,
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
    /// including character positions, page numbers, or chunk identifiers.
    public let location: CitationLocation?
    /// The source from the original search result that provided the cited content.
    public let source: String?
    /// The specific content from the source document that was referenced or cited in the generated response.
    public let sourceContent: [String]?
    /// The title or identifier of the source document being cited.
    public let title: String?

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

/// Generated content and the citations that support it.
///
/// - SeeAlso: [CitationsContentBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_CitationsContentBlock.html)
@Generable()
public struct CitationContent {
    /// The citations that support the content.
    public let citations: [DocumentCitation]
    /// The generated content that is supported by the associated citations.
    ///
    /// - Note: Citations deltas obtained from streaming that ground already-streamed text carry no content of their own.
    public let content: String
}
