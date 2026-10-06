//
//  BedrockClientConfigBuilder.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/06.
//

import AWSBedrockRuntime
import SmithyIdentity

nonisolated enum BedrockClientConfigBuilder {
    static func buildClientConfig(
        model: BedrockLanguageModel
    ) async throws -> BedrockRuntimeClient.BedrockRuntimeClientConfig {
        let config = model.executorConfiguration

        var credentialResolver:
            any SmithyIdentity.AWSCredentialIdentityResolver? = nil

        if let credential = config.credential {
            credentialResolver = StaticAWSCredentialIdentityResolver(
                AWSCredentialIdentity(
                    accessKey: credential.accessKeyId,
                    secret: credential.secretAccessKey,
                    sessionToken: credential.sessionToken,
                )
            )
        }

        var apiKeyResolver: any SmithyIdentity.BearerTokenIdentityResolver? =
            nil

        if let apiKey = config.apiKey {
            apiKeyResolver = StaticBearerTokenIdentityResolver(
                token: BearerTokenIdentity(token: apiKey)
            )
        }

        let runtimeConfig =
            try await BedrockRuntimeClient.BedrockRuntimeClientConfig(
                awsCredentialIdentityResolver: credentialResolver,
                region: config.region,
                bearerTokenIdentityResolver: apiKeyResolver
            )

        return runtimeConfig
    }
}
