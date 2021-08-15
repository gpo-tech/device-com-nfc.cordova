import Cordova
import Cordova
import Cordova
import Cordova
import Cordova
import Cordova
//
//  NFCTapPlugin.swift
//  NFC
//
//  Created by dev@iotize.com on 23/07/2019.
//  Copyright © 2019 dev@iotize.com. All rights reserved.
//

import Foundation
import UIKit
import CoreNFC

// Main class handling the plugin functionalities.
@objc(NfcPlugin) class NfcPlugin: CDVPlugin {
    var nfcController: NSObject? // ST25DVReader downCast as NSObject for iOS version compatibility
    var ndefController: NFCNDEFDelegate?
    var lastError: Error?
    var channelCommand: CDVInvokedUrlCommand?
    var isListeningNDEF = false

    // helper to return a string
    func sendSuccess(command: CDVInvokedUrlCommand, result: String) {
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: result
        )
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    // helper to return a boolean
    private func sendSuccess(command: CDVInvokedUrlCommand, result: Bool) {
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: result
        )
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    // helper to return a String with keeping the callback
    func sendSuccessWithResponse(command: CDVInvokedUrlCommand, result: String) {
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: result
        )
        pluginResult!.setKeepCallbackAs(true)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    // helper to send back an error
    func sendError(command: CDVInvokedUrlCommand, result: String) {
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR,
            messageAs: result
        )
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(connect:)
    func connect(command: CDVInvokedUrlCommand) {
        guard #available(iOS 13.0, *) else {
            sendError(command: command, result: "connect is only available on iOS 13+")
            return
        }
        DispatchQueue.main.async {
            print("Begin session \(self.nfcController)")
            if self.nfcController == nil {
                self.nfcController = ST25DVReader()
            }

            (self.nfcController as! ST25DVReader).initSession(alertMessage: "Bring your phone close to the Tap.", completed: {
                (error: Error?) -> Void in

                DispatchQueue.main.async {
                    if error != nil {
                        self.sendError(command: command, result: error!.localizedDescription)
                    } else {
                        self.sendSuccess(command: command, result: "")
                    }
                }
            })
        }
    }

    @objc(close:)
    func close(command: CDVInvokedUrlCommand) {
        guard #available(iOS 13.0, *) else {
            sendError(command: command, result: "close is only available on iOS 13+")
            return
        }
        DispatchQueue.main.async {
            if self.nfcController == nil {
                self.sendError(command: command, result: "no session to terminate")
                return
            }

            (self.nfcController as! ST25DVReader).invalidateSession(message: "Sesssion Ended!")
            self.nfcController = nil
        }
    }

    @objc(transceive:)
    func transceive(command: CDVInvokedUrlCommand) {
        guard #available(iOS 13.0, *) else {
            sendError(command: command, result: "transceive is only available on iOS 13+")
            return
        }
        DispatchQueue.main.async {
            print("sending ...")
            if self.nfcController == nil {
                self.sendError(command: command, result: "no session available")
                return
            }

            // we need data to send
            if command.arguments.count <= 0 {
                self.sendError(command: command, result: "SendRequest parameter error")
                return
            }

            guard let data: NSData = command.arguments[0] as? NSData else {
                self.sendError(command: command, result: "Tried to transceive empty string")
                return
            }
            let request = data.map { String(format: "%02x", $0) }
                .joined()
            print("send request  - \(request)")

            if (self.transceiveDispatcher(command: command)) {
                print("Handled by dispatcher")
            } else {
                (self.nfcController as! ST25DVReader).send(request: request, completed: {
                    (response: Data?, error: Error?) -> Void in

                    DispatchQueue.main.async {
                        if error != nil {
                            self.lastError = error
                            self.sendError(command: command, result: error!.localizedDescription)
                        } else {
                            print("responded \(response!.hexEncodedString())")
                            self.sendSuccess(command: command, result: response!.hexEncodedString())
                        }
                    }
                })
            }
        }
    }

    func performResponse(command: CDVInvokedUrlCommand, response: Data?, error: Error?) -> Void {
        DispatchQueue.main.async {
            if error != nil {
                self.lastError = error
                self.sendError(command: command, result: error!.localizedDescription)
            } else {
                print("responded \(response!.hexEncodedString())")
                self.sendSuccess(command: command, result: response!.hexEncodedString())
            }
        }
    }

    func performArrayResponse(command: CDVInvokedUrlCommand, response: [Data], error: Error?) -> Void {
        DispatchQueue.main.async {
            if error != nil {
                self.lastError = error
                self.sendError(command: command, result: error!.localizedDescription)
            } else {
                let respArray = flattenedArray(array: response)
                let respData = Data(bytes: respArray, count: respArray.count)
                print("responded \(response) : \(respArray) : \(respData.hexEncodedString())")
                self.sendSuccess(command: command, result: respData.hexEncodedString())
            }
        }
    }

    func transceiveDispatcher(command: CDVInvokedUrlCommand) -> Bool {
        guard #available(iOS 13.0, *) else {
            sendError(command: command, result: "Those commands are only available on iOS 13+")
            return false
        }
        guard let data: NSData = command.arguments[0] as? NSData else {
            self.sendError(command: command, result: "Tried to transceive empty string")
            return false
        }

        let request = data.map { String(format: "%02x", $0) }
            .joined()

        if (request.lengthOfBytes(using: String.Encoding.utf8) < 4) {
            return false
        }

        let array = request.split(by: 2)
        let commandCode = array[1]
        switch commandCode {
            case "20":
                if let blockNumberStr = array.last, let blockNumber = UInt(blockNumberStr, radix: 16) {
                    print("Read single block, Recognized blockNumber: \(blockNumber)")
                    (self.nfcController as! ST25DVReader).readSingleBlock(blockNumber: UInt8(blockNumber), completed: {
                        (response: Data?, error: Error?) -> Void in
                        self.performResponse(command: command, response: response, error: error)
                    })
                    return true
                }

            case "21":
                print("Write single block")
                if let startBlock = UInt8(array[10], radix: 16) {
                        print("Recognized blockNumber: \(startBlock)")
                    let prepared = array[11...].map({
                        (n: String) -> UInt8 in
                        return UInt8(n, radix: 16) ?? 0
                    })

                        (self.nfcController as! ST25DVReader).writeSingleBlock(blockNumber: startBlock, data: Data(prepared), completed: {
                            (error: Error?) -> Void in
                            self.performResponse(command: command, response: "00".data(using: .utf8)!, error: error)
                        })
                        return true
                }

            case "23":
                print("read multiples blocks")
                if let numberOfBlocksStr = array.last, let numberOfBlocks = Int(numberOfBlocksStr, radix: 16), let startBlock = Int(array[array.count - 2], radix: 16) {
                    print("Recognized startBlock: \(startBlock), numberOfBlocks: \(numberOfBlocks)")
                    do {
                        try (self.nfcController as! ST25DVReader).readMultipleBlocks(from: startBlock, numberOfBlocks: numberOfBlocks, completed: {
                            (response: [Data], error: Error?) -> Void in
                            print("Response after read multiple blocks: \(response), error: \(error)")
                            self.performArrayResponse(command: command, response: response, error: error)
                        })
                        return true

                    } catch NfcCustomError.oldVersionError(let errorMessage) {
                        print("Error: \(errorMessage)")
                    } catch {
                        print("Error: not recognized")
                    }
                }

            case "24":
                print("write multiples blocks")
                if let startBlock = Int(array[10], radix: 16), let numberOfBlocks = Int(array[11], radix: 16) {
                    print("Recognized startBlock: \(startBlock), numberOfBlocks: \(numberOfBlocks), \(array[12...])")
                    let prepared = array[12...].map({
                        (n: String) -> UInt8 in
//                        withUnsafeBytes(of: ) { Data($0) }
                        UInt8(n, radix: 16) ?? 0
                    })
                    .chunked(into: 4)
                    .map({
                        (arr: [UInt8]) -> Data in
                        Data(arr)
                    })
                    print("Prepared data: \(prepared)")
                    do {
                        try (self.nfcController as! ST25DVReader).writeMultipleBlocks(from: startBlock, numberOfBlocks: numberOfBlocks, dataBlocks: prepared, completed: {
                            (error: Error?) -> Void in
                            self.performArrayResponse(command: command, response: ["00".data(using: .utf8)!], error: error)
                        })
                        return true

                    } catch NfcCustomError.oldVersionError(let errorMessage) {
                        print("Error: \(errorMessage)")
                    } catch {
                        print("Error: not recognized")
                    }
                }


            default:
                return false

        }

        return false
    }

    @objc(registerNdef:)
    func registerNdef(command: CDVInvokedUrlCommand) {
        print("Registered NDEF Listener")
        isListeningNDEF = true // Flag for the AppDelegate
        sendSuccess(command: command, result: "NDEF Listener is on")
    }

    @objc(registerMimeType:)
    func registerMimeType(command: CDVInvokedUrlCommand) {
        print("Registered Mi Listener")
        sendSuccess(command: command, result: "NDEF Listener is on")
    }

    @objc(beginNDEFSession:)
    func beginNDEFSession(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            print("Begin NDEF reading session")

            if self.ndefController == nil {
                var message: String?
                if command.arguments.count != 0 {
                    message = command.arguments[0] as? String ?? ""
                }
                self.ndefController = NFCNDEFDelegate(completed: {
                    (response: [AnyHashable: Any]?, error: Error?) -> Void in
                    DispatchQueue.main.async {
                        print("handle NDEF")
                        if error != nil {
                            self.lastError = error
                            self.sendError(command: command, result: error!.localizedDescription)
                        } else {
                            // self.sendSuccess(command: command, result: response ?? "")
                            self.sendThroughChannel(jsonDictionary: response ?? [:])
                        }
                        self.ndefController = nil
                    }
                }, message: message)
            }
        }
    }

    @objc(invalidateNDEFSession:)
    func invalidateNDEFSession(command: CDVInvokedUrlCommand) {
        guard #available(iOS 11.0, *) else {
            sendError(command: command, result: "close is only available on iOS 13+")
            return
        }
        DispatchQueue.main.async {
            guard let session = self.ndefController?.session else {
                self.sendError(command: command, result: "no session to terminate")
                return
            }

            session.invalidate()
            self.nfcController = nil
            self.sendSuccess(command: command, result: "Session Ended!")
        }
    }

    @objc(channel:)
    func channel(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            print("Creating NDEF Channel")
            self.channelCommand = command
            self.sendThroughChannel(message: "Did create NDEF Channel")
        }
    }

    func sendThroughChannel(message: String) {
        guard let command: CDVInvokedUrlCommand = self.channelCommand else {
            print("Channel is not set")
            return
        }
        guard let response = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: message) else {
            print("sendThroughChannel Did not create CDVPluginResult")
            return
        }

        response.setKeepCallbackAs(true)
        commandDelegate!.send(response, callbackId: command.callbackId)
    }

    func sendThroughChannel(jsonDictionary: [AnyHashable: Any]) {
        guard let command: CDVInvokedUrlCommand = self.channelCommand else {
            print("Channel is not set")
            return
        }
        guard let response = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: jsonDictionary) else {
            print("sendThroughChannel Did not create CDVPluginResult")
            return
        }

        response.setKeepCallbackAs(true)
        commandDelegate!.send(response, callbackId: command.callbackId)

//        self.sendSuccessWithResponse(command: command, result: message)
    }

    @objc(enabled:)
    func enabled(command: CDVInvokedUrlCommand) {
        guard #available(iOS 11.0, *) else {
            sendError(command: command, result: "enabled is only available on iOS 11+")
            return
        }
        let enabled = NFCReaderSession.readingAvailable
        sendSuccess(command: command, result: enabled)
    }
}

extension String {
    func split(by length: Int) -> [String] {
        var startIndex = self.startIndex
        var results = [Substring]()

        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }

        return results.map { String($0) }
    }
}

func flattenedArray(array:[Data]) -> [UInt8] {
    var myArray = [UInt8]()
    for element in array {
        myArray.append(contentsOf: element)
    }
    return myArray
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
