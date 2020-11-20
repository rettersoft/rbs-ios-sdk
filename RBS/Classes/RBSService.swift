//
//  RBSService.swift
//  RBS
//
//  Created by Baran Baygan on 19.11.2020.
//


import Foundation
import Moya
import ObjectMapper



enum RBSService {
    
    case getAnonymToken(request: GetAnonymTokenRequest)
    case executeAction(request: ExecuteActionRequest)
    case refreshToken(request: RefreshTokenRequest)
    case authWithCustomToken(request: AuthWithCustomTokenRequest)
    
    var endPoint: String {
        switch self {
        case .getAnonymToken(_): return "/public/anonymous-auth"
        case .executeAction(_): return "/user/action"
        case .refreshToken(_): return "/public/auth-refresh"
        case .authWithCustomToken(_): return "/public/auth"
        }
    }
    
    var body: [String:Any] {
        switch self {
        case .executeAction(let request):
            if let payload = request.payload {
                return payload
            }
            return [:]
        default: return [:]
        }
    }
    
    var urlParameters: [String: Any] {
        switch self {
        case .getAnonymToken(let request): return ["projectId": request.projectId!, "clientId": "rbs.user.enduser"] //Mapper().toJSON(request)
        case .refreshToken(let request): return ["refreshToken":request.refreshToken!]
        case .authWithCustomToken(let request): return ["customToken": request.customToken!]
        case .executeAction(let request):
            if let accessToken = request.accessToken, let action = request.actionName {
                return [
                    "auth": accessToken,
                    "action": action
                ]
            } else {
                return [:]
            }
        }
    }
    
    var httpMethod: Moya.Method {
        switch self {
        case .executeAction: return .post
        default: return .get
        }
    }
}


extension RBSService: TargetType, AccessTokenAuthorizable {
    
    var authorizationType: AuthorizationType? {
        switch self {
        default: return .none
        }
    }
    
    var baseURL: URL {
        URL(string: "https://core-test.rettermobile.com")!
    }
    var path: String { return self.endPoint }
    var method: Moya.Method { return self.httpMethod }
    var sampleData: Data {
        switch self {
        default:
            return Data()
        }
    }
    var task: Task {
        switch self {
        case .executeAction(_):
            return .requestCompositeParameters(bodyParameters: self.body,
                                               bodyEncoding: JSONEncoding.default,
                                               urlParameters: self.urlParameters)
        default:
            return .requestParameters(parameters: self.urlParameters, encoding: URLEncoding.default)
        }
    }
    var headers: [String : String]? {
        
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"
        headers["x-rbs-sdk-client"] = "ios"

        switch self {
        case .executeAction:
            headers["Content-Type"] = "application/json"
            break
        default:
            break
        }
        
        return headers
    }
}

extension RBSService : CachePolicyGettable {
    var cachePolicy: URLRequest.CachePolicy {
        get {
            .reloadIgnoringLocalAndRemoteCacheData
        }
    }
}

protocol CachePolicyGettable {
    var cachePolicy: URLRequest.CachePolicy { get }
}

final class CachePolicyPlugin: PluginType {
    public func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        if let cachePolicyGettable = target as? CachePolicyGettable {
            var mutableRequest = request
             mutableRequest.cachePolicy = cachePolicyGettable.cachePolicy
            return mutableRequest
        }
        
        return request
    }
}
