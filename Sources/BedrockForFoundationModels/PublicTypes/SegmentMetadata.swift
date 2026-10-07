//
//  SegmentMetadata.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import FoundationModels

/// Metadata will be add to the response as [SegmentId: SegmentMetadata]
@Generable()
public struct SegmentMetadata {
    public var citations: [CitationContent] = []
}

extension SegmentMetadata {
    var isEmpty: Bool {
        return citations.isEmpty
    }
}
