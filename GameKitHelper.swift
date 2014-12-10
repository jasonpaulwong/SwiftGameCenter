//
//  GameKitHelper.swift
//  CatRaceStarter
//
//  Created by Jason Wong on 11/11/14.
//  Copyright (c) 2014 Raywenderlich. All rights reserved.
//

import GameKit
import Foundation

let PresentAuthenticationViewController : NSString = "present_authentication_view_controller"
let LocalPlayerIsAuthenticated : NSString = "local_player_authenticated"
    
/* For singleton pattern */
private let _GameKitHelperSharedInstace = GameKitHelper()

protocol GameKitHelperDelegate {
    func matchStarted()
    func matchEnded()
    func match(match:GKMatch, didReceiveData data: NSData!, fromPlayer playerID: NSString!)
}

class GameKitHelper : NSObject, GKMatchmakerViewControllerDelegate, GKMatchDelegate {
    var _enableGameCenter : Bool
    var _matchStarted : Bool
    var _match : GKMatch!
    var _delegate : GameKitHelperDelegate?
    var authenticationViewController: UIViewController?
    var lastError : NSError?
    var playersDict : NSMutableDictionary?

    class var SharedGameKitHelper:GameKitHelper {
        return _GameKitHelperSharedInstace
    }
    
    override init() {
        self._enableGameCenter = true
        self._matchStarted = false
        super.init()
    }
    
    func authenticateLocalPlayer() {

        var localPlayer = GKLocalPlayer.localPlayer()
        
        if(localPlayer.authenticated) {
            NSNotificationCenter.defaultCenter().postNotificationName(LocalPlayerIsAuthenticated, object:nil)
            return
        }
        
        localPlayer.authenticateHandler = {(viewController : UIViewController!, error : NSError!) -> Void in

            if(error != nil) {
                self.setLastError(error)
            }
            if(viewController != nil) {
                self.setAuthenticationViewController(viewController)
            }
            else if(GKLocalPlayer.localPlayer().authenticated) {
                self._enableGameCenter = true
                    NSNotificationCenter.defaultCenter().postNotificationName(LocalPlayerIsAuthenticated, object: nil)
            }
            else {
                self._enableGameCenter = false
            }
            
        }

    }
    
    func setAuthenticationViewController(authViewController:UIViewController!) {
        if(authViewController != nil) {
            authenticationViewController = authViewController
            NSNotificationCenter.defaultCenter().postNotificationName(PresentAuthenticationViewController, object:self)
        }

    }
    
    func setLastError(error: NSError) {

        lastError = error.copy() as? NSError
        
        if((lastError) != nil) {
            NSLog("GamerKitHelp ERROR: \(lastError?.userInfo?.description)")
        }

    }

    func findMatchWithMinPlayers(minPlayers:Int, maxPlayers:Int, viewController:UIViewController, delegate:GameKitHelperDelegate) {

        if(!_enableGameCenter) {
           return;
        }

        _matchStarted = false
        self._match = nil
        _delegate = delegate
        viewController.dismissViewControllerAnimated(false, completion: nil)

        let request = GKMatchRequest()
        request.minPlayers = minPlayers
        request.maxPlayers = maxPlayers

        let mmvc = GKMatchmakerViewController(matchRequest: request)
        mmvc.matchmakerDelegate = self
        viewController.presentViewController(mmvc, animated: true, completion: nil)
    }
    
    func lookupPlayers() {
        println("Looking up \(_match.playerIDs.count) players...")

        GKPlayer.loadPlayersForIdentifiers(_match?.playerIDs) { (players, error) -> Void in
            if error != nil {
                println("Error retrieving player info: \(error.localizedDescription)")
                self._matchStarted = false
                self._delegate?.matchEnded()
            }
            else {
                self.playersDict = NSMutableDictionary(capacity: players.count)
                for player in players {
                    println("Found player: \(player.alias)")
                    self.playersDict?.setObject(player, forKey: player.playerID)
                }
            }
            self.playersDict?.setObject(GKLocalPlayer.localPlayer(), forKey: GKLocalPlayer.localPlayer().playerID)
            self._matchStarted = true
            self._delegate?.matchStarted()
        }
    }
    
    /* For protocol GKMatchmakerViewControllerDelegate */
    func matchmakerViewControllerWasCancelled(viewController:GKMatchmakerViewController) {
        viewController.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func matchmakerViewController(viewController: GKMatchmakerViewController!, didFailWithError error:NSError!) {
        viewController.dismissViewControllerAnimated(true, completion: nil)
        NSLog("Error finding match: %@", error.localizedDescription)
    }
    
    func matchmakerViewController(viewController: GKMatchmakerViewController!,
        didFindMatch match: GKMatch!) {

        viewController.dismissViewControllerAnimated(true, completion: nil)
        self._match = match
        match.delegate = self
        if(!_matchStarted && match.expectedPlayerCount==0) {
            NSLog("Ready to start match")
            self.lookupPlayers()
        }
    }
    
    /* For protocol GKMatchDelegate */
    func match(match: GKMatch!, didReceiveData data: NSData!, fromPlayer playerID: NSString!) {
        if(_match != match) {
            return
        }
        _delegate?.match(match, didReceiveData: data, fromPlayer: playerID)
    }
    
    func match(match: GKMatch!,  player: String!, didChangeState state: GKPlayerConnectionState) {

        if(_match != match) {
            return
        }
        switch(state) {
            case GKPlayerConnectionState.StateConnected:
                if(!_matchStarted && match.expectedPlayerCount == 0) {
                    NSLog("Ready to start match!")
                    self.lookupPlayers()
                }
            case GKPlayerConnectionState.StateDisconnected:
                NSLog("Player disconnected!")
                _matchStarted = false
                _delegate?.matchEnded()
            default:
                break
        }
    }
    
    func match(match: GKMatch!, connectionWithPlayerFailed:String!, withError error:NSError!) {
        if(_match != match) {
            return
        }
        NSLog("Failed to connect to player with error: %@", error.localizedDescription)
        _matchStarted = false
        _delegate?.matchEnded()

    }
    
    func match(match: GKMatch!, didFailWithError error: NSError!) {
        if(_match != match) {
            return
        }
        NSLog("Match failed with error: %@", error.localizedDescription)
        _matchStarted = false
        _delegate?.matchEnded()
    }
}