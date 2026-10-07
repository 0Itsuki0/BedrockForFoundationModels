//
//  CIImage+Extensions.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import CoreImage

// MARK: - converting CIImage to Jpeg data
nonisolated extension CIImage {
    enum Error: LocalizedError, Sendable {
        case encoding

        var errorDescription: String? {
            switch self {
            case .encoding:
                "Error encoding image to data."
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
                throw Error.encoding
            }

            return jpegData
        }
    }
}
