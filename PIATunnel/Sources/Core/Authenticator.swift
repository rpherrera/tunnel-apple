//
//  Authenticator.swift
//  PIATunnel
//
//  Created by Davide De Rosa on 2/9/17.
//  Copyright © 2018 London Trust Media. All rights reserved.
//

import Foundation
import SwiftyBeaver
import __PIATunnelNative

private let log = SwiftyBeaver.self

fileprivate extension ZeroingData {
    fileprivate func appendSized(_ buf: ZeroingData) {
        append(Z(UInt16(buf.count).bigEndian))
        append(buf)
    }
}

class Authenticator {
    private var controlBuffer: ZeroingData
    
    private(set) var preMaster: ZeroingData
    
    private(set) var random1: ZeroingData
    
    private(set) var random2: ZeroingData
    
    private(set) var serverRandom1: ZeroingData?

    private(set) var serverRandom2: ZeroingData?

    let username: ZeroingData
    
    let password: ZeroingData
    
    init(_ username: String, _ password: String) throws {
        preMaster = try SecureRandom.safeData(length: Configuration.preMasterLength)
        random1 = try SecureRandom.safeData(length: Configuration.randomLength)
        random2 = try SecureRandom.safeData(length: Configuration.randomLength)
        
        // XXX: not 100% secure, can't erase input username/password
        self.username = Z(username, nullTerminated: true)
        self.password = Z(password, nullTerminated: true)
        
        controlBuffer = Z()
    }
    
    // MARK: Authentication request

    // Ruby: on_tls_connect
    func putAuth(into: TLSBox) throws {
        let raw = Z(ProtocolMacros.tlsPrefix)
        
        // local keys
        raw.append(preMaster)
        raw.append(random1)
        raw.append(random2)
        
        // opts
        raw.appendSized(Z(UInt8(0)))
        
        // credentials
        raw.appendSized(username)
        raw.appendSized(password)

        // peer info
        raw.appendSized(Z(Configuration.peerInfo))

        if Configuration.logsSensitiveData {
            log.debug("TLS.auth: Put plaintext (\(raw.count) bytes): \(raw.toHex())")
        } else {
            log.debug("TLS.auth: Put plaintext (\(raw.count) bytes)")
        }
        
        try into.putRawPlainText(raw.bytes, length: raw.count)
    }
    
    // MARK: Server replies

    func appendControlData(_ data: ZeroingData) {
        controlBuffer.append(data)
    }
    
    func isAuthReplyComplete() -> Bool {
        let prefixLength = ProtocolMacros.tlsPrefix.count
        
        return (controlBuffer.count >= prefixLength + 2 * Configuration.randomLength)
    }
    
    func parseAuthReply() -> Bool {
        let prefixLength = ProtocolMacros.tlsPrefix.count
        let prefix = controlBuffer.withOffset(0, count: prefixLength)!
        
        guard prefix.isEqual(to: ProtocolMacros.tlsPrefix) else {
            return false
        }
        
        var offset = ProtocolMacros.tlsPrefix.count
        
        let serverRandom1 = controlBuffer.withOffset(offset, count: Configuration.randomLength)!
        offset += Configuration.randomLength
        
        let serverRandom2 = controlBuffer.withOffset(offset, count: Configuration.randomLength)!
        offset += Configuration.randomLength
        
        let serverOptsLength = Int(CFSwapInt16BigToHost(controlBuffer.uint16Value(fromOffset: offset)))
        offset += 2
        
        let serverOpts = controlBuffer.withOffset(offset, count: serverOptsLength)!
        offset += serverOptsLength

        if Configuration.logsSensitiveData {
            log.debug("TLS.auth: Parsed server random: [\(serverRandom1.toHex()), \(serverRandom2.toHex())]")
        } else {
            log.debug("TLS.auth: Parsed server random")
        }
        
        if let serverOptsString = serverOpts.nullTerminatedString(fromOffset: 0) {
            log.debug("TLS.auth: Parsed server opts: \"\(serverOptsString)\"")
        }
        
        self.serverRandom1 = serverRandom1
        self.serverRandom2 = serverRandom2
        controlBuffer.remove(untilOffset: offset)
        
        return true
    }
    
    func parseMessages() -> [String] {
        var messages = [String]()
        var offset = 0
        
        while true {
            guard let msg = controlBuffer.nullTerminatedString(fromOffset: offset) else {
                break
            }
            messages.append(msg)
            offset += msg.count + 1
        }

        controlBuffer.remove(untilOffset: offset)

        return messages
    }
}
