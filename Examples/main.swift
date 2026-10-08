//
//  main.swift
//  BedrockForFoundationModels
//
//  Created by Itsuki on 2026/10/05.
//

/// Run examples in this repository.
/// Optionally set up `ExampleConstants` before the run.
///
/// For advance configuration such as using assume roles, adding guardrails, cache config, please refer to [`AdvancedConfigurationExample`](./AdvancedConfigurationExample.swift)
do {
    try await basicExample(stream: true)
} catch {
    print(error)
}
