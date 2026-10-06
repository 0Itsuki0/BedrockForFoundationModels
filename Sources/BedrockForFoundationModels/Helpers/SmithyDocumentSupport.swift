//
//  SmithyDocumentSupport.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//

import AWSBedrockRuntime
import Foundation
import FoundationModels
@_spi(SmithyDocumentImpl) import Smithy
import SmithyJSON

nonisolated enum SmithyDocumentSupport {
    enum Error: LocalizedError, Sendable {
        // Error when decoding smithy document to Swift Types
        case decoding(String)
        // Error when encoding Swift Types to smithy document
        case encoding(String)
    }
}

// MARK: - SmithyDocument to JSON
nonisolated extension SmithyDocumentSupport {

    private static func baseType(for document: SmithyDocument) throws -> Any {
        func toAny(_ value: Any?) -> Any {
            value ?? NSNull()
        }

        switch document.type {
        case .blob:
            return toAny(try? document.asBlob())
        case .boolean:
            return toAny(try? document.asBoolean())
        case .string:
            return toAny(try? document.asString())
        case .timestamp:
            return toAny(try? document.asTimestamp())
        case .byte:
            return toAny(try? document.asByte())
        case .short:
            return toAny(try? document.asShort())
        case .integer:
            return toAny(try? document.asInteger())
        case .long:
            return toAny(try? document.asLong())
        case .float:
            return toAny(try? document.asFloat())
        case .document:
            return toAny(try baseType(for: document))
        case .double:
            return toAny(try? document.asDouble())
        case .bigDecimal:
            return toAny(try? document.asBigDecimal())
        case .bigInteger:
            return toAny(try? document.asBigInteger())
        case .list, .set:
            let list = (try? document.asList()) ?? []
            let baseTypeArray = try list.map({ try baseType(for: $0) })
            return baseTypeArray as NSArray
        case .map:
            let map = (try? document.asStringMap()) ?? [:]
            let baseTypeDict = try map.mapValues({ try baseType(for: $0) })
            return baseTypeDict as NSDictionary
        case .structure:
            // NullDocument has type `structure` and is the only document that has structure type
            return NSNull()
        default:
            throw Error.decoding(
                "\(document.type) document type is not supported."
            )
        }
    }

    static func jsonData(for document: SmithyDocument) throws -> Data? {
        // NOTE: direct JSONSerialization.data call on SmithyDocument will not work
        // FAULT: NSInvalidArgumentException: Invalid type in JSON write (__SwiftValue); (user info absent)
        return try JSONSerialization.data(
            withJSONObject: baseType(for: document),
            options: [.fragmentsAllowed]
        )
    }

    static func jsonString(for document: SmithyDocument) throws -> String? {
        guard let data = try jsonData(for: document) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

}

// MARK: - GenerationSchema to SmithyDocument
nonisolated extension SmithyDocumentSupport {

    static func document(from schema: GenerationSchema) throws
        -> Smithy.Document
    {
        let data = try JSONEncoder().encode(schema)
        let document = try Smithy.Document.make(from: data)
        return document
    }
}

// MARK: - GeneratedContent to SmithyDocument
nonisolated extension SmithyDocumentSupport {

    static func document(from schema: GeneratedContent)
        -> Smithy.Document?
    {
        switch schema.kind {
        case .null:
            return .init(nilLiteral: ())
        case .bool(let value):
            return .init(booleanLiteral: value)
        case .number(let value):
            return .init(floatLiteral: Float(value))
        case .string(let value):
            return .init(stringLiteral: value)
        case .array(let value):
            return .init(
                ListDocument(
                    value: value.compactMap { document(from: $0) }
                )
            )
        case .structure(let value, _):
            return .init(
                StringMapDocument(
                    value: value.compactMapValues { document(from: $0) }
                )
            )
        @unknown default:
            print(
                "Encountered unknown GeneratedContent schema kind while converting to Smithy Document: \(schema.kind)"
            )
            return nil
        }
    }
}
