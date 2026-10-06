//
//  BedrockTypes+Extensions.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime

nonisolated extension BedrockRuntimeClientTypes.AudioFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }
}

nonisolated extension BedrockRuntimeClientTypes.VideoFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }
}

nonisolated extension BedrockRuntimeClientTypes.DocumentFormat {
    var isUnknown: Bool {
        if case .sdkUnknown(_) = self {
            return true
        }
        return false
    }
}
