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
    
    let rbs = RBS(config: RBSConfig(projectId: "1ae2cad9191e60d2e58ca4e4303d3e80"))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        rbs.delegate = self
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    @IBAction func testButtonTapped(_ sender: Any) {
        
        rbs.send(action: "rbs.businessuserauth.request.LOGIN",
                 data: [
                    "email": "email@test.com",
                    "password": "password"
                 ],
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
    @IBAction func signoutTapped(_ sender: Any) {
        rbs.signOut()
    }
    @IBAction func searchProducts(_ sender: Any) {
        
//        rbs.send(action: "rbs.product.request.GET_CATEGORIES",
//                 data: [:],
//                 onSuccess: { result in
//                    print("Result: \(result)")
//                 },
//                 onError: { error in
//                    print("Error Result: \(error)")
//                 })
        
        rbs.send(action: "rbs.catalog.request.SEARCH",
                 data: [:],
                 onSuccess: { result in
                    print("Result: \(result)")
                 },
                 onError: { error in
                    print("Error Result: \(error)")
                 })
        
        //        rbs.send(action: "rbs.product.request.SEARCH",
        //                 data: [
        //                    "searchTerm": "dove",
        //                    "filters": [
        //                        ["filterId": "categories", "filterValues": ["BPC"]]
        //                    ]
        //                 ],
        //                 onSuccess: { result in
        //                    print("Result: \(result)")
        //                 },
        //                 onError: { error in
        //                    print("Error Result: \(error)")
        //                 })
        
        
        //        rbs.send(action: "rbs.product.request.AGGREGATE",
        //                 data: [
        //                    "searchTerm": "dove"
        //                 ],
        //                 onSuccess: { result in
        //                    print("Result: \(result)")
        //                 },
        //                 onError: { error in
        //                    print("Error Result: \(error)")
        //                 })
        
    }
    @IBAction func loginBusinessUser(_ sender: Any) {
        rbs.send(action: "rbs.businessuserauth.request.LOGIN",
                 data: [
                    "email": "email@test.com",
                    "password": "password"
                 ],
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
