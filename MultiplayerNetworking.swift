/**
  * MultiplayerNetworking.swift
  * CatRaceStarter
  *
  * Created by Jason Wong on 11/20/14.
  * Copyright (c) 2014 Raywenderlich. All rights reserved.
*/

import Foundation
import GameKit

let playerIDKey = "PlayerID"
let randomNumberKey = "randomNumber"

protocol MultiplayerNetworkingProtocol {
    func matchEnded()
    func setCurrentPlayerIndex(index : Int)
    func movePlayerAtIndex(index : Int)
    func gameOver(player1Won : Bool)
}

enum MessageType : Int {
    case kMessageTypeRandomNumber = 0
    case kMessageTypeGameBegin
    case kMessageTypeMove
    case kMessageTypeGameOver
}

enum GameState : Int {
    case kGameStateWaitingForMatch = 0
    case kGameStateWaitingForRandomNumber
    case kGameStateWaitingForStart
    case kGameStateActive
    case kGameStateDone
}

struct Message {
    var messageType : MessageType
}

struct MessageRandomNumber {
    var message : Message
    var randomNumber : UInt32
}

struct MessageGameBegin {
    var message : Message
}

struct MessageMove {
    var message : Message
}

struct MessageGameOver {
    var message : Message
    var player1Won : Bool
}

class MultiplayerNetworking : NSObject, GameKitHelperDelegate {
    var delegate : MultiplayerNetworkingProtocol?
    var _ourRandomNumber : UInt32!
    var _gameState : GameState?
    var _isPlayer1 = false
    var _receivedAllRandomNumbers = false
    var _orderOfPlayers : NSMutableArray!

    override init() {
        super.init()
        
        _ourRandomNumber = arc4random()
        _gameState = GameState.kGameStateWaitingForMatch
        _orderOfPlayers = NSMutableArray()
        
        var dict = ["\(playerIDKey)":"\(GKLocalPlayer.localPlayer().playerID)", "\(randomNumberKey)":"\(_ourRandomNumber)"]
        _orderOfPlayers.addObject(dict)
    }
    
    func sendRandomNumber() {
        var message = Message(messageType: MessageType.kMessageTypeRandomNumber)
        var MessageRandomNum =  MessageRandomNumber(message: message, randomNumber: _ourRandomNumber!)
        let data = NSData(bytes: &MessageRandomNum, length: sizeof(MessageRandomNumber))
        self.sendData(data)
    }
    
    func sendGameBegin() {
        var message = Message(messageType: MessageType.kMessageTypeGameBegin)
        var MessageGameBeg = MessageGameBegin(message: message)
        var data = NSData(bytes: &MessageGameBeg, length: sizeof(MessageGameBegin))
        self.sendData(data)
    }
    
    func sendGameEnd(player1Won : Bool) {
        var message = Message(messageType: MessageType.kMessageTypeGameOver)
        var messageGameOver = MessageGameOver(message: message, player1Won: player1Won)
        var data = NSData(bytes: &messageGameOver, length: sizeof(MessageGameOver))
        self.sendData(data)
    }
    
    func sendMove() {
        var message = Message(messageType: MessageType.kMessageTypeMove)
        var messageMove = MessageMove(message: message)
        var data = NSData(bytes: &messageMove, length: sizeof(MessageMove))
        self.sendData(data)
    }
    
    func sendData(data : NSData) {
        var error : NSError?
        
        let gameKitHelper = GameKitHelper.SharedGameKitHelper
        var success = gameKitHelper._match.sendDataToAllPlayers(data, withDataMode: GKMatchSendDataMode.Reliable, error: &error)
        
        if(success == false) {
            println("Error sending data: \(error?.localizedDescription)")
            self.matchEnded()
        }
    }
    
    func indexForLocalPlayer() -> Int {
        var playerID = GKLocalPlayer.localPlayer().playerID
        return self.indexForPlayerWithId(playerID)
    }
    
    func indexForPlayerWithId(playerId : String) -> Int {
        var index = -1
        _orderOfPlayers.enumerateObjectsUsingBlock( {object, ind, stop in
            
            var pId = object[playerIDKey] as String
            
            if(pId == playerId) {
                index = ind
                stop.initialize(true)
            }
        })
        return index
    }
    
    func setCurrentPlayerIndex(index : Int) {
        
    }
    
