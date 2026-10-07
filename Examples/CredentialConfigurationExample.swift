//
//  CredentialConfigurationExample.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/07.
//

import AWSSTS
import BedrockForFoundationModels
import Foundation
import FoundationModels

/// Placeholder values for the advanced configuration example. Replace them with your own.
private enum AdvancedConfigConstants {
    /// The shared config / SSO profile used to call STS.
    static let profileName = "your-sso-profile"
    /// The role to assume for Bedrock access.
    static let roleArn = "arn:aws:iam::123456789012:role/YourBedrockRole"
    /// An application inference profile ARN (a model ID also works).
    static let inferenceProfileArn =
        "arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/your-profile-id"
    static let guardrailId = "your-guardrail-id"
    static let guardrailVersion = "1"
}

/// Assumes a role with STS and returns temporary credentials.
///
/// See [AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).
private func assumeRoleCredentials() async throws
    -> BedrockModelConfiguration.AWSCredentialIdentity
{
    let client = try STSClient(region: ExampleConstants.region)
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
        throw NSError(domain: "Fail to get credential", code: 0)
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
func credentialConfigurationExample(stream: Bool) async throws {
    // the STS client resolves its own credentials from this profile
    setenv("AWS_PROFILE", AdvancedConfigConstants.profileName, 1)

    let credential = try await assumeRoleCredentials()

    let model = BedrockLanguageModel(
        modelId: AdvancedConfigConstants.inferenceProfileArn,
        region: ExampleConstants.region,
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
        let responseStream = session.streamResponse(to: prompt)
        for try await snapshot in responseStream {
            print(snapshot.content)
        }
    } else {
        let response = try await session.respond(to: prompt)
        print(response.content)
    }
}
