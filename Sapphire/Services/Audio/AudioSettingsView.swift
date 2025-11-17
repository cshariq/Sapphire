//
//  AudioSettingsView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

import SwiftUI

fileprivate enum HelperStatus: Equatable {
    case unknown
    case notInstalled
    case installing
    case installed
    case failed(String)
}

struct AudioSettingsView: View {
    @State private var helperStatus: HelperStatus = .unknown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("System Audio Helper")
                    .font(.largeTitle.bold())
                    .padding(.bottom)

                InfoContainer(text: "All audio features are in development.", iconName: "info.circle.fill", color: .yellow)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Helper Status")
                        .font(.headline)

                    Text("To combine multiple speakers, Sapphire needs to install a small helper tool. This only needs to be done once.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 5)

                    HStack {
                        switch helperStatus {
                        case .unknown:
                            Image(systemName: "questionmark.diamond.fill")
                                .foregroundColor(.secondary)
                            Text("Checking helper status...")

                        case .notInstalled:
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundColor(.red)
                            Text("Helper tool is not installed.")

                        case .installing:
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing helper...")

                        case .installed:
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Helper is installed and active.")

                        case .failed(let error):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Installation failed: \(error)")
                        }

                        Spacer()

                            Button("Install Helper") {
                                installHelper()
                            }

                        if helperStatus == .installed {
                             Button("Uninstall Helper") {
                                 print("Uninstall logic to be implemented.")
                             }
                             .tint(.red)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
                .cornerRadius(12)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func installHelper() {
        self.helperStatus = .installing

        guard let scriptPath = Bundle.main.path(forResource: "install", ofType: "sh") else {
            self.helperStatus = .failed("Installation script (install.sh) not found.")
            return
        }

    }
}