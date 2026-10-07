//
//  DocumentCitation.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import FoundationModels

nonisolated extension String {
    public static let enableDocumentCitationKey = "enableCitation"
    public static let documentNameKey = "name"
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
public struct CitationContent {
    public let citations: [DocumentCitation]
    /// The generated content that is supported by the associated citations.
    /// NOTE:  Citations deltas obtained from streaming that ground already-streamed text carry no content of their own.
    public let content: String
}
