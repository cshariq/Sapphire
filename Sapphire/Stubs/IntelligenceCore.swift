#if !SAPPHIRE_FULL_BUILD
import Foundation
import AppKit
import SwiftUI

// MARK: - LLM backends / model options

enum LLMBackend: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case gemini
    case openai
    case anthropic
    case openrouter
    case xai
    case nvidia
    case hackclub

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .gemini: "Gemini"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .openrouter: "OpenRouter"
        case .xai: "xAI"
        case .nvidia: "NVIDIA"
        case .hackclub: "Hack Club"
        }
    }

    var isKeyConfigured: Bool {
        let keys = APIKeyManager.shared
        switch self {
        case .auto:
            return keys.hasGeminiKey
                || keys.hasOpenAIKey
                || keys.hasAnthropicKey
                || keys.hasOpenRouterKey
                || keys.hasXAIKey
                || !keys.nvidiaAPIKey.isEmpty
                || keys.hasHackClubKey
        case .gemini: return keys.hasGeminiKey
        case .openai: return keys.hasOpenAIKey
        case .anthropic: return keys.hasAnthropicKey
        case .openrouter: return keys.hasOpenRouterKey
        case .xai: return keys.hasXAIKey
        case .nvidia: return !keys.nvidiaAPIKey.isEmpty
        case .hackclub: return keys.hasHackClubKey
        }
    }

    func resolveAPIKey(fallbackGeminiKey: String) -> String {
        let keys = APIKeyManager.shared
        switch self {
        case .auto:
            if keys.hasGeminiKey { return keys.googleGeminiAPIKey }
            if !fallbackGeminiKey.isEmpty { return fallbackGeminiKey }
            if keys.hasOpenAIKey { return keys.openAIAPIKey }
            if keys.hasAnthropicKey { return keys.anthropicAPIKey }
            if keys.hasOpenRouterKey { return keys.openRouterAPIKey }
            if keys.hasXAIKey { return keys.xaiAPIKey }
            if !keys.nvidiaAPIKey.isEmpty { return keys.nvidiaAPIKey }
            if keys.hasHackClubKey { return keys.hackClubAPIKey }
            return fallbackGeminiKey
        case .gemini:
            let gemini = keys.googleGeminiAPIKey
            return gemini.isEmpty ? fallbackGeminiKey : gemini
        case .openai: return keys.openAIAPIKey
        case .anthropic: return keys.anthropicAPIKey
        case .openrouter: return keys.openRouterAPIKey
        case .xai: return keys.xaiAPIKey
        case .nvidia: return keys.nvidiaAPIKey
        case .hackclub: return keys.hackClubAPIKey
        }
    }
}

enum GeminiSpeedMode: String, Codable, CaseIterable, Identifiable, Equatable {
    case fast
    case balanced
    case quality

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum GeminiModelOption: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case flash35Lite
    case flash25
    case pro25

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .flash35Lite: "Gemini 3.5 Flash Lite"
        case .flash25: "Gemini 2.5 Flash"
        case .pro25: "Gemini 2.5 Pro"
        }
    }
}

enum OpenAIModelOption: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case gpt4o
    case gpt4oMini
    case o3Mini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .gpt4o: "GPT-4o"
        case .gpt4oMini: "GPT-4o mini"
        case .o3Mini: "o3-mini"
        }
    }
}

enum AnthropicModelOption: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case sonnet
    case haiku
    case opus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .sonnet: "Claude Sonnet"
        case .haiku: "Claude Haiku"
        case .opus: "Claude Opus"
        }
    }
}

enum XAIModelOption: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case grok2
    case grok3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .grok2: "Grok 2"
        case .grok3: "Grok 3"
        }
    }
}

enum NVIDIAModelOption: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case nemotron
    case llama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .nemotron: "Nemotron"
        case .llama: "Llama"
        }
    }
}

enum OpenRouterModelPreset: String, Codable, CaseIterable, Identifiable, Equatable {
    case auto
    case free
    case balanced
    case quality

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum BlipModelPreferences {
    static var openAIModel: String {
        get { UserDefaults.standard.string(forKey: "blipOpenAIModel") ?? OpenAIModelOption.auto.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "blipOpenAIModel") }
    }

    static var anthropicModel: String {
        get { UserDefaults.standard.string(forKey: "blipAnthropicModel") ?? AnthropicModelOption.auto.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "blipAnthropicModel") }
    }

    static var openRouterModelStored: String {
        get { UserDefaults.standard.string(forKey: "blipOpenRouterModel") ?? OpenRouterModelPreset.auto.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "blipOpenRouterModel") }
    }

    static var xaiModel: String {
        get { UserDefaults.standard.string(forKey: "blipXAIModel") ?? XAIModelOption.auto.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "blipXAIModel") }
    }

    static var nvidiaModel: String {
        get { UserDefaults.standard.string(forKey: "blipNVIDIAModel") ?? NVIDIAModelOption.auto.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "blipNVIDIAModel") }
    }
}

// MARK: - Agent run result / logs

struct IntelligenceAgentResult: Equatable {
    var success: Bool
    var subtasksCompleted: Int
    var subtasksTotal: Int
    var actionsTaken: Int
    var duration: TimeInterval
}

struct IntelligenceLogEntry: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError: Bool
    var isSubtask: Bool

    init(text: String, isError: Bool = false, isSubtask: Bool = false) {
        self.text = text
        self.isError = isError
        self.isSubtask = isSubtask
    }
}

struct ScreenPerceptionElement: Identifiable, Equatable {
    let id = UUID()
    var label: String
}

struct ScreenPerception {
    func captureAnnotatedScreen() async -> (NSImage?, [ScreenPerceptionElement]) {
        (nil, [])
    }
}

// MARK: - Settings pane placeholder

struct IntelligenceSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Blip unavailable in this build", systemImage: "sparkles")
                .font(.headline)
            Text("Intelligence / Blip sources are not included in this fork yet. Model and agent settings are stubbed so the rest of Sapphire can build and run.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

final class EncryptionManager {
    static let shared = EncryptionManager()
    private init() {}

    func encrypt(_ data: Data) throws -> Data { data }
    func decrypt(_ data: Data) throws -> Data { data }
}
#endif
