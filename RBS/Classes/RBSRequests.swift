//
//  SignInAnonymRequest.swift
//  RBS
//
//  Created by Baran Baygan on 19.11.2020.
//

import Foundation
import ObjectMapper
import Moya

class GetAnonymTokenRequest : Mappable {
    
    var projectId: String?
    
    required init?(map: Map) { }
    
    init() {
    
    }
    
    func mapping(map: Map) {
        projectId <- map["projectId"]
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

class AuthWithCustomTokenRequest : Mappable {

    var customToken: String?
    
    required init?(map: Map) { }
    
    init() {
    
    }
    
    func mapping(map: Map) {
        customToken <- map["customToken"]
    }
}

class ExecuteActionRequest : Mappable {
    
    var projectId: String?
    var accessToken:String?
    var actionName:String?
    var payload: [String:Any]?
    var headers: [String:String]?
    var culture: String?
    var classID: String?
    var instanceID: String?
    var keyValue: (key: String, value: String)?
    var httpMethod: Moya.Method?
    var method: String?
    var queryString: [String: Any]?
    
    required init?(map: Map) { }
    
    init() {
    
    }
    
    func mapping(map: Map) {
        projectId <- map["projectId"]
        accessToken <- map["accessToken"]
        actionName <- map["actionName"]
        payload <- map["payload"]
        headers <- map["headers"]
        culture <- map["culture"]
    }
}
