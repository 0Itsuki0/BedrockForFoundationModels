//
//  AttachmentUTType.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import AWSBedrockRuntime
import UniformTypeIdentifiers

// MARK: - Uniform types for Bedrock supported formats not declared by UniformTypeIdentifiers
nonisolated extension UTType {
    /// Microsoft Word 97-2003 document (`.doc`).
    public static let doc = UTType(
        identifier: "com.microsoft.word.doc",
        allowUndeclared: true
    )
    /// Microsoft Word document (`.docx`).
    public static let docx = UTType(
        identifier: "org.openxmlformats.wordprocessingml.document",
        allowUndeclared: true
    )
    /// Microsoft Excel 97-2003 spreadsheet (`.xls`).
    public static let xls = UTType(
        identifier: "com.microsoft.excel.xls",
        allowUndeclared: true
    )
    /// Microsoft Excel spreadsheet (`.xlsx`).
    public static let xlsx = UTType(
        identifier: "org.openxmlformats.spreadsheetml.sheet",
        allowUndeclared: true
    )

    /// Flash video (`.flv`).
    public static let flv = UTType(
        identifier: "com.macromedia.flash-video",
        allowUndeclared: true
    )
    /// Matroska video (`.mkv`).
    public static let mkv = UTType(
        identifier: "org.matroska.mkv",
        allowUndeclared: true
    )
    /// 3GPP video (`.3gp`).
    public static let threeGp = UTType(
        identifier: "public.3gpp",
        allowUndeclared: true
    )
    /// WebM video (`.webm`).
    public static let webm = UTType(
        identifier: "org.webmproject.webm",
        allowUndeclared: true
    )
    /// Windows Media video (`.wmv`).
    public static let wmv = UTType(
        identifier: "com.microsoft.windows-media-wmv",
        allowUndeclared: true
    )
    /// MPEG video (`.mpg`).
    public static let mpg = UTType(
        filenameExtension: "mpg",
        conformingTo: .mpeg
    )

    /// AAC audio (`.aac`).
    public static let aac = UTType(
        identifier: "public.aac-audio",
        allowUndeclared: true
    )
    /// FLAC audio (`.flac`).
    public static let flac = UTType(
        identifier: "org.xiph.flac",
        allowUndeclared: true
    )
    /// Matroska audio (`.mka`).
    public static let mka = UTType(
        identifier: "org.matroska.mka",
        allowUndeclared: true
    )
    /// Ogg audio (`.ogg`).
    public static let ogg = UTType(
        identifier: "org.xiph.ogg-audio",
        allowUndeclared: true
    )
    /// Opus audio (`.opus`).
    public static let opus = UTType(
        identifier: "org.xiph.opus",
        allowUndeclared: true
    )
    /// Raw PCM audio (`.pcm`).
    public static let pcm = UTType(
        filenameExtension: "pcm",
        conformingTo: .data
    )
    /// Extended HE-AAC audio (`.xaac`).
    public static let xAac = UTType(
        filenameExtension: "xaac",
        conformingTo: aac ?? .audio
    )
}

extension BedrockRuntimeClientTypes.DocumentFormat {
    /// The uniform type corresponding to this format, or `nil` if the format is unknown.
    ///
    /// - SeeAlso: [DocumentBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_DocumentBlock.html)
    public var utType: UTType? {
        return switch self {
        case .csv: .commaSeparatedText
        case .doc: .doc
        case .docx: .docx
        case .html: .html
        case .md: .markdown
        case .pdf: .pdf
        case .xls: .xls
        case .xlsx: .xlsx
        case .txt: .plainText
        default: nil
        }
    }
}

extension BedrockRuntimeClientTypes.AudioFormat {
    /// The uniform type corresponding to this format, or `nil` if the format is unknown.
    ///
    /// - SeeAlso: [AudioBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_AudioBlock.html)
    public var utType: UTType? {
        return switch self {
        case .aac: .aac
        case .flac: .flac
        case .m4a: .mpeg4Audio
        case .mka: .mka
        case .mkv: .mkv
        case .mp3: .mp3
        case .mp4: .mpeg4Movie
        case .mpeg: .mpeg
        case .mpga: .mp3
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

extension BedrockRuntimeClientTypes.VideoFormat {
    /// The uniform type corresponding to this format, or `nil` if the format is unknown.
    ///
    /// - SeeAlso: [VideoBlock](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_VideoBlock.html)
    public var utType: UTType? {
        return switch self {
        case .flv: .flv
        case .mkv: .mkv
        case .mov: .quickTimeMovie
        case .mpeg: .mpeg
        case .mpg: .mpg
        case .threeGp: .threeGp
        case .webm: .webm
        case .wmv: .wmv
        default: nil
        }
    }
}
