//
//  BedrockTypes+Extensions.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import UniformTypeIdentifiers

nonisolated extension BedrockRuntimeClientTypes.AudioFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }

    static func fromUTType(_ type: UTType?) -> BedrockRuntimeClientTypes
        .AudioFormat?
    {
        return switch type {
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

nonisolated extension BedrockRuntimeClientTypes.VideoFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }

    static func fromUTType(_ type: UTType?) -> BedrockRuntimeClientTypes
        .VideoFormat?
    {
        return switch type {
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

nonisolated extension BedrockRuntimeClientTypes.DocumentFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }

    static func fromUTType(_ type: UTType?) -> BedrockRuntimeClientTypes
        .DocumentFormat?
    {
        return switch type {
        case .commaSeparatedText: .csv
        case .doc: .doc
        case .docx: .docx
        case .html: .html
        case .markdown: .md
        case .pdf: .pdf
        case .xls: .xls
        case .xlsx: .xlsx
        case .plainText, .utf8PlainText, .utf16PlainText, .text: .txt
        default: nil
        }
    }

    var isTextDocument: Bool {
        switch self {
        case .md, .txt, .html: true
        default: false
        }
    }

}
