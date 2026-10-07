//
//  SegmentMetadata.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import FoundationModels

@Generable()
public struct SegmentMetadata {
    public var citations: [CitationContent] = []
}

extension SegmentMetadata {
    var isEmpty: Bool {
        return citations.isEmpty
    }
}
