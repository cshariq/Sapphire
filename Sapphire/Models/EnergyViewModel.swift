//
//  EnergyViewModel.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08.
//

import Foundation

@MainActor
class EnergyViewModel: ObservableObject {
    @Published var topProcesses: [TopProcess] = []

    private var energyReader: EnergyReader?

    init() {}

    func start() {
        if energyReader == nil {
            energyReader = EnergyReader { [weak self] processes in
                self?.topProcesses = processes
            }
        }
        energyReader?.start()
    }

    func stop() {
        energyReader?.stop()
        energyReader = nil
        topProcesses = []
    }
}