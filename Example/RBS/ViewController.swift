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
    
    let rbs = RBS(config: RBSConfig(projectId: "69ec1ef0039b4332b3e102f082a98ec2", region: .euWest1Beta))
    
    var cloudObject: RBSCloudObject?
    
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
        cloudObject = nil
    }
    
    @IBAction func searchProducts(_ sender: Any) {
        // MARK: - Get Cloud Object
        let cloudOpts = RBSCloudObjectOptions(classID: "TestClass", instanceID: "01FQXSX0S23GQA59ZS45H66YGC", useLocal: true)
//        let cloudOpts = RBSCloudObjectOptions(classID: "User", keyValue: ("username", "loodos2"))
        
        rbs.getCloudObject(with: cloudOpts) { [weak self] (newObject) in
            print("--- Cloud Object Created ---")
            self?.cloudObject = newObject
        } onError: { (error) in
            print(error)
        }
    }
    
    @IBAction func loginBusinessUser(_ sender: Any) {
        guard let object = cloudObject else {
            showCloudAlert()
            return
        }
        
        // MARK: - Get Objects States
        
        
        
        object.state?.user.subscribe { (data) in
            print("---User State ->", data)
        } onError: { (error) in
            print("---User State Error ->", error)
        }
        
        object.state?.role.subscribe { (data) in
            print("---RoleState State ->", data)
        } onError: { (error) in
            print("---Role State Error ->", error)
        }
        
        object.state?.public.subscribe { (data) in
            print("---Public State ->", data)
        } onError: { (error) in
            print("---Public State Error ->", error)
        }
        
    }
    @IBAction func testAction(_ sender: Any) {
        guard let object = cloudObject else {
            showCloudAlert()
            return
        }
        
        // MARK: - Call Method
        
        object.call(
            with: RBSCloudObjectOptions(method: "sayHello")
        ) { (methodResponse) in
            
            let json = try? JSONSerialization.jsonObject(with: methodResponse.body!, options: [])
            print(json)
//
//            object.call(with: RBSCloudObjectOptions(method: "updateProfile", body: ["username": "loodos2"])) { (responseX) in
//                if let firstResponseX = responseX.first,
//                   let dataX = firstResponseX as? Data {
//                    let json = try? JSONSerialization.jsonObject(with: dataX, options: [])
//                    print("---Update Response ->", json)
//                }
//            } onError: { (error) in
//                print("---Method Error ->", error)
//            }
            
        } onError: { (error) in
            print("---Method Error ->", error)
            
//            let json = try? JSONSerialization.jsonObject(with: error.body!, options: [])
//            print(json)
        }
    }
    
    private func showCloudAlert() {
        let alert = UIAlertController(title: "Warning", message: "Please firstly get the cloud object.", preferredStyle: .alert)
        let OKAction = UIAlertAction(title: "OK", style: .default)
        alert.addAction(OKAction)
        present(alert, animated: true)
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
