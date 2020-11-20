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

    let rbs = RBS(clientType: .user(userType: ""))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        
        try! rbs.send(action: "rbs.oms.request.CREATE_ORDER",
                      data: ["":""],
                      onSuccess: { result in
                        print("Result: \(result)")
                      },
                      onError: { error in
                        
                      })
        
        
        rbs.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func testButtonTapped(_ sender: Any) {
        
        try! rbs.send(action: "rbs.oms.request.CREATE_ORDER",
                      data: ["":""],
                      onSuccess: { result in
                        print("Result: \(result)")
                      },
                      onError: { error in
                        
                      })
        
    }
    @IBAction func signoutTapped(_ sender: Any) {
        rbs.signOut()
    }
}

extension ViewController : RBSClientDelegate {
    func rbsClient(client: RBS, authStatusChanged toStatus: RBSClientAuthStatus) {
        print("RBS authStatusChanged to \(toStatus)")
    }
}



