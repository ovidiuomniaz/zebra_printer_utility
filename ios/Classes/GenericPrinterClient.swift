//
//  GenericPrinterClient.swift
//  zebrautil
//
//  Replaces POSWIFIManager (vendored 3rd-party POS code, no license, no source)
//  with a thin wrapper around CocoaAsyncSocket's GCDAsyncSocket. Keeps the
//  Swift-bridged surface that Printer.swift already calls
//  (posConnect/posDisConnect/posWriteCommand/connectOK) so the only call-site
//  change is the type swap from `POSWIFIManager?` to `GenericPrinterClient?`.
//
//  Behavior delta from POSWIFIManager: no auto-reconnect timer. The original
//  attempted to re-establish a dropped connection on a timer; this client
//  surfaces disconnects to the caller and lets the integrator decide.
//

import Foundation
import CocoaAsyncSocket

final class GenericPrinterClient: NSObject {
    private static let connectTimeout: TimeInterval = 5
    private static let writeTimeout: TimeInterval = 10

    private let delegateQueue = DispatchQueue(
        label: "com.rubdev.zebrautil.generic-printer"
    )

    private var socket: GCDAsyncSocket?
    private var connectCompletion: ((Bool) -> Void)?
    private var writeCompletion: ((Bool) -> Void)?

    private(set) var connectOK: Bool = false

    override init() {
        super.init()
    }

    func posConnect(
        withHost host: String,
        port: UInt16,
        completion: @escaping (Bool) -> Void
    ) {
        delegateQueue.async {
            self.disconnectInternal()
            self.connectCompletion = completion
            let socket = GCDAsyncSocket(
                delegate: self,
                delegateQueue: self.delegateQueue
            )
            self.socket = socket
            do {
                try socket.connect(
                    toHost: host,
                    onPort: port,
                    withTimeout: Self.connectTimeout
                )
            } catch {
                self.connectOK = false
                let cb = self.connectCompletion
                self.connectCompletion = nil
                DispatchQueue.main.async { cb?(false) }
            }
        }
    }

    func posDisConnect() {
        delegateQueue.async { self.disconnectInternal() }
    }

    func posWriteCommand(
        with data: Data,
        withResponse: @escaping (Bool) -> Void
    ) {
        delegateQueue.async {
            guard let socket = self.socket, socket.isConnected else {
                DispatchQueue.main.async { withResponse(false) }
                return
            }
            self.writeCompletion = withResponse
            socket.write(data, withTimeout: Self.writeTimeout, tag: 0)
        }
    }

    /// Must be called on `delegateQueue`.
    private func disconnectInternal() {
        connectOK = false
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
    }
}

extension GenericPrinterClient: GCDAsyncSocketDelegate {
    func socket(
        _ sock: GCDAsyncSocket,
        didConnectToHost host: String,
        port: UInt16
    ) {
        connectOK = true
        let cb = connectCompletion
        connectCompletion = nil
        DispatchQueue.main.async { cb?(true) }
    }

    func socketDidDisconnect(
        _ sock: GCDAsyncSocket,
        withError err: Error?
    ) {
        connectOK = false
        if let cb = connectCompletion {
            connectCompletion = nil
            DispatchQueue.main.async { cb(false) }
        }
        if let cb = writeCompletion {
            writeCompletion = nil
            DispatchQueue.main.async { cb(false) }
        }
    }

    func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        let cb = writeCompletion
        writeCompletion = nil
        DispatchQueue.main.async { cb?(true) }
    }
}
