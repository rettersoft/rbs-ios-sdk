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
    
    let rbs = RBS(config: RBSConfig(projectId: "048dbf4ab878487895129a0c778e7996", region: .euWest1Beta))
    
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
        
        //        rbs.generateGetActionUrl(action: "rbs.businessuserauth.get.LOGIN",
        //                                 data: [
        //                                    "email": "email@test.com",
        //                                    "password": "password"
        //                                 ]) { url in
        //            print("URL \(url)")
        //        } onError: { err in
        //
        //        }
        
        
        //        rbs.send(action: "rbs.businessuserauth.request.LOGIN",
        //                 data: [
        //                    "email": "email@test.com",
        //                    "password": "password"
        //                 ],
        //                 onSuccess: { result in
        //                    print("Result: \(result)")
        //
        //                    if let serviceResponse = result.first as? [String:Any],
        //                       let resp = serviceResponse["response"] as? [String:Any],
        //
        //                       let customToken = resp["customToken"] as? String {
        //                        self.rbs.authenticateWithCustomToken(customToken)
        //                    }
        //                 },
        //                 onError: { error in
        //                    print("Error Result: \(error)")
        //                 })
        
    }
    @IBAction func signoutTapped(_ sender: Any) {
        rbs.signOut()
    }
    @IBAction func searchProducts(_ sender: Any) {
        rbs.send(action: "rbs.catalog.get.SEARCH",
                 data: ["searchTerm": "hardal"],
                 headers: ["deneme": "baran"],
                 onSuccess: { result in
                    print("SEARCH Result: \(result)")
                 },
                 onError: { error in
                    print("SEARCH Error Result: \(error)")
                 })
        //
        //        rbs.send(action: "rbs.catalog.get.SEARCH",
        //                 data: ["searchTerm": "hardal"],
        //                 onSuccess: { result in
        //                    print("SEARCH Result success")
        //                 },
        //                 onError: { error in
        //                    print("SEARCH Error Result: \(error)")
        //                 })
        //
        //
        //                rbs.send(action: "rbs.catalog.request.GET_CATEGORIES",
        //                         data: ["searchTerm": "hardal"],
        //                         onSuccess: { result in
        //                            print("GET_CATEGORIES Result success")
        //                         },
        //                         onError: { error in
        //                            print("GET_CATEGORIES Error Result: \(error)")
        //                         })
                
        rbs.getCloudObject(classID: "TEST", instanceID: "01FKVP097BGXJ7J5MEXJ1HXSN3") { [weak self] (newObject) in
            self?.userObject = newObject
            newObject.userState.subscribe { (data) in
                print("---XXXX", data)
            } errorFired: { (error) in
                print("---XXX", error)
            }

        } onError: { (error) in
            print(error)
        }

//        userObject.roleState.subscribe { (data) in
//            print("---XXXX", data)
//        } errorFired: { (error) in
//            print("---XXX", error)
//        }
    }
    
    var userObject: RBSCloudObject?
    
    @IBAction func loginBusinessUser(_ sender: Any) {
        rbs.send(action: "rbs.businessuserauth.request.LOGIN",
                 data: [
                    "email": "email@test.com",
                    "password": "password"
                 ],
                 headers: ["deneme": "baran"],
                 onSuccess: { result in
                    print("Result: \(result)")
                    
                    if let serviceResponse = result.first as? [String:Any],
                       let resp = serviceResponse["response"] as? [String:Any],
                       let customToken = resp["customToken"] as? String {
                        self.rbs.authenticateWithCustomToken(customToken)
                    }
                 },
                 onError: { error in
                    print("Error Result: \(error)")
                 })
    }
    @IBAction func testAction(_ sender: Any) {
        
        
        
        
        rbs.send(action: "rbs.wms.request.GET_OPTION",
                 data: ["optionId":"MAIN"],
                 headers: nil,
                 onSuccess: { result in
                    print("Result: \(result)")
                 },
                 onError: { error in
                    print("Error Result: \(error)")
                 })
        
        
        
        
        
        //        rbs.send(action: "rbs.crm.request.GET_MY_PROFILE",
        //                 data: [:],
        //                 onSuccess: { result in
        //                    print("Result: \(result)")
        //                 },
        //                 onError: { error in
        //                    print("Error Result: \(error)")
        //                 })
        
        //        rbs.send(action: "rbs.crm.request.UPDATE_PROFILE",
        //                 data: ["firstName":"Baran", "lastName": "Baygan"],
        //                 onSuccess: { result in
        //                    print("Result: \(result)")
        //                 },
        //                 onError: { error in
        //                    print("Error Result: \(error)")
        //                 })
        
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
