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
        
    override func viewDidLoad() {
        super.viewDidLoad()
        rbs.delegate = self
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
        rbs.send(action: "rbs.catalog.get.SEARCH",
                 data: ["searchTerm": "hardal"],
                 headers: ["deneme": "baran"],
                 onSuccess: { result in
            print("SEARCH Result: \(result)")
        }, onError: { error in
            print("SEARCH Error Result: \(error)")
        })
    }
    @IBAction func testAction(_ sender: Any) {
        rbs.send(action: "rbs.wms.request.GET_OPTION",
                 data: ["optionId":"MAIN"],
                 headers: nil,
                 onSuccess: { result in
            print("Result: \(result)")
        }, onError: { error in
            print("Error Result: \(error)")
        })
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