    func tryStartGame() {
        if(_isPlayer1 && _gameState == GameState.kGameStateWaitingForStart) {
            _gameState = GameState.kGameStateActive
            self.sendGameBegin()
            self.delegate?.setCurrentPlayerIndex(0)
        }
        
    }
    
    func matchStarted() {
        println("Match has started successfully")
        if(_receivedAllRandomNumbers) {
            _gameState = GameState.kGameStateWaitingForStart
        }
        else {
            _gameState = GameState.kGameStateWaitingForRandomNumber;

        }
        self.sendRandomNumber()

        self.tryStartGame()

    }

    func matchEnded() {
        println("Match has ended")
        delegate?.matchEnded()
    }
    
    func match(match:GKMatch, didReceiveData data: NSData!, fromPlayer playerID: NSString!) {
        
        let message = UnsafePointer<Message>(data.bytes).memory

        if(message.messageType == MessageType.kMessageTypeRandomNumber) {
            let messageRandomNumber = UnsafePointer<MessageRandomNumber>(data.bytes).memory
            
            println("Received random number: \(messageRandomNumber.randomNumber)")
            
            var tie = false
            
            if(messageRandomNumber.randomNumber == _ourRandomNumber) {
                println("Tie")
                tie = true
                _ourRandomNumber = arc4random()
                self.sendRandomNumber()
            }
            else {
                var dictionary = ["\(playerIDKey)":"\(playerID)", "\(randomNumberKey)":"\(messageRandomNumber.randomNumber)"]
                self.processReceivedRandomNumber(dictionary)
            }
            
            if(_receivedAllRandomNumbers) {
                _isPlayer1 = self.isLocalPlayerPlayer1()
            }
            
            if(!tie && _receivedAllRandomNumbers) {
                if(_gameState == GameState.kGameStateWaitingForRandomNumber) {
                    _gameState = GameState.kGameStateWaitingForStart
                }
                self.tryStartGame()
            }
        }
        else if(message.messageType == MessageType.kMessageTypeGameBegin) {
            println("Begin game message received")
            _gameState = GameState.kGameStateActive
            self.delegate?.setCurrentPlayerIndex(self.indexForLocalPlayer())
        }
        else if(message.messageType == MessageType.kMessageTypeMove) {
            println("Move message received")
            let messageMove = UnsafePointer<MessageMove>(data.bytes).memory
            self.delegate?.movePlayerAtIndex(self.indexForPlayerWithId(playerID))
        }
        else if(message.messageType == MessageType.kMessageTypeGameOver) {
            println("Game over message received")
            let messageGameOver = UnsafePointer<MessageGameOver>(data.bytes).memory
            self.delegate?.gameOver(messageGameOver.player1Won)
        }
    }
    
    func processReceivedRandomNumber(randomNumberDetails:NSDictionary) {
        
        if(_orderOfPlayers.containsObject(randomNumberDetails)) {
            _orderOfPlayers.removeObjectAtIndex(_orderOfPlayers.indexOfObject(randomNumberDetails))
        }
        _orderOfPlayers.addObject(randomNumberDetails)
        
        var sortByRandomNumber = NSSortDescriptor(key:randomNumberKey, ascending: false)
        var sortDescriptors = [sortByRandomNumber]
        _orderOfPlayers.sortUsingDescriptors(sortDescriptors)
        
        if(self.allRandomNumbersAreReceived()) {
            _receivedAllRandomNumbers = true
        }
    }
    
    func allRandomNumbersAreReceived() -> Bool {
        var receivedRandomNumbers = NSMutableArray()
        
        for dict in _orderOfPlayers {
            receivedRandomNumbers.addObject(dict[randomNumberKey] as String)
        }
        
        var set = NSSet()
        
        var arrayOfUniqueRandomNumbers = set.setByAddingObjectsFromArray(receivedRandomNumbers).allObjects
        
        if(arrayOfUniqueRandomNumbers.count == GameKitHelper.SharedGameKitHelper._match.playerIDs.count + 1) {
            return true
        }
        return false
    }
    
    func isLocalPlayerPlayer1() -> Bool {
        var dictionary = _orderOfPlayers[0] as NSDictionary
        if((dictionary[playerIDKey] as String) ==  (GKLocalPlayer.localPlayer().playerID)) {
            println("I am player 1")
            return true
        }
        return false
    }
}