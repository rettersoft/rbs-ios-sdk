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
        case .executeAction(_): return "/executeAction"
        case .refreshToken(_): return "/public/auth-refresh"
        case .authWithCustomToken(_): return "/public/auth"
        }
    }
    
    var parameters: [String: Any] {
        switch self {
        case .getAnonymToken(_): return ["projectId":"7b7ecec721d54629bed1d3b1aec210e8", "clientId": "rbs.user.enduser"] //Mapper().toJSON(request)
        case .executeAction(_): return [:]
        case .refreshToken(let request): return ["refreshToken":request.refreshToken!]
        case .authWithCustomToken(let request): return ["customToken": request.customToken!]
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
//        case .getAnonymToken(_): return .none
//        case .executeAction(_): return .none
//        case .refreshToken(_): return .none
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
            return .requestParameters(parameters: self.parameters, encoding: JSONEncoding.default)
        default:
            return .requestParameters(parameters: self.parameters, encoding: URLEncoding.default)
        }
    }
    var headers: [String : String]? {
        
        var headers: [String: String] = [:]
//        headers["Content-Type"] = "application/json"
        headers["OperationChannel"] = "ios"
//        headers["ClientVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

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
