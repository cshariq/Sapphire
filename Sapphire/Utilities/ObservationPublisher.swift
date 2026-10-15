//
//  ObservationPublisher.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-28

import Combine
import Foundation
import Observation

func observationPublisher<Value>(_ read: @escaping () -> Value) -> AnyPublisher<Value, Never> {
    Deferred { () -> AnyPublisher<Value, Never> in
        let relay = ObservationRelay(read: { read() })
        return relay.publisher
    }
    .eraseToAnyPublisher()
}

extension Observable where Self: AnyObject {
    func valuePublisher<Value>(_ keyPath: KeyPath<Self, Value>) -> AnyPublisher<Value, Never> {
        Deferred { [weak self] () -> AnyPublisher<Value, Never> in
            guard let self else { return Empty().eraseToAnyPublisher() }
            let relay = ObservationRelay { [weak self] in self?[keyPath: keyPath] }
            return relay.publisher
        }
        .eraseToAnyPublisher()
    }
}

private final class ObservationRelay<Value>: @unchecked Sendable {
    private let read: () -> Value?
    private var subject: CurrentValueSubject<Value, Never>?
    private let lock = NSLock()
    private var isCancelled = false

    init(read: @escaping () -> Value?) {
        self.read = read
        subject = arm().map { CurrentValueSubject($0) }
    }

    var publisher: AnyPublisher<Value, Never> {
        guard let subject else { return Empty().eraseToAnyPublisher() }
        return subject
            .handleEvents(receiveCancel: { [self] in cancel() })
            .eraseToAnyPublisher()
    }

    private func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    @discardableResult
    private func arm() -> Value? {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.emitAndRearm() }
        }
    }

    private func emitAndRearm() {
        guard !cancelled, let value = arm() else { return }
        subject?.send(value)
    }
}