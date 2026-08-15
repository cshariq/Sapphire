//
//  PasswordPromptView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//

import SwiftUI

struct PasswordPromptView: View {
    @Binding var isPresented: Bool
    var validate: ((String) -> Bool)?
    var title: String = "Authentication Required"
    var message: String = "To enable Bluetooth Unlock, Sapphire needs your Mac's login password. It will be stored securely in your system's Keychain and used only to unlock your device."
    var onSubmit: (String) -> Void

    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .multilineTextAlignment(.center)

            if let message = errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    if password.isEmpty {
                        errorMessage = "Password cannot be empty."
                    } else if let validate = validate, !validate(password) {
                        errorMessage = "Incorrect password. Please try again."
                        password = ""
                    } else {
                        onSubmit(password)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 350)
    }
}