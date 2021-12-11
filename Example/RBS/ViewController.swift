//
//  ViewController.swift
//  RBS
//
//  Created by baranbaygan on 11/19/2020.
//  Copyright (c) 2020 baranbaygan. All rights reserved.
//

import UIKit
import RBS

class ViewController: UIViewController {
    
    let rbs = RBS(config: RBSConfig(projectId: "6eedd7ca16be4ae8982451fdfdba7e15", region: .euWest1Beta))
    
    var cloudObject: RBSCloudObject?
//    var cloudItem = RBSCloudObjectItem(classID: "ChatRoom", instanceID: "01FPJX38KE3G8HBQ49VMF2KC3C")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        rbs.delegate = self
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    @IBAction func testButtonTapped(_ sender: Any) {
        
        let url = rbs.generatePublicGetActionUrl(action: "rbs.businessuserauth.get.LOGIN", data: [
            "email": "email@test.com",
            "password": "password"
        ])
        
        print("URL is \(url)")
    }
    @IBAction func signoutTapped(_ sender: Any) {
        rbs.signOut()
    }

    @IBAction func searchProducts(_ sender: Any) {
        // MARK: - Get Cloud Object
        
        rbs.getCloudObject(with: RBSCloudObjectOptions(classID: "ChatRoom", instanceID: "01FPJX38KE3G8HBQ49VMF2KC3C")) { [weak self] (newObject) in
            print("--- Cloud Object Created ---")
            self?.cloudObject = newObject
        } onError: { (error) in
            print(error)
        }
    }
        
    @IBAction func loginBusinessUser(_ sender: Any) {
        
        // MARK: - Get Objects States
        
        if let object = cloudObject {
            object.state.user.subscribe { (data) in
                print("---User State ->", data)
            } errorFired: { (error) in
                print("---User State Error ->", error)
            }

            object.state.role.subscribe { (data) in
                print("---RoleState State ->", data)
            } errorFired: { (error) in
                print("---Role State Error ->", error)
            }

            object.state.public.subscribe { (data) in
                print("---Public State ->", data)
            } errorFired: { (error) in
                print("---Public State Error ->", error)
            }
        }
        
    }
    @IBAction func testAction(_ sender: Any) {
        
        
        if let object = cloudObject {
            
            // MARK: - Call Method
            
            object.call(
                with: RBSCloudObjectOptions(method: "sayHello")
            ) { (response) in
                if let firstResponse = response.first,
                   let data = firstResponse as? Data {
                    let json = try? JSONSerialization.jsonObject(with: data, options: [])
                    print("---Method Response ->", json)
                }
            } errorFired: { (error) in
                print("---Method Error ->", error)
            }
            
            // MARK: - Get State via REST
            
//            object.getState(
//                with: cloudItem
//            ) { (response) in
//                if let firstResponse = response.first,
//                   let data = firstResponse as? Data {
//                    let json = try? JSONSerialization.jsonObject(with: data, options: [])
//                    print("---GETSTATE Response ->", json)
//                }
//            } errorFired: { (error) in
//                print("---GETSTATE Error ->", error)
//            }
        }
    }
}

extension ViewController : RBSClientDelegate {
    func rbsClient(client: RBS, authStatusChanged toStatus: RBSClientAuthStatus) {
        
        //        switch toStatus {
        //        case .signedIn(let user):
        //            break
        //        case .signedInAnonymously(let user):
        //            break
        //        case .authenticating:
        //            break
        //        case .signedOut:
        //            break
        //        }
        
        print("RBS authStatusChanged to \(toStatus)")
    }
}
