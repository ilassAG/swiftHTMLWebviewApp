//
//  BridgeRouter.swift
//  swiftHTMLWebviewApp
//

import Foundation

struct BridgeRouter {
    typealias Handler = ([String: Any]) -> Void
    typealias ResultHandler = ([String: Any]) -> Void

    private let handlers: [String: Handler]
    private let resultHandler: ResultHandler
    private let missingActionMessage: String
    private let unknownActionMessage: (String) -> String
    private let unknownActionHandler: (() -> Void)?

    init(
        handlers: [String: Handler],
        resultHandler: @escaping ResultHandler,
        missingActionMessage: String,
        unknownActionMessage: @escaping (String) -> String,
        unknownActionHandler: (() -> Void)? = nil
    ) {
        self.handlers = handlers
        self.resultHandler = resultHandler
        self.missingActionMessage = missingActionMessage
        self.unknownActionMessage = unknownActionMessage
        self.unknownActionHandler = unknownActionHandler
    }

    var actions: Set<String> {
        Set(handlers.keys)
    }

    func postMessage(_ request: [String: Any]) {
        guard let action = BridgeDispatcher.action(from: request) else {
            resultHandler(BridgeDispatcher.missingActionResponse(
                request: request,
                message: missingActionMessage
            ))
            return
        }

        guard let handler = handlers[action] else {
            resultHandler(BridgeDispatcher.unknownActionResponse(
                request: request,
                action: action,
                message: unknownActionMessage(action)
            ))
            unknownActionHandler?()
            return
        }

        handler(request)
    }

    final class Builder {
        private var handlers: [String: Handler] = [:]
        private let resultHandler: ResultHandler
        private let missingActionMessage: String
        private let unknownActionMessage: (String) -> String
        private let unknownActionHandler: (() -> Void)?

        init(
            resultHandler: @escaping ResultHandler,
            missingActionMessage: String,
            unknownActionMessage: @escaping (String) -> String,
            unknownActionHandler: (() -> Void)? = nil
        ) {
            self.resultHandler = resultHandler
            self.missingActionMessage = missingActionMessage
            self.unknownActionMessage = unknownActionMessage
            self.unknownActionHandler = unknownActionHandler
        }

        @discardableResult
        func on(_ action: String, handler: @escaping Handler) -> Builder {
            handlers[action] = handler
            return self
        }

        @discardableResult
        func onAll(_ actions: [String], handler: @escaping Handler) -> Builder {
            for action in actions {
                on(action, handler: handler)
            }
            return self
        }

        func build() -> BridgeRouter {
            BridgeRouter(
                handlers: handlers,
                resultHandler: resultHandler,
                missingActionMessage: missingActionMessage,
                unknownActionMessage: unknownActionMessage,
                unknownActionHandler: unknownActionHandler
            )
        }
    }
}
