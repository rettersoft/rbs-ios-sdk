//
//  RBSResponses.swift
//  RBS
//
//  Created by Baran Baygan on 19.11.2020.
//

import Foundation
import Moya


class GetTokenResponse: Decodable {
    
    var accessToken: String?
    var refreshToken: String?
    
    
    private enum CodingKeys: String, CodingKey { case accessToken, refreshToken }
    
    var tokenData:RBSTokenData? {
        get {
            if let accessToken = self.accessToken, let refreshToken = self.refreshToken {
                return RBSTokenData(JSON: [
                    "isAnonym": true,
                    "accessToken": accessToken,
                    "refreshToken": refreshToken
                ])
            } else {
                return nil
            }
            
        }
    }
}


class ExecuteActionResponse: Decodable {
    
    var accessToken: String?
    var refreshToken: String?
    
    
    private enum CodingKeys: String, CodingKey { case accessToken, refreshToken }
    
    var tokenData:RBSTokenData? {
        get {
            if let accessToken = self.accessToken, let refreshToken = self.refreshToken {
                return RBSTokenData(JSON: [
                    "isAnonym": true,
                    "accessToken": accessToken,
                    "refreshToken": refreshToken
                ])
            } else {
                return nil
            }
            
        }
    }
}


enum NetworkError : Error {
    case connection_lost
}


class BaseErrorResponse: Decodable, Error {
    
    var code: Int? // unknown
    var httpStatusCode: Int? // unknown
    
    private enum CodingKeys: String, CodingKey { case code, message, httpStatusCode }
    
    required init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.httpStatusCode = try? container.decode(Int.self, forKey: .httpStatusCode)
            self.code = try? container.decode(Int.self, forKey: .code)
        } catch (let error) {
            print(error)
        }
    }
    
    init() {
        
    }
    
}
