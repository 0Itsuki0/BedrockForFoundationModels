//
//  UTType+Extensions.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import UniformTypeIdentifiers

// MARK: - Public Identifiers for documents/images
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

}

// MARK: - conversions between UTType and bedrock type
nonisolated extension UTType {
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
}
