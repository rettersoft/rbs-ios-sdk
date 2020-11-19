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

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let rbs = RBS(clientType: .user(userType: ""))
        
        try! rbs.send(action: "rbs.oms.request.CREATE_ORDER",
                      data: ["":""],
                      onSuccess: { result in
                        print("Result: \(result)")
                      },
                      onError: { error in
                        
                      })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

