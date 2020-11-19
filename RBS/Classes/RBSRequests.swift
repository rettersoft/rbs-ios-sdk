//
//  SignInAnonymRequest.swift
//  RBS
//
//  Created by Baran Baygan on 19.11.2020.
//

import Foundation
import ObjectMapper

class GetAnonymTokenRequest : Mappable {
    
    
    required init?(map: Map) { }
    
    init() {
    
    }
    
    func mapping(map: Map) {
//        phoneNumber <- map["phoneNumber"]
//        email <- map["email"]
//        password <- map["password"]
    }
}

class RefreshTokenRequest : Mappable {

    var refreshToken: String?
    
    required init?(map: Map) { }
    
    init() {
    
    }
    
    func mapping(map: Map) {
        refreshToken <- map["refreshToken"]
    }
}

class ExecuteActionRequest : Mappable {
    
    var accessToken:String?
    var actionName:String?
    var payload:String?
    
    
    required init?(map: Map) { }
    
    init() {
    
    }
    
    func mapping(map: Map) {
        accessToken <- map["accessToken"]
        actionName <- map["actionName"]
        payload <- map["payload"]
    }
}
