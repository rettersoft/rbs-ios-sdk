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
    
    let testCustomToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJwcm9qZWN0SWQiOiI3YjdlY2VjNzIxZDU0NjI5YmVkMWQzYjFhZWMyMTBlOCIsImlkZW50aXR5IjoicmJzLmJ1c2luZXNzdXNlcmF1dGgiLCJpYXQiOjE2MDYyNDI1NzMsImV4cCI6MTYxNjI0MjU3Mn0.Pu_FTXaOwxRq7mnWurF2V3VtyVscxnxN-33M3thTlxk"
    
    let rbs = RBS(config: RBSConfig(projectId: "7b7ecec721d54629bed1d3b1aec210e8"))
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
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
        
        rbs.send(action: "rbs.basicauth.request.VALIDATE_OTP",
                 data: [
                    "msisdn": "905305553322",
                    "otp": "141414"
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
}

extension ViewController : RBSClientDelegate {
    func rbsClient(client: RBS, authStatusChanged toStatus: RBSClientAuthStatus) {
        print("RBS authStatusChanged to \(toStatus)")
    }
}



