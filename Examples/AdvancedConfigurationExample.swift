//
//  AdvancedConfigurationExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import AWSSTS
import BedrockForFoundationModels
import FoundationModels

/// Placeholder values for the advanced configuration example. Replace them with your own.
private enum AdvancedConfigConstants {
    /// AWS region of the Bedrock service.
    static let region = "us-east-1"
    /// The role to assume for Bedrock access.
    static let roleArn = "arn:aws:iam::123456789012:role/YourBedrockRole"
    /// An application inference profile ARN (a model ID also works).
    static let inferenceProfileArn =
        "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/your-profile-id"
    static let guardrailId = "your-guardrail-id"
    static let guardrailVersion = "1"
}

/// Errors thrown by ``assumeRoleCredentials()``.
private enum AssumeRoleError: Error {
    /// STS returned no credentials.
    case missingCredentials
}

/// Assumes a role with STS and returns temporary credentials.
///
/// The STS client itself uses the AWS SDK default chain
/// (for example, `AWS_PROFILE` set in the environment).
///
/// See [AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).
private func assumeRoleCredentials() async throws
    -> BedrockModelConfiguration.AWSCredentialIdentity
{
    let client = try STSClient(region: AdvancedConfigConstants.region)
    let output = try await client.assumeRole(
        input: AssumeRoleInput(
            roleArn: AdvancedConfigConstants.roleArn,
            roleSessionName: "BedrockForFoundationModelsSession"
        )
    )

    guard let credentials = output.credentials,
        let accessKeyId = credentials.accessKeyId,
        let secretAccessKey = credentials.secretAccessKey
    else {
        throw AssumeRoleError.missingCredentials
    }

    return .init(
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        sessionToken: credentials.sessionToken,
        expiration: credentials.expiration
    )
}

/// Advanced configuration: assumed-role credentials, an application inference profile,
/// a guardrail, prompt caching, and latency settings.
///
/// - Parameters:
///   - stream: Whether to use the ConverseStream API and `session.streamResponse`,
///     or the Converse API and `session.respond`.
func advancedConfigurationExample(stream: Bool) async throws {
    let credential = try await assumeRoleCredentials()

    let model = BedrockLanguageModel(
        modelId: AdvancedConfigConstants.inferenceProfileArn,
        region: AdvancedConfigConstants.region,
        credential: credential,
        // https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-use-converse-api.html
        guardrailConfig: .init(
            guardrailIdentifier: AdvancedConfigConstants.guardrailId,
            guardrailVersion: AdvancedConfigConstants.guardrailVersion,
            trace: .enabled,
            // only used with the ConverseStream API
            streamProcessingMode: .async
        ),
        // https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html
        cacheConfig: .init(
            toolsTTL: .fiveMinutes,
            systemPromptTTL: .fiveMinutes,
            messagesTTL: .fiveMinutes
        ),
        // `.optimized` for models that support latency-optimized inference
        // https://docs.aws.amazon.com/bedrock/latest/userguide/latency-optimized-inference.html
        performance: .standard,
        stream: stream
    )

    let session = LanguageModelSession(
        model: model,
        instructions: "Help the user the best you can."
    )
    let prompt = "Hello! What can you help me with?"

    if stream {
        // snapshots are cumulative: print only the newly generated part
        var printed = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            print(snapshot.content.dropFirst(printed.count), terminator: "")
            printed = snapshot.content
        }
        print()
    } else {
        let response = try await session.respond(to: prompt)
        print(response.content)
    }
}
