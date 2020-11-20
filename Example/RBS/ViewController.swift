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

    let testCustomToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjbGllbnRJZCI6InJicy51c2VyLmVuZHVzZXIiLCJhbm9ueW1vdXMiOmZhbHNlLCJwcm9qZWN0SWQiOiI3YjdlY2VjNzIxZDU0NjI5YmVkMWQzYjFhZWMyMTBlOCIsInVzZXJJZCI6Im15VXNlcklkMSIsInRpbWVzdGFtcCI6MTYwNTgwOTkwMjAxMiwic2VydmljZUlkIjoidGVzdHNlcnZpY2UiLCJpYXQiOjE2MDU4MDk5MDIsImV4cCI6MTYwNzEwNTkwMn0.O1xaYQzdG7awq_jt5PxrezKTtR7OG4BEa0AxOvpTt60"
    
    let rbs = RBS(clientType: .user(userType: ""))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        
        rbs.send(action: "rbs.oms.request.CREATE_ORDER",
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

    @IBAction func signInWithCustomToken(_ sender: Any) {
        rbs.authenticateWithCustomToken(testCustomToken)
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



