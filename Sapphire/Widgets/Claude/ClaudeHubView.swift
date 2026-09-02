//
//  ClaudeHubView.swift
//  Sapphire
//
//  Chat panel for asking Claude questions directly from the notch.
//

import SwiftUI

struct ClaudeHubView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @StateObject private var session = ClaudeChatSession()
    @State private var draftText = ""
    @State private var hasKey = APIKeyManager.shared.hasAnthropicKey
    @FocusState private var inputFocused: Bool

    init(navigationStack: Binding<[NotchWidgetMode]>) {
        _navigationStack = navigationStack
    }

    var body: some View {
        Group {
            if hasKey {
                chatBody
            } else {
                missingKeyState
            }
        }
        .onAppear { hasKey = APIKeyManager.shared.hasAnthropicKey }
    }

    private var missingKeyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 40))
                .symbolRenderingMode(.multicolor)

            Text("Claude API Key Missing")
                .font(.title2).bold()

            Text("Add your Anthropic API key in Sapphire's settings (under Claude) to start chatting.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)

            Text("Use the back control in the notch to return.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400)
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.messages.isEmpty {
                            emptyState
                        }
                        ForEach(session.messages) { message in
                            ClaudeMessageBubble(message: message, isStreaming: session.isSending && message.id == session.messages.last?.id && message.role == .assistant)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: session.messages.last?.content) { _, _ in
                    guard let lastID = session.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .frame(height: 260)

            if let error = session.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .lineLimit(2)
            }

            inputBar
        }
        .frame(width: 460)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(
                    LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Claude")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            if !session.messages.isEmpty {
                Button {
                    session.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Ask Claude anything.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Claude…", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: session.isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isSending ? Color.secondary : Color.indigo)
            }
            .buttonStyle(.plain)
            .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isSending)
        }
        .padding(12)
    }

    private func sendDraft() {
        if session.isSending {
            session.cancel()
            return
        }
        let text = draftText
        draftText = ""
        session.send(text)
    }
}

private struct ClaudeMessageBubble: View {
    let message: ClaudeChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 0) {
                if message.content.isEmpty && isStreaming {
                    ProgressView().scaleEffect(0.6).frame(height: 14)
                } else {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.role == .user ? Color.indigo.opacity(0.85) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
