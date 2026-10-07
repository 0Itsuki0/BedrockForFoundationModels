//
//  ConverseInputCommon.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import AWSBedrockRuntime
import Smithy

/// Shared fields for ConverseInput and ConverseStreamInput
struct ConverseInputCommon: Sendable {
    /// Additional inference parameters that the model supports, beyond the base set of inference parameters that Converse and ConverseStream support in the inferenceConfig field. For more information, see [Model parameters](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters.html).
    var additionalModelRequestFields: Smithy.Document?
    /// Additional model parameters field paths to return in the response. Converse and ConverseStream return the requested fields as a JSON Pointer object in the additionalModelResponseFields field. The following is example JSON for additionalModelResponseFieldPaths. [ "/stop_sequence" ] For information about the JSON Pointer syntax, see the [Internet Engineering Task Force (IETF)](https://datatracker.ietf.org/doc/html/rfc6901) documentation. Converse and ConverseStream reject an empty JSON Pointer or incorrectly structured JSON Pointer with a 400 error code. if the JSON Pointer is valid, but the requested field is not in the model response, it is ignored by Converse.
    var additionalModelResponseFieldPaths: [String]?
    /// Inference parameters to pass to the model. Converse and ConverseStream support a base set of inference parameters. If you need to pass additional parameters that the model supports, use the additionalModelRequestFields request field.
    var inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration?
    /// The messages that you want to send to the model.
    var messages: [BedrockRuntimeClientTypes.Message]?
    /// Specifies the model or throughput with which to run inference, or the prompt resource to use in inference. The value depends on the resource that you use:
    ///
    /// * If you use a base model, specify the model ID or its ARN. For a list of model IDs for base models, see [Amazon Bedrock base model IDs (on-demand throughput)](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html#model-ids-arns) in the Amazon Bedrock User Guide.
    ///
    /// * If you use an inference profile, specify the inference profile ID or its ARN. For a list of inference profile IDs, see [Supported Regions and models for cross-region inference](https://docs.aws.amazon.com/bedrock/latest/userguide/cross-region-inference-support.html) in the Amazon Bedrock User Guide.
    ///
    /// * If you use a provisioned model, specify the ARN of the Provisioned Throughput. For more information, see [Run inference using a Provisioned Throughput](https://docs.aws.amazon.com/bedrock/latest/userguide/prov-thru-use.html) in the Amazon Bedrock User Guide.
    ///
    /// * If you use a custom model, first purchase Provisioned Throughput for it. Then specify the ARN of the resulting provisioned model. For more information, see [Use a custom model in Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-use.html) in the Amazon Bedrock User Guide.
    ///
    /// * To include a prompt that was defined in [Prompt management](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-management.html), specify the ARN of the prompt version to use.
    ///
    ///
    /// The Converse API doesn't support [imported models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-import-model.html).
    /// This member is required.
    var modelId: String?
    /// Output configuration for a model response.
    var outputConfig: BedrockRuntimeClientTypes.OutputConfig?
    /// Model performance settings for the request.
    var performanceConfig: BedrockRuntimeClientTypes.PerformanceConfiguration?
    /// Contains a map of variables in a prompt from Prompt management to objects containing the values to fill in for them when running model invocation. This field is ignored if you don't specify a prompt resource in the modelId field.
    var promptVariables: [String: BedrockRuntimeClientTypes.PromptVariableValues]?
    /// Key-value pairs that you can use to filter invocation logs.
    var requestMetadata: [String: String]?
    /// Specifies the processing tier configuration used for serving the request.
    var serviceTier: BedrockRuntimeClientTypes.ServiceTier?
    /// A prompt that provides instructions or context to the model about the task it should perform, or the persona it should adopt during the conversation.
    var system: [BedrockRuntimeClientTypes.SystemContentBlock]?
    /// Configuration information for the tools that the model can use when generating a response. For information about models that support tool use, see [Supported models and model features](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html#conversation-inference-supported-models-features).
    var toolConfig: BedrockRuntimeClientTypes.ToolConfiguration?

    init(
        additionalModelRequestFields: Smithy.Document? = nil,
        additionalModelResponseFieldPaths: [String]? = nil,
        inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration? =
            nil,
        messages: [BedrockRuntimeClientTypes.Message]? = nil,
        modelId: String? = nil,
        outputConfig: BedrockRuntimeClientTypes.OutputConfig? = nil,
        performanceConfig: BedrockRuntimeClientTypes.PerformanceConfiguration? =
            nil,
        promptVariables: [String: BedrockRuntimeClientTypes
            .PromptVariableValues]? = nil,
        requestMetadata: [String: String]? = nil,
        serviceTier: BedrockRuntimeClientTypes.ServiceTier? = nil,
        system: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil,
        toolConfig: BedrockRuntimeClientTypes.ToolConfiguration? = nil
    ) {
        self.additionalModelRequestFields = additionalModelRequestFields
        self.additionalModelResponseFieldPaths =
            additionalModelResponseFieldPaths
        self.inferenceConfig = inferenceConfig
        self.messages = messages
        self.modelId = modelId
        self.outputConfig = outputConfig
        self.performanceConfig = performanceConfig
        self.promptVariables = promptVariables
        self.requestMetadata = requestMetadata
        self.serviceTier = serviceTier
        self.system = system
        self.toolConfig = toolConfig
    }
}
