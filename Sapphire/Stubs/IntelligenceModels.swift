//
//  IntelligenceModels.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation

enum LLMBackend: String, Codable, CaseIterable {
    case auto, gemini, openAI, anthropic, openRouter, xai, nvidia, hackclub

    var isKeyConfigured: Bool { false }
    func resolveAPIKey(fallbackGeminiKey: String) -> String { fallbackGeminiKey }
}

enum GeminiSpeedMode: String, Codable, CaseIterable {
    case fast, quality
}

enum GeminiModelOption: String, Codable, CaseIterable {
    case auto, flash35Lite
}

enum OpenAIModelOption: String, Codable, CaseIterable {
    case auto
}

enum AnthropicModelOption: String, Codable, CaseIterable {
    case auto
}

enum XAIModelOption: String, Codable, CaseIterable {
    case auto
}

enum NVIDIAModelOption: String, Codable, CaseIterable {
    case auto
}

enum OpenRouterModelPreset: String, Codable, CaseIterable {
    case auto
}

enum BlipModelPreferences {
    static var openAIModel = ""
    static var anthropicModel = ""
    static var openRouterModelStored = ""
    static var xaiModel = ""
    static var nvidiaModel = ""
}
#endif