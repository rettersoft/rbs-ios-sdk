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
    
    let rbs = RBS(config: RBSConfig(projectId: "36229bb229af4983a4bc6ecded2a68d2", region: .euWest1Beta))
    
    lazy var testLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .boldSystemFont(ofSize: 15)
        label.numberOfLines = 0
        return label
    }()
    
    lazy var socketButton: UIButton = {
        let button = UIButton()
        button.setTitle("Socket Button", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 25
        button.layer.borderWidth = 1
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        rbs.delegate = self
        
        view.addSubview(testLabel)
        NSLayoutConstraint.activate([testLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     testLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 180),
                                     testLabel.widthAnchor.constraint(equalToConstant: 200),
                                     testLabel.heightAnchor.constraint(equalToConstant: 180)])
        
        view.addSubview(socketButton)
        NSLayoutConstraint.activate([socketButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     socketButton.bottomAnchor.constraint(equalTo: testLabel.topAnchor, constant: -10),
                                     socketButton.widthAnchor.constraint(equalToConstant: 150),
                                     socketButton.heightAnchor.constraint(equalToConstant: 50)])
        
        socketButton.addTarget(self, action: #selector(socketButtonTapped), for: .touchUpInside)
    }
    
    @objc func socketButtonTapped() {
        rbs.send(action: "rbs.process.request.START",
                 data: ["processId": "MERT_TEST"],
                 headers: [:],
                 onSuccess: { result in
                    print("Result: \(result)")

                 },
                 onError: { error in
                    print("Error Result: \(error)")
                 })
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    @IBAction func testButtonTapped(_ sender: Any) {
        
//        rbs.generateGetActionUrl(action: "rbs.businessuserauth.get.LOGIN",
//                                 data: [
//                                    "email": "email@test.com",
//                                    "password": "password"
//                                 ]) { url in
//            print("URL \(url)")
//        } onError: { err in
//
//        }

        
        rbs.send(action: "rbs.process.request.START",
                 data: ["processId": "MERT_TEST"],
                 headers: [:],
                 onSuccess: { result in
                    print("Result: \(result)")

                 },
                 onError: { error in
                    print("Error Result: \(error)")
                 })
        
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
        
        
    }
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
    func socketDisconnected() {
        print("disconnected")
        testLabel.textColor = .red
        testLabel.text = "Disconnected!"
    }
    
    func socketConnected() {
        print("connected")
        testLabel.textColor = .green
        testLabel.text = "Connected!"
    }
    
    func socketEventFired(payload: [String : Any]) {
        print("event", payload)
        testLabel.textColor = .blue
        if let text = payload["text"] as? String {
            testLabel.text = text
        }
    }
    
    func socketErrorOccurred(error: Error?) {
        print("errorrr: \(error?.localizedDescription)")
    }
    
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
