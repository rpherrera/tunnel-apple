//
//  GenericSocket.swift
//  PIATunnel
//
//  Created by Davide De Rosa on 4/16/18.
//  Copyright © 2018 London Trust Media. All rights reserved.
//

import Foundation
import NetworkExtension

protocol LinkProducer {
    func link() -> LinkInterface
}

protocol GenericSocketDelegate: class {
    func socketDidBecomeActive(_ socket: GenericSocket)

    func socket(_ socket: GenericSocket, didShutdownWithFailure failure: Bool)

    func socketHasBetterPath(_ socket: GenericSocket)
}

protocol GenericSocket: LinkProducer {
    var endpoint: NWEndpoint { get }
    
    var remoteAddress: String? { get }
    
    var hasBetterPath: Bool { get }
    
    var delegate: GenericSocketDelegate? { get set }

    func observe(queue: DispatchQueue, activeTimeout: Int)

    func unobserve()
    
    func shutdown()
}
