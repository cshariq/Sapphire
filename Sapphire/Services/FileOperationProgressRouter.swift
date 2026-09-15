//
//  FileOperationProgressRouter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-06

import Foundation
import Combine

@MainActor
final class FileOperationProgressRouter {
    static let shared = FileOperationProgressRouter()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        ArchiveExtractor.shared.$currentTransferTask
            .receive(on: DispatchQueue.main)
            .sink { task in
                Self.route(task, sourceType: .archiveExtraction, displayMode: SettingsModel.shared.settings.archiveProgressDisplay)
            }
            .store(in: &cancellables)

        DMGInstallerManager.shared.$currentTransferTask
            .receive(on: DispatchQueue.main)
            .sink { task in
                Self.route(task, sourceType: .dmgInstall, displayMode: SettingsModel.shared.settings.dmgInstallerProgressDisplay)
            }
            .store(in: &cancellables)
    }

    func start() {}

    private static func route(_ task: FileTransferTask?, sourceType: FileTransferTask.FileTransferSource, displayMode: FileOperationProgressDisplay) {
        switch displayMode {
        case .liveActivity:
            FileDropManager.shared.updateExternalTask(task, sourceType: sourceType)
        case .popup:
            FileOperationProgressPresenter.shared.update(task)
        }
    }
}