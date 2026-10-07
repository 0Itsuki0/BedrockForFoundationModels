//
//  Request+Converse.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import AWSBedrockRuntime
import Foundation
import FoundationModels

// MARK: - helper for building converse input
nonisolated extension BedrockRequestBuilder {

    static func buildConverseInput(
        from request: LanguageModelExecutorGenerationRequest,
        model: BedrockLanguageModel
    ) throws -> (ConverseInput, [ToolNameMap]) {
        let (inputCommon, toolNameMap) = try buildConverseInputCommon(
            from: request,
            model: model
        )

        return (
            converseInput(
                from: inputCommon,
                guardrailConfig: buildGuardrailConfig(
                    from: model.executorConfiguration
                )
            ), toolNameMap
        )
    }

    private static func buildGuardrailConfig(
        from executorConfiguration: BedrockExecutor.Configuration
    ) -> BedrockRuntimeClientTypes.GuardrailConfiguration? {
        guard let guardrailConfig = executorConfiguration.guardrailConfig else {
            return nil
        }

        return .init(
            guardrailIdentifier: guardrailConfig.guardrailIdentifier,
            guardrailVersion: guardrailConfig.guardrailVersion,
            trace: guardrailConfig.trace
        )
    }

    private static func converseInput(
        from commonInput: ConverseInputCommon,
        guardrailConfig: BedrockRuntimeClientTypes.GuardrailConfiguration?
    )
        -> ConverseInput
    {
        return ConverseInput(
            additionalModelRequestFields: commonInput
                .additionalModelRequestFields,
            additionalModelResponseFieldPaths: commonInput
                .additionalModelResponseFieldPaths,
            guardrailConfig: guardrailConfig,
            inferenceConfig: commonInput.inferenceConfig,
            messages: commonInput.messages,
            modelId: commonInput.modelId,
            outputConfig: commonInput.outputConfig,
            performanceConfig: commonInput.performanceConfig,
            promptVariables: commonInput.promptVariables,
            requestMetadata: commonInput.requestMetadata,
            serviceTier: commonInput.serviceTier,
            system: commonInput.system,
            toolConfig: commonInput.toolConfig,
        )
    }
}
