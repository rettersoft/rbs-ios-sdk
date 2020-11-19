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



enum NetworkError : Error {
    case connection_lost
}

class BaseErrorResponse: Decodable, Error {
    var code: Int? = 512 // unknown
    
    var httpStatusCode: Int? = 512 // unknown
    var displayDialog: Bool {
        get {
            guard let httpStatus = self.httpStatusCode else { return false }
            if httpStatus >= 400 && httpStatus < 500 { return true }
            
            guard let code = self.code else { return false }
            
            if (0...121).contains(code) || (1000...1021).contains(code) { return true }
            
            return false
        }
    }
    
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
    
    init(en:String, tr:String, code:Int, displayDialog:Bool) {
        
        self.code = code
        self.httpStatusCode = code
    }
    
    static func createFakeErrorResponse() -> Response {
        return Response(statusCode: 475, data: Data())
    }
    
    
}
