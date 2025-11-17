//
//  DragStateManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import Foundation
import Combine

@MainActor
class DragStateManager: ObservableObject {
    static let shared = DragStateManager()
    @Published var isDraggingFromShelf = false
    @Published var didJustDrop = false
    private init() {}
}