//
//  SegmentMetadata.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import FoundationModels

/// Metadata attached to a response segment.
///
/// Metadata will be added to the response as `[SegmentId: SegmentMetadata]`.
@Generable()
public struct SegmentMetadata {
    /// The citations for the segment.
    public var citations: [CitationContent] = []
}

extension SegmentMetadata {
    var isEmpty: Bool {
        return citations.isEmpty
    }
}
