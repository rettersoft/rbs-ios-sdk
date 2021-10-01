//
//  RBSService.swift
//  RBS
//
//  Created by Baran Baygan on 19.11.2020.
//


import Foundation
import Moya
import ObjectMapper


var globalRbsRegion:RbsRegion = .euWest1

enum RBSService {
    
    case getAnonymToken(request: GetAnonymTokenRequest)
    case executeAction(request: ExecuteActionRequest)
    
    case refreshToken(request: RefreshTokenRequest)
    case authWithCustomToken(request: AuthWithCustomTokenRequest)
    
    var endPoint: String {
        switch self {
        case .getAnonymToken(_): return "/public/anonymous-auth"
        case .executeAction(let request):
            return "/user/action/\(request.projectId!)/\(request.actionName!)"
            
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
    
    func isGetAction(_ action:String?) -> Bool {
        guard let actionName = action else { return false }
        let actionType = actionName.split(separator: ".")[2]
        return actionType == "get"
    }
    
    var urlParameters: [String: Any] {
        switch self {
        case .getAnonymToken(let request):
            return [
                "projectId": request.projectId!,
                "platform": "IOS"
            ]
        case .refreshToken(let request): return ["refreshToken":request.refreshToken!, "platform": "IOS"]
        case .authWithCustomToken(let request): return ["customToken": request.customToken!, "platform": "IOS"]
            
        case .executeAction(let request):
            
            if let action = request.actionName {
               
                let accessToken = request.accessToken != nil ? request.accessToken! : ""
                
                if(self.isGetAction(action)) {
                    let payload: [String:Any] = request.payload == nil ? [:] : request.payload!
                    let data: Data = try! JSONSerialization.data(withJSONObject:payload, options: JSONSerialization.WritingOptions.prettyPrinted)
                    let dataBase64 = data.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                    var parameters =  [
                        "auth": accessToken,
                        "platform": "IOS",
                        "data": dataBase64!
                    ]
                    
                    if let culture = request.culture {
                        parameters["culture"] = culture
                    }
                    
                    return parameters
                } else {
                    var parameters = ["auth": accessToken]
                    if let culture = request.culture {
                        parameters["culture"] = culture
                    }
                    
                    return parameters
                }
                
            } else {
                
                return [:]
                
            }
        }
    }
    
    var httpMethod: Moya.Method {
        switch self {
        case .executeAction(let request):
            
            if(self.isGetAction(request.actionName)) {
                return .get
            }
            
            return .post
            
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
        switch self {
        case .executeAction(let request):
            if(self.isGetAction(request.actionName)) {
                return URL(string: globalRbsRegion.getUrl)!
            }
            return URL(string: globalRbsRegion.postUrl)!
        default:
            return URL(string: globalRbsRegion.postUrl)!
        }
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
        case .executeAction(let request):
            
            if(self.isGetAction(request.actionName)) {
                return .requestParameters(parameters: self.urlParameters, encoding: URLEncoding.default)
            }
            
            return .requestCompositeParameters(bodyParameters: self.body,
                                               bodyEncoding: JSONEncoding.default,
                                               urlParameters: self.urlParameters)
        default:
            return .requestParameters(parameters: self.urlParameters, encoding: URLEncoding.default)
        }
    }
    func getLanguageISO() -> String {
        let locale = Locale.current
        guard let languageCode = locale.languageCode,
              let regionCode = locale.regionCode else {
            return "en_US"
        }
        return languageCode + "_" + regionCode
    }
    var headers: [String : String]? {
        
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"
        headers["x-rbs-sdk-client"] = "ios"
        
        switch self {
        case .executeAction(let request):
            if var reqHeaders = request.headers {
                if(!reqHeaders.keys.contains { $0 == "accept-language" || $0 == "Accept-Language" }) {
                    reqHeaders["accept-language"] = self.getLanguageISO()
                }
                for h in reqHeaders {
                    headers[h.key] = h.value
                }
            }
            
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
